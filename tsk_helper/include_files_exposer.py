#!/usr/bin/env python3
"""Copy public Sleuth Kit headers into a Windows release package."""

import argparse
import re
import shutil
import sys
from pathlib import Path


HEADER_VAR = "nobase_include_HEADERS"


def parse_public_headers(makefile_path):
    text = makefile_path.read_text(encoding="utf-8")
    match = re.search(r"^" + HEADER_VAR + r"\s*=\s*(.*?)(?:\n\S|\Z)", text, re.M | re.S)
    if not match:
        raise ValueError("Could not find {} in {}".format(HEADER_VAR, makefile_path))
    
    block = match.group(1)
    block = block.replace("\\\r\n", " ").replace("\\\n", " ")
    return [item.strip() for item in block.split() if item.strip()]


def copy_headers(source_root, package_root, strict):
    makefile_path = source_root / "Makefile.am"
    headers = parse_public_headers(makefile_path)
    include_root = package_root / "include"
    copied = 0
    missing = []

    for header in headers:
        src = source_root / header
        dst = include_root / header

        if not src.exists():
            missing.append(header)
            continue

        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

    for header in missing:
        print("warning: missing public header: {}".format(header), file=sys.stderr)

    if strict and missing:
        raise FileNotFoundError("Missing {} public header(s)".format(len(missing)))

    return copied, missing


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Copy public headers into <dest>/include, preserving tsk/... paths."
    )
    parser.add_argument(
        "--source",
        default=Path.cwd(),
        type=Path,
        help="Sleuth Kit source root containing Makefile.am (default: current directory)",
    )
    parser.add_argument(
        "--dest",
        required=True,
        type=Path,
        help="Windows package root; headers are copied under <dest>/include",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail if any public header listed in Makefile.am is missing",
    )
    args = parser.parse_args(argv)

    source_root = args.source.resolve()
    package_root = args.dest.resolve()

    try:
        copied, missing = copy_headers(source_root, package_root, args.strict)
    except Exception as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 1

    print(
        "Copied {} public header(s) to {}".format(
            copied, package_root / "include"
        )
    )
    if missing:
        print("Skipped {} missing header(s)".format(len(missing)), file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
