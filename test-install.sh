#!/bin/bash
# Install the built .debs in arm64 containers (qemu) and smoke-test them.
# Run inside WSL:  bash test-install.sh [image ...]   default: ubuntu:22.04 debian:12
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGES=("$@"); [ ${#IMAGES[@]} -eq 0 ] && IMAGES=(ubuntu:22.04 debian:12)
rc=0
for img in "${IMAGES[@]}"; do
  echo "=== $img (linux/arm64) ==="
  docker run --rm --platform linux/arm64 -v "$HERE/dist:/dist:ro" "$img" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq /dist/vmxpi-hal_*.deb /dist/vmxpi-hal-dev_*.deb /dist/vmxpi-hal-examples_*.deb python3 g++ >/dev/null
    echo "[ldconfig]"; ldconfig -p | grep vmxpi
    echo "[ldd]";      ldd /usr/local/lib/vmxpi/libvmxpi_hal_cpp.so | grep -c "not found" || true
    echo "[python]";   python3 -c "import vmxpi_hal_python; print(\"import OK\")" 2>&1 | tail -1
    echo "[c++ link]"; printf "#include <vmxpi/VMXPi.h>\nint main(){return 0;}\n" > /tmp/t.cpp
                       g++ -std=c++14 /tmp/t.cpp -I/usr/local/include/vmxpi -L/usr/local/lib/vmxpi -lvmxpi_hal_cpp -o /tmp/t 2>&1 | tail -3 && echo "compile+link done"
    echo "[remove]";   apt-get purge -y -qq vmxpi-hal-examples vmxpi-hal-dev vmxpi-hal >/dev/null && echo "purge OK"
  ' || rc=1
done
exit $rc
