# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import sys
import datetime

direct_output = False


def diag(msg: str):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if direct_output:
        print(f"[{timestamp}] {msg}", file=sys.stderr)
    # In real isotovideo, this would also write to autoinst-log.txt
    else:
        # For now, just print to stderr
        print(f"[{timestamp}] {msg}", file=sys.stderr)


def fctwarn(msg: str, component: str = "main"):
    diag(f"WARNING: [{component}] {msg}")


def fctres(msg: str):
    diag(f"RESULT: {msg}")


def fctinfo(msg: str):
    diag(f"INFO: {msg}")


def modstate(msg: str):
    diag(f"MODSTATE: {msg}")
