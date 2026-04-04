#!/usr/bin/env python3
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
import subprocess
import shutil
import os
from pathlib import Path
from typing import Optional
import typer
import gzip
import lzma
import zlib

app = typer.Typer(help="Extract kernel and initrd from a disk image using guestfs-tools.")


def decompress_kernel(compressed_path: Path, output_path: Path):
    """Decompress a vmlinuz image to a raw vmlinux ELF."""
    data = compressed_path.read_bytes()

    # Try different offsets and decompressors
    # We use zlib for gzip to handle headers/trailing data more flexibly
    decompressors = [
        (b"\x1f\x8b\x08", lambda d: zlib.decompress(d, 31)),
        (b"\xfd\x37\x7a\x58\x5a", lzma.decompress),
        # Zstd usually requires external tool as python-zstandard is not stdlib
    ]

    for magic, decompress_fn in decompressors:
        offset = data.find(magic)
        if offset != -1:
            try:
                output_path.write_bytes(decompress_fn(data[offset:]))
                typer.echo(f"Decompressed kernel using internal decompressor at offset {offset}.")
                return
            except Exception:
                continue

    # Fallback to system tools (especially for zstd)
    for magic, tool in [
        (b"\x1f\x8b\x08", "zcat"),
        (b"\xfd\x37\x7a\x58\x5a", "xzcat"),
        (b"\x28\xb5\x2f\xfd", "zstdcat"),
    ]:
        offset = data.find(magic)
        if offset != -1 and shutil.which(tool):
            try:
                subprocess.run(
                    [tool], input=data[offset:], stdout=output_path.open("wb"), check=True, stderr=subprocess.DEVNULL
                )
                typer.echo(f"Decompressed kernel using {tool} at offset {offset}.")
                return
            except subprocess.CalledProcessError:
                continue

    typer.echo("Warning: Could not decompress kernel. Copying as is.")
    shutil.copy(compressed_path, output_path)


@app.command()
def extract(
    image: Path = typer.Argument(..., help="Path to the disk image."),
    output_dir: Path = typer.Option(Path("."), "--output-dir", "-o", help="Directory to save extracted assets."),
):
    """Extract kernel and initrd from a disk image."""
    image = image.absolute()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Use guestfish with inspection to find kernel and initrd
    # This handles Btrfs subvolumes and partitions automatically
    typer.echo(f"Inspecting {image} using guestfish...")
    try:
        files = []
        # Search in /boot and /usr/lib/modules
        for search_dir in ["/boot", "/usr/lib/modules"]:
            try:
                cmd = ["guestfish", "--ro", "-a", str(image), "-i", "find", search_dir]
                res = subprocess.run(cmd, capture_output=True, text=True, check=True)
                # find returns relative paths to the search_dir
                files.extend([os.path.join(search_dir, f.lstrip("/")) for f in res.stdout.strip().split("\n")])
            except subprocess.CalledProcessError:
                continue

        vmlinuz_path = None
        initrd_path = None

        # Priority: find the latest version
        for f in sorted(files, reverse=True):
            if "vmlinuz-" in f or f.endswith("/vmlinuz"):
                if not vmlinuz_path or "/boot/" in f or "/usr/lib/modules/" in f:
                    vmlinuz_path = f
            if "initrd" in f:
                if not initrd_path or "/boot/" in f or "/usr/lib/modules/" in f:
                    initrd_path = f

        if not vmlinuz_path or not initrd_path:
            raise RuntimeError("Could not find kernel or initrd in the image.")

        typer.echo(f"Found Kernel: {vmlinuz_path}")
        typer.echo(f"Found Initrd: {initrd_path}")

        # Download files
        ext_vmlinuz = output_dir / "vmlinuz.tmp"
        ext_initrd = output_dir / "initrd.img"

        subprocess.run(
            [
                "guestfish",
                "--ro",
                "-a",
                str(image),
                "-i",
                "download",
                vmlinuz_path,
                str(ext_vmlinuz),
                ":",
                "download",
                initrd_path,
                str(ext_initrd),
            ],
            check=True,
        )

        decompress_kernel(ext_vmlinuz, output_dir / "vmlinux")
        ext_vmlinuz.unlink()

        typer.echo("-------------------------------------------------------")
        typer.echo(f"Successfully extracted assets to {output_dir}")
        typer.echo(f"  Kernel: {output_dir}/vmlinux (ELF)")
        typer.echo(f"  Initrd: {output_dir}/initrd.img")
        typer.echo("-------------------------------------------------------")

    except subprocess.CalledProcessError as e:
        typer.echo(f"Error using guestfish: {e}", err=True)
        raise typer.Exit(1)


if __name__ == "__main__":
    app()
