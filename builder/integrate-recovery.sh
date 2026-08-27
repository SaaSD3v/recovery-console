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

"$MAGISKBOOT" unpack base.img
[ -s ramdisk.cpio ] || {
  echo "ERROR: no ramdisk.cpio produced. Unsupported or ramdisk-less image." >&2
  exit 1
}

cpio -it < ramdisk.cpio > ramdisk.list 2>/dev/null || {
  echo "ERROR: cannot list ramdisk.cpio" >&2
  exit 1
}

find_entry() {
  local needle="$1"
  grep -E "^(\./)?${needle}$" ramdisk.list | head -n1 || true
}

# Prefer /sbin only when this recovery actually uses /sbin/recovery.
# Otherwise install at root instead of inventing a directory/symlink layout.
if [ -n "$(find_entry 'sbin/recovery')" ]; then
  CONSOLE_ENTRY='sbin/recovery-console'
  CONSOLE_EXEC='/sbin/recovery-console'
else
  CONSOLE_ENTRY='recovery-console'
  CONSOLE_EXEC='/recovery-console'
fi

RC_ENTRY=''
RC_ARCHIVE_ENTRY=''
for candidate in init.recovery.service.rc init.recovery.rc init.rc; do
  found=$(find_entry "$candidate")
  if [ -n "$found" ]; then
    RC_ENTRY="$candidate"
    RC_ARCHIVE_ENTRY="$found"
    break
  fi
done
[ -n "$RC_ENTRY" ] || {
  echo "ERROR: no supported init rc file found in ramdisk" >&2
  exit 1
}

mkdir extract
(
  cd extract
  cpio -idmu --quiet "$RC_ARCHIVE_ENTRY" < ../ramdisk.cpio
)
RC_FILE="$WORK/extract/${RC_ARCHIVE_ENTRY#./}"
[ -f "$RC_FILE" ] || { echo "ERROR: failed to extract $RC_ARCHIVE_ENTRY" >&2; exit 1; }
RC_MODE="0$(stat -c '%a' "$RC_FILE")"

# Idempotent: remove an earlier builder block before appending a fresh one.
python3 - "$RC_FILE" "$CONSOLE_EXEC" "$SECLABEL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
exe = sys.argv[2]
seclabel = sys.argv[3]
text = path.read_text(errors='surrogateescape')
start = '# BEGIN RECOVERY-CONSOLE-BUILDER'
end = '# END RECOVERY-CONSOLE-BUILDER'
while start in text and end in text:
    a = text.index(start)
    b = text.index(end, a) + len(end)
    text = text[:a].rstrip() + '\n' + text[b:].lstrip('\n')

block = [
    start,
    f'service recovery-console {exe}',
    '    user root',
    '    group root',
    '    oneshot',
    '    disabled',
]
if seclabel and seclabel.lower() != 'none':
    block.append(f'    seclabel {seclabel}')
block.append(end)
path.write_text(text.rstrip() + '\n\n' + '\n'.join(block) + '\n', errors='surrogateescape')
PY

# Replace only the selected rc entry and add the console binary; leave the rest
# of the original ramdisk untouched.
"$MAGISKBOOT" cpio ramdisk.cpio "rm $RC_ARCHIVE_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio ramdisk.cpio "rm $RC_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio ramdisk.cpio "add $RC_MODE $RC_ENTRY $RC_FILE"
"$MAGISKBOOT" cpio ramdisk.cpio "rm $CONSOLE_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio ramdisk.cpio "add 0755 $CONSOLE_ENTRY $BIN"

mkdir -p "$(dirname "$OUT")"
"$MAGISKBOOT" repack base.img "$OUT"
[ -s "$OUT" ] || { echo "ERROR: repack did not create output image" >&2; exit 1; }

# Re-open the generated image to prove both payloads exist after repack.
VERIFY=$(mktemp -d)
(
  cd "$VERIFY"
  "$MAGISKBOOT" unpack "$OUT" >/dev/null
  [ -s ramdisk.cpio ]
  cpio -it < ramdisk.cpio > list 2>/dev/null
  grep -Eq "^(\./)?${CONSOLE_ENTRY}$" list
  verify_rc=$(grep -E "^(\./)?${RC_ENTRY}$" list | head -n1)
  [ -n "$verify_rc" ]
  mkdir x
  cd x
  cpio -idmu --quiet "$verify_rc" < ../ramdisk.cpio
  verify_file="${verify_rc#./}"
  grep -q '^service recovery-console ' "$verify_file"
  grep -q '^[[:space:]]*disabled[[:space:]]*$' "$verify_file"
)
rm -rf "$VERIFY"

printf '%s\n' \
  "Integrated recovery-console successfully" \
  "  base        : $BASE" \
  "  output      : $OUT" \
  "  binary path : $CONSOLE_EXEC" \
  "  init rc     : /$RC_ENTRY" \
  "  init mode   : $RC_MODE" \
  "  autostart   : NO (service is disabled)" \
  "  seclabel    : $SECLABEL"
sha256sum "$OUT"
