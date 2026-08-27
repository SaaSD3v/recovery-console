#!/usr/bin/env python3
import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit(f"usage: {sys.argv[0]} <config.h> <rotation 0-3>")

path = Path(sys.argv[1])
rotation = int(sys.argv[2])
if rotation not in (0, 1, 2, 3):
    raise SystemExit("rotation must be 0, 1, 2, or 3")

text = path.read_text()
pattern = re.compile(r"(?m)^\s*#\s*define\s+ROTATION\s+.*$")
if not pattern.search(text):
    raise SystemExit(f"ROTATION define not found in {path}")

text, count = pattern.subn(f"#define ROTATION {rotation}", text, count=1)
path.write_text(text)
print(f"patched {path}: ROTATION={rotation}")
