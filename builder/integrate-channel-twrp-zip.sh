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
[ -n "$RAMDISK" ] || {
  echo "ERROR: TWRP installer contains neither ramdisk-twrp.cpio nor ramdisk-recovery.cpio" >&2
  exit 1
}

[ -f META-INF/com/google/android/update-binary ] || {
  echo "ERROR: installer update-binary missing" >&2
  exit 1
}
[ -f magiskboot ] || {
  echo "ERROR: installer magiskboot missing" >&2
  exit 1
}

# The official Channel installer stores its recovery ramdisk compressed.
# Work on an uncompressed CPIO, then restore the original compression format.
RAW_RAMDISK="$WORK/ramdisk.raw.cpio"
COMPRESSION="raw"

if cpio -it < "$RAMDISK" > "$WORK/ramdisk.list" 2>/dev/null; then
  cp -f "$RAMDISK" "$RAW_RAMDISK"
else
  DESC=$(file -b "$RAMDISK" || true)
  MAGIC=$(xxd -p -l 8 "$RAMDISK" 2>/dev/null | tr -d '\n')

  case "$MAGIC" in
    1f8b*)         COMPRESSION="gzip" ;;
    04224d18*)     COMPRESSION="lz4" ;;
    02214c18*)     COMPRESSION="lz4_legacy" ;;
    fd377a585a00*) COMPRESSION="xz" ;;
    425a68*)       COMPRESSION="bzip2" ;;
    *)
      case "$DESC" in
        *gzip*)  COMPRESSION="gzip" ;;
        *XZ*)    COMPRESSION="xz" ;;
        *LZMA*)  COMPRESSION="lzma" ;;
        *bzip2*) COMPRESSION="bzip2" ;;
        *LZ4*)   COMPRESSION="lz4" ;;
        *)
          echo "ERROR: unsupported ramdisk compression: $DESC (magic=$MAGIC)" >&2
          exit 1
          ;;
      esac
      ;;
  esac

  echo "Ramdisk compression: $COMPRESSION ($DESC)"
  "$MAGISKBOOT" decompress "$RAMDISK" "$RAW_RAMDISK"
  [ -s "$RAW_RAMDISK" ] || {
    echo "ERROR: magiskboot did not produce a decompressed ramdisk" >&2
    exit 1
  }

  cpio -it < "$RAW_RAMDISK" > "$WORK/ramdisk.list" 2>/dev/null || {
    echo "ERROR: decompressed $RAMDISK is not a valid CPIO archive" >&2
    exit 1
  }
fi

find_entry() {
  local needle="$1"
  grep -E "^(\./)?${needle}$" "$WORK/ramdisk.list" | head -n1 || true
}

# Channel TWRP normally contains /sbin/recovery. Keep the same placement
# strategy as the generic builder, but fail cleanly if the layout differs.
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
  echo "ERROR: no supported init rc file found in TWRP ramdisk" >&2
  exit 1
}

mkdir -p "$WORK/extract"
(
  cd "$WORK/extract"
  cpio -idmu --quiet "$RC_ARCHIVE_ENTRY" < "$RAW_RAMDISK"
)
RC_FILE="$WORK/extract/${RC_ARCHIVE_ENTRY#./}"
[ -f "$RC_FILE" ] || { echo "ERROR: failed to extract $RC_ARCHIVE_ENTRY" >&2; exit 1; }
RC_MODE="0$(stat -c '%a' "$RC_FILE")"

python3 - "$RC_FILE" "$CONSOLE_EXEC" "$SECLABEL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
exe = sys.argv[2]
seclabel = sys.argv[3]
text = path.read_text(errors="surrogateescape")
start = "# BEGIN RECOVERY-CONSOLE-CHANNEL"
end = "# END RECOVERY-CONSOLE-CHANNEL"

while start in text and end in text:
    a = text.index(start)
    b = text.index(end, a) + len(end)
    text = text[:a].rstrip() + "\n" + text[b:].lstrip("\n")

block = [
    start,
    f"service recovery-console {exe}",
    "    user root",
    "    group root",
    "    oneshot",
    "    disabled",
]
if seclabel and seclabel.lower() != "none":
    block.append(f"    seclabel {seclabel}")
block.append(end)

path.write_text(text.rstrip() + "\n\n" + "\n".join(block) + "\n",
                errors="surrogateescape")
PY

"$MAGISKBOOT" cpio "$RAW_RAMDISK" "rm $RC_ARCHIVE_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio "$RAW_RAMDISK" "rm $RC_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio "$RAW_RAMDISK" "add $RC_MODE $RC_ENTRY $RC_FILE"
"$MAGISKBOOT" cpio "$RAW_RAMDISK" "rm $CONSOLE_ENTRY" >/dev/null 2>&1 || true
"$MAGISKBOOT" cpio "$RAW_RAMDISK" "add 0755 $CONSOLE_ENTRY $BIN"

# Verify the modified raw CPIO before recompressing it.
cpio -it < "$RAW_RAMDISK" > "$WORK/verify.list" 2>/dev/null
grep -Eq "^(\./)?${CONSOLE_ENTRY}$" "$WORK/verify.list"
VERIFY_RC=$(grep -E "^(\./)?${RC_ENTRY}$" "$WORK/verify.list" | head -n1)
[ -n "$VERIFY_RC" ]

mkdir -p "$WORK/verify"
(
  cd "$WORK/verify"
  cpio -idmu --quiet "$VERIFY_RC" < "$RAW_RAMDISK"
)
VERIFY_FILE="$WORK/verify/${VERIFY_RC#./}"
grep -q '^service recovery-console ' "$VERIFY_FILE"
grep -q '^[[:space:]]*disabled[[:space:]]*$' "$VERIFY_FILE"

# Restore the exact compression family expected by the native TWRP installer.
if [ "$COMPRESSION" = "raw" ]; then
  cp -f "$RAW_RAMDISK" "$RAMDISK"
else
  rm -f "$RAMDISK"
  "$MAGISKBOOT" "compress=$COMPRESSION" "$RAW_RAMDISK" "$RAMDISK"
  [ -s "$RAMDISK" ] || {
    echo "ERROR: failed to recompress ramdisk as $COMPRESSION" >&2
    exit 1
  }
fi

# Re-open the final ramdisk after compression and prove our changes survived.
FINAL_RAW="$WORK/final-verify.cpio"
if [ "$COMPRESSION" = "raw" ]; then
  cp -f "$RAMDISK" "$FINAL_RAW"
else
  "$MAGISKBOOT" decompress "$RAMDISK" "$FINAL_RAW"
fi
cpio -it < "$FINAL_RAW" > "$WORK/final.list" 2>/dev/null
grep -Eq "^(\./)?${CONSOLE_ENTRY}$" "$WORK/final.list"
grep -Eq "^(\./)?${RC_ENTRY}$" "$WORK/final.list"

# Preserve executable installer helpers before rebuilding the ZIP.
chmod 0755 META-INF/com/google/android/update-binary magiskboot 2>/dev/null || true

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
zip -q -r -9 "$OUT" .
[ -s "$OUT" ] || { echo "ERROR: output zip was not created" >&2; exit 1; }

# Re-open output and verify installer + modified ramdisk are present.
unzip -t "$OUT" >/dev/null
unzip -Z1 "$OUT" | grep -q '^META-INF/com/google/android/update-binary$'
unzip -Z1 "$OUT" | grep -q "^${RAMDISK}$"

printf '%s\n' \
  "Integrated Recovery Console into Channel TWRP installer" \
  "  base zip     : $BASE_ZIP" \
  "  output zip   : $OUT" \
  "  ramdisk      : $RAMDISK" \
  "  compression  : $COMPRESSION" \
  "  binary path  : $CONSOLE_EXEC" \
  "  init rc      : /$RC_ENTRY" \
  "  autostart    : NO (service is disabled)" \
  "  install mode : recovery-as-boot (official Channel update-binary patches boot_a + boot_b)" \
  "  seclabel     : $SECLABEL"

sha256sum "$OUT"
