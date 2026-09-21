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

# Device profiles can expose a named compile-time selector such as
# CHANNEL_ROTATION/ALBUS_ROTATION and then map ROTATION to it.
# Prefer patching that selector so the profile remains internally consistent.
patterns = [
    re.compile(r"(?m)^(\s*#\s*define\s+CHANNEL_ROTATION\s+)\d+\s*$"),
    re.compile(r"(?m)^(\s*#\s*define\s+ALBUS_ROTATION\s+)\d+\s*$"),
    re.compile(r"(?m)^(\s*#\s*define\s+ROTATION\s+)\d+\s*$"),
]

for pattern in patterns:
    if pattern.search(text):
        text, count = pattern.subn(lambda m: f"{m.group(1)}{rotation}", text, count=1)
        path.write_text(text)
        print(f"patched {path}: rotation={rotation}")
        break
else:
    raise SystemExit(
        f"no numeric CHANNEL_ROTATION, ALBUS_ROTATION, or ROTATION define found in {path}"
    )
