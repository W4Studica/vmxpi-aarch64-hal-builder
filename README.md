# vmxpi aarch64 hal builder

Extracts the VMX-pi HAL from the Studica Ubuntu 22.04 / ROS2 Humble disk image
(`/usr/local`) and packages it as arm64 `.deb` files, so it can be installed on
other Debian/Ubuntu-based aarch64 distributions.

| Package | Contents |
|---|---|
| `vmxpi-hal` | runtime libs (C++, Python, Java, C#), `ld.so.conf.d` + Python `.pth` |
| `vmxpi-hal-dev` | headers, static lib |
| `vmxpi-hal-examples` | example sources |

## Usage (WSL / Linux, as root)

Put the image next to the scripts (or set `IMG=`), then:

```bash
sudo bash build-deb.sh      # writes dist/*.deb   (env: IMG=..., VERSION=...)
sudo bash test-install.sh   # installs them in arm64 containers (ubuntu:22.04, debian:12)
```

Requires `dpkg-deb`, `fakeroot`, `sfdisk`, loop-mount support; the test needs Docker + qemu-user.
Installed files land in `/usr/local/lib/vmxpi` and `/usr/local/include/vmxpi`
(the HAL examples hardcode that path).

## Licensing

- **This repository's scripts**: MIT (see `LICENSE`).
- **The HAL** (headers, libraries, examples) is by Kauai Labs under the MIT license;
  the `.deb` files carry that notice in `/usr/share/doc/<package>/copyright`.
- The HAL static library bundles third-party code (pigpio, rpi_ws281x). Their notices
  must be completed in `build-deb.sh` before public redistribution.
- This is an **unofficial repackaging**, not affiliated with Kauai Labs or Studica.
- The disk image and the built `.deb` files are **not** included in this repo
  (`.gitignore`). Obtain the image from its official source; check its terms
  before redistributing any derived binaries.

## Do not redistribute the built `.deb` files

**Secondary distribution of the generated `.deb` packages is discouraged.**
They contain binaries taken from a third-party image whose redistribution terms
are unverified, plus bundled third-party code (pigpio, rpi_ws281x) whose notices
are incomplete. Build the packages yourself from your own copy of the image
instead of sharing or hosting the `.deb` files (releases, package repos, mirrors).
