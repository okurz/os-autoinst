# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import json
import os


class Vars:
    def __init__(self, filename: str = "vars.json"):
        self.filename = filename
        self.data = {}

    def load(self):
        if not os.path.exists(self.filename):
            return
        with open(self.filename, "r") as f:
            self.data = json.load(f)

    def save(self):
        with open(self.filename, "w") as f:
            json.dump(self.data, f, indent=4)

    def get(self, key, default=None):
        return self.data.get(key.upper(), default)

    def set(self, key, value):
        self.data[key.upper()] = value


# Global vars singleton
global_vars = Vars()
