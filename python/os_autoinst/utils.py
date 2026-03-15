# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import subprocess
import re
from typing import Optional, Dict, Any, List
from .log import diag, fctinfo
from .vars import global_vars


def git_rev_parse(dirname: str) -> str:
    try:
        res = subprocess.run(
            ["git", "-C", dirname, "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return res.stdout.strip()
    except subprocess.CalledProcessError:
        return "UNKNOWN"


def checkout_git_repo_and_branch(dir_variable: str, repo: Optional[str] = None):
    val = global_vars.get(dir_variable) or repo
    if not val:
        return None

    # Very basic clone logic for now
    if val.startswith(("http://", "https://", "git://", "ssh://")):
        # branch is in fragment like URL#branch
        if "#" in val:
            url, branch = val.split("#", 1)
        else:
            url, branch = val, None

        local_path = url.split("/")[-1].replace(".git", "")
        if not os.path.exists(local_path):
            fctinfo(f"Cloning {url} into {local_path}")
            cmd = ["git", "clone", url, local_path]
            if branch:
                cmd.extend(["--branch", branch])
            subprocess.run(cmd, check=True)

        abs_path = os.path.abspath(local_path)
        global_vars.set(dir_variable, abs_path)
        return abs_path
    return None


def load_test_schedule():
    # In a real implementation, this would parse main.pm or similar
    # For now, we just log that we are loading it
    casedir = global_vars.get("CASEDIR")
    if casedir:
        fctinfo(f"Loading test schedule from {casedir}")

    schedule = global_vars.get("SCHEDULE")
    if schedule:
        fctinfo(f"Enforced schedule: {schedule}")
