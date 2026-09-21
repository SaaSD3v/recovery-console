#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <magiskboot> <base-twrp-installer.zip> <recovery-console-bin> <output.zip> [seclabel]" >&2
  exit 2
}

[ "$#" -ge 4 ] || usage
MAGISKBOOT=$(readlink -f "$1")
BASE_ZIP=$(readlink -f "$2")
BIN=$(readlink -f "$3")
OUT=$(readlink -m "$4")
SECLABEL="${5:-u:r:recovery:s0}"

[ -x "$MAGISKBOOT" ] || { echo "ERROR: magiskboot is not executable" >&2; exit 1; }
[ -s "$BASE_ZIP" ] || { echo "ERROR: base TWRP installer zip missing/empty" >&2; exit 1; }
[ -x "$BIN" ] || { echo "ERROR: recovery-console binary missing/not executable" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/zip"
unzip -q "$BASE_ZIP" -d "$WORK/zip"
cd "$WORK/zip"

RAMDISK=""
for candidate in ramdisk-twrp.cpio ramdisk-recovery.cpio; do
  if [ -s "$candidate" ]; then
    RAMDISK="$candidate"
    break
  fi
done
[ -n "$RAMDISK" ] || { echo "ERROR: TWRP installer ramdisk not found" >&2; exit 1; }
[ -f META-INF/com/google/android/update-binary ] || { echo "ERROR: native TWRP update-binary missing" >&2; exit 1; }
[ -f magiskboot ] || { echo "ERROR: native TWRP magiskboot missing" >&2; exit 1; }

RAW="$WORK/ramdisk.raw.cpio"
COMPRESSION="raw"
if cpio -it < "$RAMDISK" >/dev/null 2>&1; then
  cp -f "$RAMDISK" "$RAW"
else
  DESC=$(file -b "$RAMDISK" || true)
  MAGIC=$(xxd -p -l 8 "$RAMDISK" 2>/dev/null | tr -d '\n')
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
        *) echo "ERROR: unsupported ramdisk compression: $DESC" >&2; exit 1 ;;
      esac
      ;;
  esac
  "$MAGISKBOOT" decompress "$RAMDISK" "$RAW"
fi
[ -s "$RAW" ] || { echo "ERROR: failed to obtain raw ramdisk CPIO" >&2; exit 1; }
cpio -it < "$RAW" > "$WORK/ramdisk.list" 2>/dev/null

# Match the upstream README permanent-integration path exactly.
CONSOLE_ENTRY='system/bin/recovery-console'
CONSOLE_EXEC='/system/bin/recovery-console'

PATCH="$WORK/patch"
VERIFY="$WORK/verify"
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

manifest = root / ".recovery-console-modified-rc"
manifest.write_text("\n".join(str(p.relative_to(root)) for p in modified) + "\n")
PY

[ -s "$PATCH/.recovery-console-modified-rc" ] || { echo "ERROR: no init rc file changed" >&2; exit 1; }

CPIO_CMDS=()
if [ ! -d "$PATCH/system" ]; then
  CPIO_CMDS+=("mkdir 0755 system")
fi
if [ ! -d "$PATCH/system/bin" ]; then
  CPIO_CMDS+=("mkdir 0755 system/bin")
fi

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mode="0$(stat -c '%a' "$PATCH/$rel")"
  CPIO_CMDS+=("rm $rel")
  CPIO_CMDS+=("add $mode $rel $PATCH/$rel")
done < "$PATCH/.recovery-console-modified-rc"

CPIO_CMDS+=("rm recovery-console")
CPIO_CMDS+=("rm sbin/recovery-console")
CPIO_CMDS+=("rm $CONSOLE_ENTRY")
CPIO_CMDS+=("add 0755 $CONSOLE_ENTRY $BIN")
"$MAGISKBOOT" cpio "$RAW" "${CPIO_CMDS[@]}"

(
  cd "$VERIFY"
  "$MAGISKBOOT" cpio "$RAW" "extract"
)

test -x "$VERIFY/$CONSOLE_ENTRY"
cmp -s "$BIN" "$VERIFY/$CONSOLE_ENTRY"
test ! -e "$VERIFY/recovery-console"
test ! -e "$VERIFY/sbin/recovery-console"

python3 - "$VERIFY" "$CONSOLE_EXEC" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
exe = sys.argv[2]
service_re = re.compile(r'^service[ \t]+recovery[ \t]+\S+.*$')
stock = 0
console = 0
autostart = 0

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
    raise SystemExit("stock recovery service missing during verification")
if console != 1:
    raise SystemExit(f"expected exactly one recovery-console service, found {console}")
if autostart == 0:
    raise SystemExit("on boot -> start recovery-console is missing")
init_text = (root / "init.rc").read_text(errors="surrogateescape")
if f"service recovery-console {exe}" not in init_text:
    raise SystemExit("recovery-console service must be defined in /init.rc per upstream README")
if not re.search(r'(?m)^on boot\\s*$[\\s\\S]*?^[ \\t]+start recovery-console\\s*
PY

if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAW" "$RAMDISK"
else
  rm -f "$RAMDISK"
  "$MAGISKBOOT" "compress=$COMPRESSION" "$RAW" "$RAMDISK"
fi
[ -s "$RAMDISK" ] || { echo "ERROR: final ramdisk missing" >&2; exit 1; }

ROUNDTRIP="$WORK/roundtrip.cpio"
if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAMDISK" "$ROUNDTRIP"
else
  "$MAGISKBOOT" decompress "$RAMDISK" "$ROUNDTRIP"
fi
cmp -s "$RAW" "$ROUNDTRIP" || { echo "ERROR: ramdisk compression round-trip changed payload" >&2; exit 1; }

chmod 0755 META-INF/com/google/android/update-binary magiskboot 2>/dev/null || true
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
zip -q -r -9 "$OUT" .
unzip -t "$OUT" >/dev/null

printf '%s\n' \
  "Integrated Recovery Console permanently into Channel TWRP installer" \
  "  base zip       : $BASE_ZIP" \
  "  output zip     : $OUT" \
  "  ramdisk        : $RAMDISK" \
  "  compression    : $COMPRESSION" \
  "  console path   : $CONSOLE_EXEC" \
  "  stock recovery : disabled" \
  "  console boot   : automatic (on boot)" \
  "  service block  : /init.rc" \
  "  integration    : upstream README permanent init.rc method" \
  "  fallback       : upstream cleanup may explicitly 'start recovery' on exit" \
  "  installer      : native Channel TWRP update-binary preserved"

sha256sum "$OUT"
, init_text):
    raise SystemExit("recovery-console boot trigger must be defined in /init.rc per upstream README")
PY

if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAW" "$RAMDISK"
else
  rm -f "$RAMDISK"
  "$MAGISKBOOT" "compress=$COMPRESSION" "$RAW" "$RAMDISK"
fi
[ -s "$RAMDISK" ] || { echo "ERROR: final ramdisk missing" >&2; exit 1; }

ROUNDTRIP="$WORK/roundtrip.cpio"
if [ "$COMPRESSION" = raw ]; then
  cp -f "$RAMDISK" "$ROUNDTRIP"
else
  "$MAGISKBOOT" decompress "$RAMDISK" "$ROUNDTRIP"
fi
cmp -s "$RAW" "$ROUNDTRIP" || { echo "ERROR: ramdisk compression round-trip changed payload" >&2; exit 1; }

chmod 0755 META-INF/com/google/android/update-binary magiskboot 2>/dev/null || true
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
zip -q -r -9 "$OUT" .
unzip -t "$OUT" >/dev/null

printf '%s\n' \
  "Integrated Recovery Console permanently into Channel TWRP installer" \
  "  base zip       : $BASE_ZIP" \
  "  output zip     : $OUT" \
  "  ramdisk        : $RAMDISK" \
  "  compression    : $COMPRESSION" \
  "  console path   : $CONSOLE_EXEC" \
  "  stock recovery : disabled" \
  "  console boot   : automatic (on boot)" \
  "  integration    : upstream README permanent init.rc method" \
  "  fallback       : upstream cleanup may explicitly 'start recovery' on exit" \
  "  installer      : native Channel TWRP update-binary preserved"

sha256sum "$OUT"
