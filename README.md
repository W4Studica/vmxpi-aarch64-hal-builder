# vmxpi aarch64 hal builder

Extracts the VMX-pi HAL from the Studica Ubuntu 22.04 / ROS2 Humble disk image
(`/usr/local`) and packages it as one arm64 `.deb`, so it can be installed on
other Debian/Ubuntu-based aarch64 distributions. Both partitioned `.iso` images
and disk `.img` images are accepted; the image can also be set with `IMG=`.

| Package | Contents |
|---|---|
| `vmxpi-hal` | runtime libraries (C++, Python, Java, C#), headers, static libraries, example sources, `ld.so.conf.d`, and Python `.pth` |

## Usage (WSL / Linux, as root)

Put either image next to the scripts (or set `IMG=` to its path), then:

```bash
sudo bash build-deb.sh      # writes dist/vmxpi-hal_<version>_arm64.deb (env: IMG=..., VERSION=...)
sudo bash test-install.sh   # installs them in arm64 containers (ubuntu:22.04, debian:12)
```

If the image partition is already mounted at its `/usr/local` directory, set
`SRC_DIR=/path/to/usr/local` and run `bash build-deb.sh` without root; the
package staging uses `fakeroot`.

Requires `dpkg-deb`, `fakeroot`, `sfdisk`, `file`, and read-only loop-mount support; the test needs Docker + qemu-user.
Installed files land in `/usr/local/lib/vmxpi` and `/usr/local/include/vmxpi`
(the HAL examples hardcode that path).

## Licensing

- **This repository's scripts**: MIT (see `LICENSE`).
- **The extracted HAL payload** is third-party material. Some files contain Kauai Labs
  MIT notices; this does not establish MIT licensing for every header, library,
  example or bundled component. The `.deb` records the unresolved scope in
  `/usr/share/doc/vmxpi-hal/copyright`.
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
