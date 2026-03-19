#!/usr/bin/env python3
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
"""Debug viewer for os-autoinst screenshots."""

import sys
import tkinter as tk
from pathlib import Path

from PIL import Image, ImageTk


class DebugViewer(tk.Tk):
    """A simple image viewer that automatically reloads an image file."""

    def __init__(self, image_path: str) -> None:
        """Initialize the viewer with the path to the image to watch."""
        super().__init__()
        self.title("Display window")
        self.image_path = Path(image_path)
        self.label = tk.Label(self)
        self.label.pack()
        self.bind("<Escape>", lambda _: self.destroy())
        self.bind("<Key>", lambda _: self.destroy())
        self.update_image()

    def update_image(self) -> None:
        """Reload the image from disk and update the display."""
        if self.image_path.exists():
            try:
                img = Image.open(self.image_path)
                photo = ImageTk.PhotoImage(img)
                self.label.configure(image=photo)  # type: ignore[arg-type]
                self.label.image = photo  # type: ignore[attr-defined]
            except (OSError, SyntaxError):
                # Ignore transient loading errors (e.g. while file is being written)
                pass
        self.after(300, self.update_image)


def main() -> None:
    """Entry point for the debug viewer."""
    expected_args_len = 2
    if len(sys.argv) != expected_args_len:
        sys.stderr.write(f"Usage: {sys.argv[0]} qemuscreenshot/last.png\n")
        sys.exit(-1)

    app = DebugViewer(sys.argv[1])
    app.mainloop()


if __name__ == "__main__":
    main()
