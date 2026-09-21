#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <magiskboot> <base-recovery.img> <recovery-console-bin> <output.img> [seclabel]" >&2
  exit 2
}

[ "$#" -ge 4 ] || usage
MAGISKBOOT=$(readlink -f "$1")
BASE=$(readlink -f "$2")
BIN=$(readlink -f "$3")
OUT=$(readlink -m "$4")
SECLABEL="${5:-u:r:recovery:s0}"

[ -x "$MAGISKBOOT" ] || { echo "ERROR: magiskboot is not executable" >&2; exit 1; }
[ -s "$BASE" ] || { echo "ERROR: base recovery image missing/empty" >&2; exit 1; }
[ -x "$BIN" ] || { echo "ERROR: recovery-console binary missing/not executable" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$BASE" "$WORK/base.img"
cd "$WORK"

# Albus known-good builder explicitly preserves legacy image layout/compression.
"$MAGISKBOOT" unpack -n base.img
[ -s ramdisk.cpio ] || { echo "ERROR: magiskboot did not extract ramdisk.cpio" >&2; exit 1; }

RAW="$WORK/ramdisk.raw.cpio"
COMPRESSION="raw"
if cpio -it < ramdisk.cpio >/dev/null 2>&1; then
  cp -f ramdisk.cpio "$RAW"
else
  DESC=$(file -b ramdisk.cpio || true)
  MAGIC=$(xxd -p -l 8 ramdisk.cpio 2>/dev/null | tr -d '\n')
  case "$MAGIC" in
    1f8b*) COMPRESSION=gzip ;;
    04224d18*) COMPRESSION=lz4 ;;
    02214c18*) COMPRESSION=lz4_legacy ;;
    fd377a585a00*) COMPRESSION=xz ;;
    425a68*) COMPRESSION=bzip2 ;;
    *)
      case "$DESC" in
        *gzip*) COMPRESSION=gzip ;;
        *XZ*) COMPRESSION=xz ;;
        *LZMA*) COMPRESSION=lzma ;;
        *bzip2*) COMPRESSION=bzip2 ;;
        *LZ4*) COMPRESSION=lz4 ;;
        *) echo "ERROR: unsupported Albus ramdisk compression: $DESC" >&2; exit 1 ;;
      esac
      ;;
  esac
  "$MAGISKBOOT" decompress ramdisk.cpio "$RAW"
fi

[ -s "$RAW" ] || { echo "ERROR: failed to decompress Albus ramdisk" >&2; exit 1; }
cpio -it < "$RAW" > "$WORK/ramdisk.list" 2>/dev/null

CONSOLE_ENTRY='system/bin/recovery-console'
CONSOLE_EXEC='/system/bin/recovery-console'

PATCH="$WORK/patch"
VERIFY="$WORK/verify-ramdisk"
mkdir -p "$PATCH" "$VERIFY"
(
  cd "$PATCH"
  "$MAGISKBOOT" cpio "$RAW" "extract"
)

python3 - "$PATCH" "$CONSOLE_EXEC" "$SECLABEL" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
exe = sys.argv[2]
seclabel = sys.argv[3]
service_re = re.compile(r'^service[ \t]+recovery[ \t]+\S+.*$')
markers = [
    ("# BEGIN RECOVERY-CONSOLE-CHANNEL", "# END RECOVERY-CONSOLE-CHANNEL"),
    ("# BEGIN RECOVERY-CONSOLE-BUILDER", "# END RECOVERY-CONSOLE-BUILDER"),
    ("# BEGIN RECOVERY-CONSOLE-PERMANENT", "# END RECOVERY-CONSOLE-PERMANENT"),
    ("# BEGIN RECOVERY-CONSOLE-OFFICIAL-PERMANENT", "# END RECOVERY-CONSOLE-OFFICIAL-PERMANENT"),
]

modified = []
stock_hosts = []

def strip_marked(text: str) -> str:
    for start, end in markers:
        while start in text and end in text:
            a = text.index(start)
            b = text.index(end, a) + len(end)
            text = text[:a].rstrip() + "\n" + text[b:].lstrip("\n")
    return text

for path in sorted(root.rglob("*.rc")):
    try:
        text = path.read_text(errors="surrogateescape")
    except OSError:
        continue
    original = text
    text = strip_marked(text)
    lines = text.splitlines()
    changed = text != original
    i = 0
    while i < len(lines):
        if not service_re.match(lines[i]):
            i += 1
            continue
        stock_hosts.append(path)
        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line and not line[0].isspace() and not line.lstrip().startswith("#"):
                break
            j += 1
        block = lines[i:j]
        if not any(x.strip() == "disabled" for x in block):
            lines.insert(j, "    disabled")
            changed = True
            j += 1
        i = j
    new_text = "\n".join(lines)
    if text.endswith("\n") or new_text:
        new_text += "\n"
    if changed:
        path.write_text(new_text, errors="surrogateescape")
        modified.append(path)

if not stock_hosts:
    raise SystemExit("no stock Android init service named recovery was found")

host = root / "init.rc"
if not host.is_file():
    raise SystemExit("/init.rc is missing from ramdisk")

for path in sorted(root.rglob("*.rc")):
    text_check = path.read_text(errors="surrogateescape")
    if re.search(r'(?m)^service[ \\t]+recovery-console[ \\t]+', text_check):
        raise SystemExit(f"unexpected pre-existing recovery-console service outside managed block: {path}")

text = host.read_text(errors="surrogateescape")
block = [
    "# BEGIN RECOVERY-CONSOLE-OFFICIAL-PERMANENT",
    f"service recovery-console {exe}",
    "    user root",
    "    group root",
    "    oneshot",
    "    disabled",
]
if seclabel and seclabel.lower() != "none":
    block.append(f"    seclabel {seclabel}")
block += [
    "",
    "on boot",
    "    start recovery-console",
    "# END RECOVERY-CONSOLE-OFFICIAL-PERMANENT",
]
host.write_text(text.rstrip() + "\n\n" + "\n".join(block) + "\n",
                errors="surrogateescape")
if host not in modified:
    modified.append(host)

(root / ".recovery-console-modified-rc").write_text(
    "\n".join(str(p.relative_to(root)) for p in modified) + "\n"
)
PY

[ -s "$PATCH/.recovery-console-modified-rc" ] || { echo "ERROR: no init rc file changed" >&2; exit 1; }

CPIO_CMDS=()
if [ ! -e "$PATCH/system" ]; then
  CPIO_CMDS+=("mkdir 0755 system")
elif [ ! -d "$PATCH/system" ]; then
  echo "ERROR: /system exists in ramdisk but is not a directory" >&2
  exit 1
fi
if [ ! -e "$PATCH/system/bin" ]; then
  CPIO_CMDS+=("mkdir 0755 system/bin")
elif [ ! -d "$PATCH/system/bin" ]; then
  echo "ERROR: /system/bin exists in ramdisk but is not a directory" >&2
  exit 1
fi

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mode="0$(stat -c '%a' "$PATCH/$rel")"
  CPIO_CMDS+=("rm $rel")
  CPIO_CMDS+=("add $mode $rel $PATCH/$rel")
done < "$PATCH/.recovery-console-modified-rc"

CPIO_CMDS+=("rm $CONSOLE_ENTRY")
CPIO_CMDS+=("add 0755 $CONSOLE_ENTRY $BIN")
"$MAGISKBOOT" cpio "$RAW" "${CPIO_CMDS[@]}"

(
  cd "$VERIFY"
  "$MAGISKBOOT" cpio "$RAW" "extract"
)

test -x "$VERIFY/$CONSOLE_ENTRY"
cmp -s "$BIN" "$VERIFY/$CONSOLE_ENTRY"

python3 - "$VERIFY" "$CONSOLE_EXEC" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
exe = sys.argv[2]
service_re = re.compile(r'^service[ \t]+recovery[ \t]+\S+.*$')
stock = console = autostart = 0

for path in root.rglob("*.rc"):
    try:
        lines = path.read_text(errors="surrogateescape").splitlines()
    except OSError:
        continue

    for i, line in enumerate(lines):
        if service_re.match(line):
            stock += 1
            j = i + 1
            block = []
            while j < len(lines):
                nxt = lines[j]
                if nxt and not nxt[0].isspace() and not nxt.lstrip().startswith("#"):
                    break
                block.append(nxt)
                j += 1
            if not any(x.strip() == "disabled" for x in block):
                raise SystemExit(f"{path}: stock recovery service is not disabled")

        if line.strip() == f"service recovery-console {exe}":
            console += 1
            j = i + 1
            block = []
            while j < len(lines):
                nxt = lines[j]
                if nxt and not nxt[0].isspace() and not nxt.lstrip().startswith("#"):
                    break
                block.append(nxt)
                j += 1
            if not any(x.strip() == "disabled" for x in block):
                raise SystemExit(f"{path}: recovery-console service is not disabled")

    text = "\n".join(lines)
    if re.search(r'(?m)^on boot\s*$[\s\S]*?^[ \t]+start recovery-console\s*$', text):
        autostart += 1

if stock == 0:
    raise SystemExit("stock recovery service missing")
if console != 1:
    raise SystemExit(f"expected exactly one recovery-console service, found {console}")
if autostart == 0:
    raise SystemExit("on boot -> start recovery-console is missing")

init_text = (root / "init.rc").read_text(errors="surrogateescape")
if f"service recovery-console {exe}" not in init_text:
    raise SystemExit("recovery-console service must be defined in /init.rc per upstream README")
if not re.search(r'(?m)^on boot\\s*$[\\s\\S]*?^[ \\t]+start recovery-console\\s*$', init_text):
    raise SystemExit("recovery-console boot trigger must be defined in /init.rc per upstream README")
PY

# The known-good Albus TWRP ramdisk is LZMA. Preserve the detected family exactly.
if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAW" ramdisk.cpio
else
  rm -f ramdisk.cpio
  "$MAGISKBOOT" "compress=$COMPRESSION" "$RAW" ramdisk.cpio
fi
[ -s ramdisk.cpio ] || { echo "ERROR: final ramdisk.cpio missing" >&2; exit 1; }

ROUNDTRIP="$WORK/roundtrip.cpio"
if [ "$COMPRESSION" = raw ]; then
  cp -f ramdisk.cpio "$ROUNDTRIP"
else
  "$MAGISKBOOT" decompress ramdisk.cpio "$ROUNDTRIP"
fi
cmp -s "$RAW" "$ROUNDTRIP" || { echo "ERROR: ramdisk compression round-trip mismatch" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
"$MAGISKBOOT" repack -n base.img "$OUT"
[ -s "$OUT" ] || { echo "ERROR: repack did not create output image" >&2; exit 1; }

# Verify permanent integration again from the final image.
FINAL="$WORK/final"
mkdir -p "$FINAL"
(
  cd "$FINAL"
  "$MAGISKBOOT" unpack -n "$OUT" >/dev/null
)
[ -s "$FINAL/ramdisk.cpio" ]
FINAL_RAW="$WORK/final.raw.cpio"
if cpio -it < "$FINAL/ramdisk.cpio" >/dev/null 2>&1; then
  cp -f "$FINAL/ramdisk.cpio" "$FINAL_RAW"
else
  "$MAGISKBOOT" decompress "$FINAL/ramdisk.cpio" "$FINAL_RAW"
fi
FINAL_TREE="$WORK/final-tree"
mkdir -p "$FINAL_TREE"
(
  cd "$FINAL_TREE"
  "$MAGISKBOOT" cpio "$FINAL_RAW" "extract"
)
test -x "$FINAL_TREE/$CONSOLE_ENTRY"
grep -R -q '^service recovery-console /system/bin/recovery-console$' "$FINAL_TREE" --include='*.rc'
grep -R -q '^[[:space:]]*start recovery-console$' "$FINAL_TREE" --include='*.rc'

python3 - "$FINAL_TREE" <<'PY'
from pathlib import Path
import re
import sys
root=Path(sys.argv[1])
rx=re.compile(r'^service[ \t]+recovery[ \t]+\S+.*$')
found=0
for p in root.rglob("*.rc"):
    try: lines=p.read_text(errors="surrogateescape").splitlines()
    except OSError: continue
    for i,line in enumerate(lines):
        if not rx.match(line): continue
        found += 1
        j=i+1; block=[]
        while j < len(lines):
            x=lines[j]
            if x and not x[0].isspace() and not x.lstrip().startswith("#"): break
            block.append(x); j += 1
        if not any(x.strip()=="disabled" for x in block):
            raise SystemExit(f"{p}: stock recovery service is not disabled in final image")
if not found:
    raise SystemExit("stock recovery service missing in final image")
PY

printf '%s\n' \
  "Integrated Recovery Console permanently into Albus recovery" \
  "  base          : $BASE" \
  "  output        : $OUT" \
  "  compression   : $COMPRESSION" \
  "  console path  : $CONSOLE_EXEC" \
  "  stock recovery: disabled" \
  "  service block : /init.rc" \
  "  console boot  : automatic (on boot)" \
  "  integration   : upstream README permanent init.rc method" \
  "  image mode    : magiskboot unpack/repack -n preserved"

sha256sum "$OUT"
, init_text):
    raise SystemExit("recovery-console boot trigger must be defined in /init.rc per upstream README")
PY

# The known-good Albus TWRP ramdisk is LZMA. Preserve the detected family exactly.
if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAW" ramdisk.cpio
else
  rm -f ramdisk.cpio
  "$MAGISKBOOT" "compress=$COMPRESSION" "$RAW" ramdisk.cpio
fi
[ -s ramdisk.cpio ] || { echo "ERROR: final ramdisk.cpio missing" >&2; exit 1; }

ROUNDTRIP="$WORK/roundtrip.cpio"
if [ "$COMPRESSION" = raw ]; then
  cp -f ramdisk.cpio "$ROUNDTRIP"
else
  "$MAGISKBOOT" decompress ramdisk.cpio "$ROUNDTRIP"
fi
cmp -s "$RAW" "$ROUNDTRIP" || { echo "ERROR: ramdisk compression round-trip mismatch" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
"$MAGISKBOOT" repack -n base.img "$OUT"
[ -s "$OUT" ] || { echo "ERROR: repack did not create output image" >&2; exit 1; }

# Verify permanent integration again from the final image.
FINAL="$WORK/final"
mkdir -p "$FINAL"
(
  cd "$FINAL"
  "$MAGISKBOOT" unpack -n "$OUT" >/dev/null
)
[ -s "$FINAL/ramdisk.cpio" ]
FINAL_RAW="$WORK/final.raw.cpio"
if cpio -it < "$FINAL/ramdisk.cpio" >/dev/null 2>&1; then
  cp -f "$FINAL/ramdisk.cpio" "$FINAL_RAW"
else
  "$MAGISKBOOT" decompress "$FINAL/ramdisk.cpio" "$FINAL_RAW"
fi
FINAL_TREE="$WORK/final-tree"
mkdir -p "$FINAL_TREE"
(
  cd "$FINAL_TREE"
  "$MAGISKBOOT" cpio "$FINAL_RAW" "extract"
)
test -x "$FINAL_TREE/$CONSOLE_ENTRY"
grep -R -q '^service recovery-console /system/bin/recovery-console$' "$FINAL_TREE" --include='*.rc'
grep -R -q '^[[:space:]]*start recovery-console$' "$FINAL_TREE" --include='*.rc'

python3 - "$FINAL_TREE" <<'PY'
from pathlib import Path
import re
import sys
root=Path(sys.argv[1])
rx=re.compile(r'^service[ \t]+recovery[ \t]+\S+.*$')
found=0
for p in root.rglob("*.rc"):
    try: lines=p.read_text(errors="surrogateescape").splitlines()
    except OSError: continue
    for i,line in enumerate(lines):
        if not rx.match(line): continue
        found += 1
        j=i+1; block=[]
        while j < len(lines):
            x=lines[j]
            if x and not x[0].isspace() and not x.lstrip().startswith("#"): break
            block.append(x); j += 1
        if not any(x.strip()=="disabled" for x in block):
            raise SystemExit(f"{p}: stock recovery service is not disabled in final image")
if not found:
    raise SystemExit("stock recovery service missing in final image")
PY

printf '%s\n' \
  "Integrated Recovery Console permanently into Albus recovery" \
  "  base          : $BASE" \
  "  output        : $OUT" \
  "  compression   : $COMPRESSION" \
  "  console path  : $CONSOLE_EXEC" \
  "  stock recovery: disabled" \
  "  console boot  : automatic (on boot)" \
  "  image mode    : magiskboot unpack/repack -n preserved"

sha256sum "$OUT"
