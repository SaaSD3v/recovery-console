#!/bin/sh
# Cross-compile a minimal FreeType 2 static lib for a musl target.
# Usage:
#   ./scripts/build-freetype.sh aarch64-linux-musl
#   ./scripts/build-freetype.sh arm-linux-musleabihf
#   ./scripts/build-freetype.sh x86_64-linux-musl
#   ./scripts/build-freetype.sh i686-linux-musl
#
# Output: deps/<arch>/include/  deps/<arch>/lib/libfreetype.a

set -eu

TRIPLE="${1:-aarch64-linux-musl}"
ARCH=$(echo "$TRIPLE" | cut -d- -f1 | sed 's/arm.*/armhf/;s/i686/x86/')
FT_VER="2.13.3"
FT_ARCHIVE="freetype-${FT_VER}.tar.gz"
FT_SHA256="5c3a8e78f7b24c20b25b54ee575d6daa40007a5f4eea2845861c3409b3021747"
DESTDIR="$(cd "$(dirname "$0")/.." && pwd)/deps/${ARCH}"
BUILD="/tmp/ft-build-${ARCH}"
ARCHIVE_PATH="$BUILD/$FT_ARCHIVE"

# Locate the complete cross-toolchain.  Do not mix host ar/ranlib with target gcc.
CC_BIN=""
for d in "$HOME/toolchains/${TRIPLE}-cross/bin" "/usr/bin"; do
  if [ -x "$d/${TRIPLE}-gcc" ]; then
    CC_BIN="$d"
    break
  fi
done
if [ -z "$CC_BIN" ]; then
  echo "ERROR: compiler ${TRIPLE}-gcc not found." >&2
  exit 1
fi

CROSS_CC="$CC_BIN/${TRIPLE}-gcc"
CROSS_AR="$CC_BIN/${TRIPLE}-ar"
CROSS_RANLIB="$CC_BIN/${TRIPLE}-ranlib"

for tool in "$CROSS_CC" "$CROSS_AR" "$CROSS_RANLIB"; do
  if [ ! -x "$tool" ]; then
    echo "ERROR: required cross-tool not found: $tool" >&2
    exit 1
  fi
done

echo "==> Building FreeType ${FT_VER} for ${TRIPLE}"
echo "    Compiler : ${CROSS_CC}"
echo "    Archiver : ${CROSS_AR}"
echo "    Ranlib   : ${CROSS_RANLIB}"
echo "    Output   : ${DESTDIR}"

mkdir -p "$BUILD" "$DESTDIR"

verify_archive() {
  [ -f "$ARCHIVE_PATH" ] || return 1
  actual=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
  [ "$actual" = "$FT_SHA256" ]
}

download_url() {
  url="$1"
  tmp="$ARCHIVE_PATH.part"
  rm -f "$tmp"
  echo "    Download: $url"

  if command -v curl >/dev/null 2>&1; then
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 \
        -o "$tmp" "$url"; then
      mv -f "$tmp" "$ARCHIVE_PATH"
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget --tries=3 --timeout=30 -O "$tmp" "$url"; then
      mv -f "$tmp" "$ARCHIVE_PATH"
      return 0
    fi
  else
    echo "ERROR: neither curl nor wget is available." >&2
    exit 1
  fi

  rm -f "$tmp"
  return 1
}

# A previous failed wget can leave a zero/HTML file behind.  Never reuse it.
if ! verify_archive; then
  rm -f "$ARCHIVE_PATH"

  downloaded=0
  for url in \
    "https://download-mirror.savannah.gnu.org/releases/freetype/$FT_ARCHIVE" \
    "https://downloads.sourceforge.net/project/freetype/freetype2/${FT_VER}/$FT_ARCHIVE" \
    "https://download.savannah.gnu.org/releases/freetype/$FT_ARCHIVE"; do
    if download_url "$url" && verify_archive; then
      downloaded=1
      break
    fi
    echo "    Mirror failed or checksum mismatch; trying next mirror..." >&2
    rm -f "$ARCHIVE_PATH"
  done

  if [ "$downloaded" -ne 1 ]; then
    echo "ERROR: failed to download a verified FreeType ${FT_VER} archive." >&2
    exit 1
  fi
fi

echo "    SHA-256 : verified"

# Always recreate the source/build trees so reruns cannot inherit partial state.
rm -rf "$BUILD/freetype-${FT_VER}" "$BUILD/build"
cd "$BUILD"
tar xzf "$FT_ARCHIVE"
SRCDIR="$BUILD/freetype-${FT_VER}"

mkdir -p "$BUILD/build"
cd "$BUILD/build"

"$SRCDIR/configure" \
  --host="$TRIPLE" \
  --prefix="$DESTDIR" \
  --enable-static \
  --disable-shared \
  --without-harfbuzz \
  --without-png \
  --without-bzip2 \
  --without-brotli \
  --without-zlib \
  CC="$CROSS_CC" \
  AR="$CROSS_AR" \
  RANLIB="$CROSS_RANLIB" \
  CFLAGS="-O2 -fPIC"

make -j"$(nproc 2>/dev/null || echo 4)"
make install

echo ""
echo "==> Done! Headers and library installed under:"
echo "    ${DESTDIR}/include/"
echo "    ${DESTDIR}/lib/libfreetype.a"
echo ""