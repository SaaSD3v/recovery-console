#!/bin/sh
set -eu

TRIPLE="${1:?target triple required}"
ROOT="${2:?source root required}"
ARCH=$(echo "$TRIPLE" | cut -d- -f1 | sed 's/arm.*/armhf/;s/i686/x86/')
FT_VER="2.13.3"
FT_ARCHIVE="freetype-${FT_VER}.tar.gz"
FT_SHA256="5c3a8e78f7b24c20b25b54ee575d6daa40007a5f4eea2845861c3409b3021747"
DESTDIR="$ROOT/deps/${ARCH}"
BUILD="/tmp/ft-build-${ARCH}"
ARCHIVE_PATH="$BUILD/$FT_ARCHIVE"
CC_BIN="$HOME/toolchains/${TRIPLE}-cross/bin"

for tool in gcc ar ranlib; do
  [ -x "$CC_BIN/${TRIPLE}-$tool" ] || {
    echo "ERROR: missing $CC_BIN/${TRIPLE}-$tool" >&2
    exit 1
  }
done

mkdir -p "$BUILD" "$DESTDIR"

verify_archive() {
  [ -f "$ARCHIVE_PATH" ] || return 1
  [ "$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')" = "$FT_SHA256" ]
}

download_url() {
  url="$1"
  tmp="$ARCHIVE_PATH.part"
  rm -f "$tmp"
  echo "Downloading $url"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$tmp" "$url" || return 1
  mv -f "$tmp" "$ARCHIVE_PATH"
}

if ! verify_archive; then
  rm -f "$ARCHIVE_PATH"
  ok=0
  for url in \
    "https://download-mirror.savannah.gnu.org/releases/freetype/$FT_ARCHIVE" \
    "https://downloads.sourceforge.net/project/freetype/freetype2/${FT_VER}/$FT_ARCHIVE" \
    "https://download.savannah.gnu.org/releases/freetype/$FT_ARCHIVE"; do
    if download_url "$url" && verify_archive; then
      ok=1
      break
    fi
    rm -f "$ARCHIVE_PATH"
  done
  [ "$ok" -eq 1 ] || { echo "ERROR: failed to download verified FreeType" >&2; exit 1; }
fi

rm -rf "$BUILD/freetype-${FT_VER}" "$BUILD/build"
cd "$BUILD"
tar xzf "$FT_ARCHIVE"
mkdir -p "$BUILD/build"
cd "$BUILD/build"

"$BUILD/freetype-${FT_VER}/configure" \
  --host="$TRIPLE" \
  --prefix="$DESTDIR" \
  --enable-static \
  --disable-shared \
  --without-harfbuzz \
  --without-png \
  --without-bzip2 \
  --without-brotli \
  --without-zlib \
  CC="$CC_BIN/${TRIPLE}-gcc" \
  AR="$CC_BIN/${TRIPLE}-ar" \
  RANLIB="$CC_BIN/${TRIPLE}-ranlib" \
  CFLAGS="-O2 -fPIC"

make -j"$(nproc 2>/dev/null || echo 4)"
make install
