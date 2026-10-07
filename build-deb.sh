#!/bin/bash
# Extract the VMX-pi HAL from the disk image (/usr/local) and package it as arm64 .debs:
#   vmxpi-hal           runtime libs (C++/Python/Java/C#), ld.so + python .pth config
#   vmxpi-hal-dev       headers + static lib
#   vmxpi-hal-examples  example sources
# Run inside WSL as root:  bash build-deb.sh   (env: IMG=..., VERSION=...)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMG="${IMG:-$HERE/Ubuntu_22_04_Ros2_Humble_Full_HAL.iso}"
VERSION="${VERSION:-1.0~20240704}"
ARCH=arm64
MNT=/mnt/img
WORK="$HOME/deb-build"
OUTDIR="${OUTDIR:-$HERE/dist}"
MAINT="VMX-pi HAL packager <donotusecheat915@naver.com>"

[ -f "$IMG" ] || { echo "Image not found: $IMG (set IMG=...)"; exit 1; }
# Start sector of the last Linux (type 83) partition, instead of hardcoding it
PART_START_SECTOR=$(sfdisk -d "$IMG" | awk -F'[=, ]+' '/type=83/ {for(i=1;i<=NF;i++) if($i=="start") s=$(i+1)} END{print s}')
[ -n "$PART_START_SECTOR" ] || { echo "No Linux partition found in image"; exit 1; }

mkdir -p "$MNT" "$OUTDIR"
mountpoint -q "$MNT" || mount -o ro,loop,offset=$((PART_START_SECTOR*512)),noload "$IMG" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT
SRC="$MNT/usr/local"
[ -d "$SRC/lib/vmxpi" ] || { echo "HAL not found at $SRC/lib/vmxpi"; exit 1; }

# newpkg <name> -> creates stage dir, echoes path
newpkg() { local d="$WORK/$1_${VERSION}_${ARCH}"; rm -rf "$d"; mkdir -p "$d/DEBIAN"; echo "$d"; }

# write_copyright <stage> <name> -> /usr/share/doc/<name>/copyright (MIT notice must travel with redistributions)
write_copyright() {
  local d="$1/usr/share/doc/$2"; mkdir -p "$d"
  {
    cat <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Comment: Unofficial repackaging of binaries/headers taken from a Studica VMX-pi
 image. The packager claims no copyright over the HAL itself.
 Files without an explicit notice upstream (the example sources, and the
 headers TeddyRegisters.h / TeddyPIDRegisters.h) carry no license text of
 their own; they are believed to be covered by the same MIT terms as the rest
 of the HAL, but this is not stated upstream.

Files: *
Copyright: 2013-2022 Kauai Labs
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
EOF
    case "$2" in vmxpi-hal|vmxpi-hal-dev) cat <<'EOF'

Comment: Third-party code statically linked into the HAL libraries
 (found as the pigpio, command and ws2811 objects in libvmxpi_hal_cpp.a):
 pigpio (public domain / Unlicense) and rpi_ws281x "ws2811" (BSD 2-Clause).
 The exact upstream notices for the bundled versions were not present in the
 source image and still need to be added here before public redistribution.
EOF
    ;; esac
  } > "$d/copyright"
  chmod 644 "$d/copyright"
}

# finish <stage> <name> <depends> <recommends> <description...>
finish() {
  local stage="$1" name="$2" deps="$3" recs="$4" desc="$5"
  local size; size=$(du -sk --exclude=DEBIAN "$stage" | cut -f1)
  {
    echo "Package: $name"
    echo "Version: $VERSION"
    echo "Section: libs"
    echo "Priority: optional"
    echo "Architecture: $ARCH"
    echo "Installed-Size: $size"
    [ -n "$deps" ] && echo "Depends: $deps"
    [ -n "$recs" ] && echo "Recommends: $recs"
    echo "Maintainer: $MAINT"
    echo "Description: $desc"
    echo " Prebuilt aarch64 VMX-pi HAL extracted from the Ubuntu 22.04 ROS2 Humble"
    echo " image. Installs under /usr/local (paths are hardcoded by the HAL examples)."
    echo " Unofficial repackaging; not affiliated with or endorsed by Kauai Labs or Studica."
  } > "$stage/DEBIAN/control"
  write_copyright "$stage" "$name"
  find "$stage" -type d -exec chmod 755 {} +
  fakeroot dpkg-deb --build --root-owner-group "$stage" "$OUTDIR/${name}_${VERSION}_${ARCH}.deb" >/dev/null
  echo "Built: $OUTDIR/${name}_${VERSION}_${ARCH}.deb"
}

# ---- vmxpi-hal (runtime) ----
S=$(newpkg vmxpi-hal)
mkdir -p "$S/usr/local/lib/vmxpi" "$S/etc/ld.so.conf.d" "$S/usr/lib/python3/dist-packages"
for f in "$SRC"/lib/vmxpi/*; do
  case "$f" in *__pycache__|*.a) continue ;; esac
  cp -a "$f" "$S/usr/local/lib/vmxpi/"
done
echo /usr/local/lib/vmxpi > "$S/etc/ld.so.conf.d/vmxpi-hal.conf"
echo /usr/local/lib/vmxpi > "$S/usr/lib/python3/dist-packages/vmxpi-hal.pth"   # `import vmxpi_hal_python` works
printf '#!/bin/sh\nset -e\n[ "$1" = configure ] && ldconfig\nexit 0\n' > "$S/DEBIAN/postinst"
printf '#!/bin/sh\nset -e\ncase "$1" in remove|purge) ldconfig ;; esac\nexit 0\n' > "$S/DEBIAN/postrm"
chmod 755 "$S/DEBIAN/postinst" "$S/DEBIAN/postrm"
finish "$S" vmxpi-hal "libc6 (>= 2.17), libstdc++6, libgcc-s1 | libgcc1" "python3, default-jre-headless" \
  "VMX-pi HAL runtime libraries (C++, Python, Java, C#)"

# ---- vmxpi-hal-dev ----
S=$(newpkg vmxpi-hal-dev)
mkdir -p "$S/usr/local/include" "$S/usr/local/lib/vmxpi"
cp -a "$SRC/include/vmxpi" "$S/usr/local/include/"
cp -a "$SRC/lib/vmxpi/libvmxpi_hal_cpp.a" "$S/usr/local/lib/vmxpi/"
finish "$S" vmxpi-hal-dev "vmxpi-hal (= $VERSION)" "g++" \
  "VMX-pi HAL C++ headers and static library"

# ---- vmxpi-hal-examples ----
S=$(newpkg vmxpi-hal-examples)
mkdir -p "$S/usr/local"
cp -a "$SRC/src" "$S/usr/local/"
finish "$S" vmxpi-hal-examples "vmxpi-hal-dev (= $VERSION)" "make, g++, python3" \
  "VMX-pi HAL example programs (C++, Python, Java, C#)"

ls -la "$OUTDIR"
