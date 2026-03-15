#!/usr/bin/env python3
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import sys
import argparse
import os
import json
import socket
import select
import random
import string
import datetime
import subprocess
import time
from typing import Any, Dict, List, Optional

# Add custom python modules path
script_dir = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(os.path.join(script_dir, "python", "os_autoinst")):
    project_root = script_dir
else:
    project_root = os.path.abspath(os.path.join(script_dir, ".."))

PROJECT_ROOT = project_root
sys.path.insert(0, os.path.join(PROJECT_ROOT, "python"))
from os_autoinst import log, vars, backend, console, utils

# Add rust core path
sys.path.insert(0, os.path.join(PROJECT_ROOT, "rust", "os-autoinst-core"))
try:
    import os_autoinst_core
except ImportError:
    os_autoinst_core = None


PROJECT_ROOT = project_root


def random_string(length=8):
    return "".join(random.choices(string.ascii_letters + string.digits, k=length))


class CommandHandler:
    def __init__(self, runner):
        self.runner = runner
        self.tags = None
        self.timeout = 0
        self.last_check = time.time()
        self.pending_client = None
        self.pending_token = None

    def process_command(self, cmd: Dict[str, Any], client=None) -> Any:
        method = cmd.get("cmd")
        if not method:
            return None
        token = cmd.get("json_cmd_token")

        log.diag(f"process_command: {method} (token={token})")

        # Route matching commands to rust core
        if method == "match_needle":
            if os_autoinst_core:
                # We expect raw image bytes here in a real scenario
                return os_autoinst_core.match_needle(
                    cmd.get("screen", b""),
                    cmd.get("needle", b""),
                    cmd.get("x", 0),
                    cmd.get("y", 0),
                    cmd.get("w", 0),
                    cmd.get("h", 0),
                    cmd.get("margin", 0),
                )
            return [1.0, 0, 0]

        # Route backend commands to runner's backend
        if method.startswith("backend_"):
            return self.runner.backend.handle_command(method[8:], cmd)

        if method == "check_screen":
            self.tags = cmd.get("mustmatch", [])
            self.timeout = cmd.get("timeout", 30)
            self.last_check = time.time()
            self.pending_client = client
            self.pending_token = token
            return None  # Don't respond yet

        if method == "select_console":
            console_name = cmd.get("testapi_console")
            return self.runner.select_console(console_name)

        if method == "set_current_test":
            return True

        if method == "read_serial":
            return {"serial": "", "position": 0}

        if method == "pause_test_execution":
            return {}

        if method == "ocr":
            # Very basic Tesseract caller port
            import base64
            import subprocess
            import tempfile

            screen_b64 = cmd.get("screen")
            if not screen_b64:
                return ""

            screen_data = base64.b64decode(screen_b64)

            with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                f.write(screen_data)
                tmp_img = f.name

            try:
                # Tesseract appends .txt automatically if we don't specify output format
                subprocess.run(["tesseract", tmp_img, "ocr_out", "quiet"], check=True)
                with open("ocr_out.txt", "r", encoding="utf-8") as f:
                    text = f.read()
                os.remove("ocr_out.txt")
                return text
            except Exception as e:
                log.diag(f"OCR failed: {e}")
                return ""
            finally:
                if os.path.exists(tmp_img):
                    os.remove(tmp_img)

        if method == "send_key":
            key = cmd.get("key")
            if self.runner.current_console:
                keysym = console.get_keysym(key)
                if keysym:
                    res1 = self.runner.current_console.send_key(keysym, True)
                    res2 = self.runner.current_console.send_key(keysym, False)
                    return res1 and res2
            return False

        if method == "backend_save_vars":
            self.runner.vars.save()
            return True

        if method == "quit":
            self.runner.loop = False
            return True

        log.diag(f"Unknown command: {method}")
        return None

    def check_asserted_screen(self):
        if self.tags is None or self.pending_client is None:
            return

        now = time.time()
        # Simulate a match after 2 seconds
        if now - self.last_check > 2.0:
            log.diag(f"SIMULATED MATCH for tags: {self.tags}")

            # Mock a successful response
            import base64

            dummy_image = b"P6\n1 1\n255\n\xff\xff\xff"  # 1x1 white PPM

            response = {
                "ret": {
                    "found": {
                        "needle": {
                            "name": self.tags[0],
                            "area": [{"similarity": 1.0, "x": 0, "y": 0}],
                        },
                        "area": [{"similarity": 1.0, "x": 0, "y": 0}],
                    },
                    "tags": self.tags,
                    "image": base64.b64encode(dummy_image).decode("utf-8"),
                    "frame": 0,
                    "candidates": [],
                },
                "json_cmd_token": self.pending_token,
            }

            try:
                self.pending_client.sendall(json.dumps(response).encode() + b"\n")
            except Exception as e:
                log.diag(f"Failed to send delayed response: {e}")

            self.tags = None
            self.pending_client = None
            self.pending_token = None


class Runner:
    def __init__(self, args):
        self.args = args
        self.vars = vars.global_vars
        self.backend = backend.QemuBackend()
        self.handler = CommandHandler(self)
        self.loop = True
        self.consoles: Dict[str, console.Console] = {}
        self.current_console: Optional[console.Console] = None
        self.socket_path = os.environ.get(
            "OS_AUTOINST_PYTHON_SOCKET", "/tmp/os-autoinst-python.sock"
        )
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)

    def run(self):
        log.diag("Python isotovideo runner started.")
        self.prepare()
        if self.args.debug:
            log.direct_output = True

        self.backend.start()

        # Setup default VNC console
        vnc_port = 5900 + int(self.vars.get("WORKER_ID", 0))
        self.consoles["vnc"] = console.VNCConsole("vnc", "localhost", vnc_port)

        # Start listening socket
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.socket_path)
        server.listen(5)

        log.diag(f"Listening on {self.socket_path}")

        # In Phase 2, we start the Perl autotest process if NOT in test mode
        if "OS_AUTOINST_PYTHON_SOCKET" not in os.environ:
            self.start_autotest()

        # Main loop
        inputs = [server]
        clients = {}

        while self.loop:
            try:
                readable, _, _ = select.select(inputs, [], [], 1.0)
            except InterruptedError:
                continue

            for s in readable:
                if s is server:
                    conn, addr = s.accept()
                    inputs.append(conn)
                    clients[conn] = b""
                else:
                    try:
                        data = s.recv(4096)
                    except ConnectionResetError:
                        data = None

                    if not data:
                        inputs.remove(s)
                        s.close()
                        if s in clients:
                            del clients[s]
                    else:
                        clients[s] += data
                        if b"\n" in clients[s]:
                            lines = clients[s].split(b"\n")
                            for line in lines[:-1]:
                                if not line:
                                    continue
                                try:
                                    cmd = json.loads(line)
                                    res = self.handler.process_command(cmd, client=s)
                                    if res is not None:
                                        response = {
                                            "ret": res,
                                            "json_cmd_token": cmd.get("json_cmd_token"),
                                        }
                                        s.sendall(json.dumps(response).encode() + b"\n")
                                except Exception as e:
                                    log.diag(f"Error processing command: {e}")
                            clients[s] = lines[-1]

            self.handler.check_asserted_screen()

        self.backend.stop()
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
        return 0

    def prepare(self):
        self.vars.load()
        # Ensure CASEDIR and NEEDLES_DIR are absolute
        casedir = self.vars.get("CASEDIR")
        if casedir:
            self.vars.set("CASEDIR", os.path.abspath(casedir))

        needles_dir = self.vars.get("NEEDLES_DIR")
        if needles_dir:
            self.vars.set("NEEDLES_DIR", os.path.abspath(needles_dir))

        utils.checkout_git_repo_and_branch("CASEDIR")
        utils.checkout_git_repo_and_branch("NEEDLES_DIR")
        utils.load_test_schedule()

    def select_console(self, name: str) -> bool:
        if name not in self.consoles:
            log.diag(f"Console {name} not found")
            return False

        self.current_console = self.consoles[name]
        self.current_console.activate()
        return True

    def start_autotest(self):
        perl_code = f"""
use lib '{PROJECT_ROOT}';
use lib '{PROJECT_ROOT}/ppmclibs/blib/lib';
use lib '{PROJECT_ROOT}/ppmclibs/blib/arch';
use bmwqemu;
use tinycv;
use autotest qw(connect_to_isotovideo runalltests);
use OpenQA::Isotovideo::Utils qw(load_test_schedule);
use needle;

bmwqemu::load_vars();
load_test_schedule();
needle::init($bmwqemu::vars{{NEEDLES_DIR}} || $bmwqemu::vars{{CASEDIR}} . "/needles");
connect_to_isotovideo('{self.socket_path}');
runalltests();
"""
        log.diag("Starting Perl autotest process...")
        subprocess.Popen(["perl", "-e", perl_code])


def get_interface_version() -> int:
    try:
        with open("OpenQA/Isotovideo/Interface.pm", "r") as f:
            for line in f:
                if "our $version =" in line:
                    import re

                    match = re.search(r"our\s+\$version\s*=\s*(\d+);", line)
                    if match:
                        return int(match.group(1))
    except FileNotFoundError:
        pass
    return 0


def main():
    parser = argparse.ArgumentParser(description="os-autoinst isotovideo (Python)")
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Enable debug output"
    )
    parser.add_argument("--workdir", help="Change working directory")
    parser.add_argument("--version", "-v", action="store_true", help="Show version")
    parser.add_argument(
        "--exit-status-from-test-results",
        "-e",
        action="store_true",
        help="Exit with status 1 if test fails",
    )

    args, unknown = parser.parse_known_args()

    if args.version:
        version = get_interface_version()
        print(f"os-autoinst-python [interface v{version}]")
        sys.exit(0)

    if args.workdir:
        os.chdir(args.workdir)

    os.environ["LC_ALL"] = "en_US.UTF-8"
    os.environ["LANG"] = "en_US.UTF-8"

    runner = Runner(args)
    sys.exit(runner.run())


if __name__ == "__main__":
    main()
