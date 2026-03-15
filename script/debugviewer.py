#!/usr/bin/env python3
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

import sys
import tkinter as tk
from PIL import Image, ImageTk
import os


def main():
    if len(sys.argv) < 2:
        print("Usage: debugviewer path/to/image.png")
        sys.exit(1)

    path = sys.argv[1]
    root = tk.Tk()
    root.title(f"debugviewer - {path}")

    label = tk.Label(root)
    label.pack()

    def update():
        if os.path.exists(path):
            try:
                # Open image and convert to PhotoImage
                img = Image.open(path)
                # Resize if it doesn't fit? Original C++ didn't resize.
                photo = ImageTk.PhotoImage(img)
                label.config(image=photo)
                label.image = photo
            except Exception as e:
                # Silently ignore errors during reading (e.g. file busy)
                pass

        # Schedule next update in 300ms
        root.after(300, update)

    update()

    # Handle escape key to exit
    root.bind("<Escape>", lambda e: root.destroy())

    root.mainloop()


if __name__ == "__main__":
    main()
