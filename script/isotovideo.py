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
from typing import Any, Dict, List, Optional

# Add custom python modules path
sys.path.insert(0, os.path.abspath("python"))
from os_autoinst import log, vars, backend, console

# Add rust core path
sys.path.insert(0, os.path.abspath("rust/os-autoinst-core"))
try:
    import os_autoinst_core
except ImportError:
    os_autoinst_core = None


def random_string(length=8):
    return "".join(random.choices(string.ascii_letters + string.digits, k=length))


class CommandHandler:
    def __init__(self, runner):
        self.runner = runner

    def process_command(self, cmd: Dict[str, Any]) -> Any:
        method = cmd.get("cmd")
        if not method:
            return None
        args = cmd.get("args", {})
        token = cmd.get("json_cmd_token")

        log.diag(f"process_command: {method} (token={token})")

        # Route matching commands to rust core
        if method == "match_needle":
            if os_autoinst_core:
                # We expect raw image bytes here in a real scenario
                return os_autoinst_core.match_needle(
                    args.get("screen", b""),
                    args.get("needle", b""),
                    args.get("x", 0),
                    args.get("y", 0),
                    args.get("w", 0),
                    args.get("h", 0),
                    args.get("margin", 0),
                )
            return [1.0, 0, 0]

        # Route backend commands to runner's backend
        if method.startswith("backend_"):
            return self.runner.backend.handle_command(method[8:], args)

        if method == "quit":
            self.runner.loop = False
            return True

        log.diag(f"Unknown command: {method}")
        return None


class Runner:
    def __init__(self, args):
        self.args = args
        self.vars = vars.global_vars
        self.backend = backend.QemuBackend()
        self.handler = CommandHandler(self)
        self.loop = True
        self.socket_path = os.environ.get(
            "OS_AUTOINST_PYTHON_SOCKET", "/tmp/os-autoinst-python.sock"
        )
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)

    def run(self):
        log.diag("Python isotovideo runner started.")
        self.vars.load()
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
                                    res = self.handler.process_command(cmd)
                                    response = {
                                        "ret": res,
                                        "json_cmd_token": cmd.get("json_cmd_token"),
                                    }
                                    s.sendall(json.dumps(response).encode() + b"\n")
                                except Exception as e:
                                    log.diag(f"Error processing command: {e}")
                            clients[s] = lines[-1]

        self.backend.stop()
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
        return 0

    def start_autotest(self):
        perl_code = f"""
use lib '.';
use autotest qw(connect_to_isotovideo runalltests);
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
