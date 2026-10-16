#!/bin/bash
# Extract the VMX-pi HAL from a partitioned .iso/.img or a filesystem image and
# package the complete /usr/local payload as one arm64 .deb.
# Run inside WSL or Linux: bash build-deb.sh (env: IMG=..., SRC_DIR=..., VERSION=...)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMG="${IMG:-$HERE/Ubuntu_22_04_Ros2_Humble_Full_HAL.iso}"
SRC_DIR="${SRC_DIR:-}"
VERSION="${VERSION:-1.0~20240704}"
ARCH=arm64
OUTDIR="${OUTDIR:-$HERE/dist}"
MAINT="VMX-pi HAL packager"

if [ -n "$SRC_DIR" ]; then
  [ -d "$SRC_DIR" ] || { echo "Source directory not found: $SRC_DIR" >&2; exit 1; }
  SRC_DIR="$(cd "$SRC_DIR" && pwd)"
else
  [ "$(id -u)" -eq 0 ] || { echo "Run as root to mount the image, or set SRC_DIR to a mounted /usr/local directory." >&2; exit 1; }
  [ -f "$IMG" ] || { echo "Image not found: $IMG (set IMG=...)" >&2; exit 1; }
  for cmd in mount umount sfdisk file; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Required command not found: $cmd" >&2; exit 1; }
  done
fi
for cmd in dpkg-deb fakeroot awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command not found: $cmd" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vmxpi-hal-build.XXXXXX")"
MNT="$WORK/mnt"
mkdir -p "$MNT" "$OUTDIR"
MOUNTED=0
cleanup() {
  if [ "$MOUNTED" = 1 ]; then umount "$MNT" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Try a whole-filesystem image first (also handles an ISO filesystem). A hybrid
# ISO or disk .img normally needs one of its Linux partitions mounted by offset.
try_mount_whole_image() {
  local opts=ro,loop
  case "$(file -b "$IMG" 2>/dev/null || true)" in *ext[234]*) opts=ro,loop,noload ;; esac
  if mount -o "$opts" "$IMG" "$MNT" 2>/dev/null; then
    MOUNTED=1
    if [ -d "$MNT/usr/local/lib/vmxpi" ]; then return 0; fi
    umount "$MNT"; MOUNTED=0
  fi
  return 1
}

try_mount_linux_partition() {
  local start="$1" size="$2" sector_size="$3" offset limit
  offset=$((start * sector_size))
  limit=$((size * sector_size))
  local opts
  for opts in "ro,loop,offset=$offset,sizelimit=$limit,noload" "ro,loop,offset=$offset,sizelimit=$limit"; do
    if mount -o "$opts" "$IMG" "$MNT" 2>/dev/null; then
      MOUNTED=1
      if [ -d "$MNT/usr/local/lib/vmxpi" ]; then return 0; fi
      umount "$MNT"; MOUNTED=0
    fi
  done
  return 1
}

SRC="$SRC_DIR"
if [ -z "$SRC" ]; then
  if try_mount_whole_image; then
    SRC="$MNT/usr/local"
  else
    TABLE="$(sfdisk -d "$IMG" 2>/dev/null || true)"
    SECTOR_SIZE="$(awk -F'[: ]+' '/^sector-size:/ {print $2; exit}' <<<"$TABLE")"
    SECTOR_SIZE="${SECTOR_SIZE:-512}"
    while read -r start size; do
      [ -n "$start" ] || continue
      if try_mount_linux_partition "$start" "$size" "$SECTOR_SIZE"; then
        SRC="$MNT/usr/local"
        break
      fi
    done < <(awk -F'[=, ]+' '{u=toupper($0); if(u ~ /TYPE=(83|0FC63DAF-8483-4772-8E79-3D69D8477DE4|4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709|B921B045-1DF0-41C3-AF44-4C6F280D3FAE|69DAD710-2CE4-4E3C-B16C-21A1D49ABED3)/) {s=""; z=""; for(i=1;i<=NF;i++){if($i=="start")s=$(i+1); if($i=="size")z=$(i+1)} if(s!="" && z!="") print s, z}}' <<<"$TABLE")
  fi
fi
[ -n "$SRC" ] || { echo "Could not find /usr/local/lib/vmxpi in $IMG (tried whole image and Linux partitions)." >&2; exit 1; }
[ -d "$SRC/include/vmxpi" ] || { echo "HAL headers not found at $SRC/include/vmxpi" >&2; exit 1; }
[ -f "$SRC/lib/vmxpi/libvmxpi_hal_cpp.so" ] || { echo "C++ HAL library not found under $SRC/lib/vmxpi" >&2; exit 1; }

PKG="$WORK/vmxpi-hal_${VERSION}_${ARCH}"
mkdir -p "$PKG/DEBIAN" "$PKG/usr/local" "$PKG/etc/ld.so.conf.d" "$PKG/usr/lib/python3/dist-packages"

# The one package contains the complete upstream /usr/local payload needed by
# existing C++, Python, Java, and C# consumers: runtime files, headers, archives,
# and examples. Keep original directory layout because examples use absolute paths.
cp -a "$SRC/lib" "$PKG/usr/local/"
cp -a "$SRC/include" "$PKG/usr/local/"
if [ -d "$SRC/src" ]; then cp -a "$SRC/src" "$PKG/usr/local/"; fi
echo /usr/local/lib/vmxpi > "$PKG/etc/ld.so.conf.d/vmxpi-hal.conf"
echo /usr/local/lib/vmxpi > "$PKG/usr/lib/python3/dist-packages/vmxpi-hal.pth"

printf '#!/bin/sh\nset -e\n[ "$1" = configure ] && ldconfig\nexit 0\n' > "$PKG/DEBIAN/postinst"
printf '#!/bin/sh\nset -e\ncase "$1" in remove|purge) ldconfig ;; esac\nexit 0\n' > "$PKG/DEBIAN/postrm"
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

DOC="$PKG/usr/share/doc/vmxpi-hal"
mkdir -p "$DOC"
cat > "$DOC/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Comment: Unofficial repackaging of binaries, headers, and examples taken from a
 Studica VMX-pi image. The packager claims no copyright over the HAL itself.
 Files without an explicit notice upstream (some example sources and the
 headers TeddyRegisters.h / TeddyPIDRegisters.h) are believed to be covered by
 the same MIT terms as the rest of the HAL, but this is not stated upstream.

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

Comment: Third-party code statically linked into HAL libraries includes pigpio
 (public domain / Unlicense) and rpi_ws281x (BSD 2-Clause), based on object
 names found in libvmxpi_hal_cpp.a. Exact upstream notices for bundled versions
 were not present in the source image and must be resolved before redistribution.
EOF

SIZE="$(du -sk --exclude=DEBIAN "$PKG" | cut -f1)"
{
  echo "Package: vmxpi-hal"
  echo "Version: $VERSION"
  echo "Section: libs"
  echo "Priority: optional"
  echo "Architecture: $ARCH"
  echo "Installed-Size: $SIZE"
  echo "Depends: libc6 (>= 2.17), libstdc++6, libgcc-s1 | libgcc1"
  echo "Conflicts: vmxpi-hal-dev, vmxpi-hal-examples"
  echo "Replaces: vmxpi-hal-dev, vmxpi-hal-examples"
  echo "Recommends: python3, default-jre-headless"
  echo "Maintainer: $MAINT"
  echo "Description: VMX-pi HAL files for C++, Python, Java, and C#"
  echo " Complete /usr/local payload extracted from the VMX-pi Ubuntu 22.04 ROS2 Humble image."
  echo " Includes runtime libraries, headers, static libraries, and example sources."
  echo " Unofficial repackaging; not affiliated with or endorsed by Kauai Labs or Studica."
} > "$PKG/DEBIAN/control"
find "$PKG" -type d -exec chmod 755 {} +

OUTPUT="$OUTDIR/vmxpi-hal_${VERSION}_${ARCH}.deb"
BUILT="$WORK/vmxpi-hal_${VERSION}_${ARCH}.deb"
fakeroot dpkg-deb --build --root-owner-group "$PKG" "$BUILT" >/dev/null
# Treat dist/ as this builder's output directory: remove stale split packages
# and old versions only after the replacement package has been built cleanly.
rm -f "$OUTDIR"/vmxpi-hal_*.deb "$OUTDIR"/vmxpi-hal-dev_*.deb "$OUTDIR"/vmxpi-hal-examples_*.deb
mv "$BUILT" "$OUTPUT"
echo "Built: $OUTPUT"
echo "Source image: $IMG"
echo "Contents: runtime, development files, and examples (single package)"
