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
        self.methods = {
            "match_needle": self.match_needle,
            "select_console": self.select_console,
            "set_current_test": lambda cmd: True,
            "read_serial": lambda cmd: {"serial": "", "position": 0},
            "pause_test_execution": lambda cmd: {},
            "ocr": self.ocr,
            "send_key": self.send_key,
            "backend_save_vars": self.backend_save_vars,
            "quit": self.quit,
        }

    def process_command(self, cmd: Dict[str, Any], client=None) -> Any:
        method_name = cmd.get("cmd")
        if not method_name:
            return None
        token = cmd.get("json_cmd_token")

        log.diag(f"process_command: {method_name} (token={token})")

        # Route backend commands to runner's backend
        if method_name.startswith("backend_") and method_name != "backend_save_vars":
            return self.runner.backend.handle_command(method_name[8:], cmd)

        handler = self.methods.get(method_name)
        if handler:
            try:
                return handler(cmd)
            except Exception as e:
                log.diag(f"Handler for {method_name} failed: {e}")
                return None

        log.diag(f"Unknown command: {method_name}")
        return None

    def match_needle(self, cmd: Dict[str, Any]) -> Any:
        if os_autoinst_core:
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

    def select_console(self, cmd: Dict[str, Any]) -> Any:
        console_name = cmd.get("testapi_console")
        return self.runner.select_console(console_name)

    def ocr(self, cmd: Dict[str, Any]) -> Any:
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

    def send_key(self, cmd: Dict[str, Any]) -> Any:
        key = cmd.get("key")
        if self.runner.current_console:
            keysym = console.get_keysym(key)
            if keysym:
                res1 = self.runner.current_console.send_key(keysym, True)
                res2 = self.runner.current_console.send_key(keysym, False)
                return res1 and res2
        return False

    def backend_save_vars(self, cmd: Dict[str, Any]) -> Any:
        self.runner.vars.save()
        return True

    def quit(self, cmd: Dict[str, Any]) -> Any:
        self.runner.loop = False
        return True


class JsonRpcStream:
    def __init__(self, sock):
        self.sock = sock
        self.buffer = b""

    def feed(self, data: bytes) -> List[Dict[str, Any]]:
        self.buffer += data
        messages = []
        while b"\n" in self.buffer:
            line, self.buffer = self.buffer.split(b"\n", 1)
            if not line.strip():
                continue
            try:
                messages.append(json.loads(line))
            except json.JSONDecodeError as e:
                log.diag(f"JSON parse error: {e} for line: {line}")
        return messages

    def send(self, obj: Any, token: Optional[str] = None):
        response = {"ret": obj}
        if token:
            response["json_cmd_token"] = token
        self.sock.sendall(json.dumps(response).encode() + b"\n")


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
        streams: Dict[socket.socket, JsonRpcStream] = {}

        while self.loop:
            try:
                readable, _, _ = select.select(inputs, [], [], 1.0)
            except InterruptedError:
                continue

            for s in readable:
                if s is server:
                    conn, addr = s.accept()
                    inputs.append(conn)
                    streams[conn] = JsonRpcStream(conn)
                else:
                    try:
                        data = s.recv(4096)
                    except ConnectionResetError:
                        data = None

                    if not data:
                        inputs.remove(s)
                        s.close()
                        if s in streams:
                            del streams[s]
                    else:
                        stream = streams[s]
                        for cmd in stream.feed(data):
                            try:
                                res = self.handler.process_command(cmd, client=s)
                                if res is not None:
                                    stream.send(res, cmd.get("json_cmd_token"))
                            except Exception as e:
                                log.diag(f"Error processing command: {e}")

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
            # Try to create console dynamically
            if name == "vnc":
                vnc_port = 5900 + int(self.vars.get("WORKER_ID", 0))
                self.consoles["vnc"] = console.VNCConsole("vnc", "localhost", vnc_port)
            else:
                log.diag(f"Console type for {name} not implemented yet")
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
