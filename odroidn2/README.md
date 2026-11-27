# ODROID N2+ headless Armbian

Unofficial Ubuntu 26.04 Minimal, Linux 6.18.65, and U-Boot 2026.07. The board-scoped patch enables `FCLK_DIV2` before either storage controller selects it. The same combined image passed separate unattended cold boots from microSD (`mmc 0:1`) and eMMC (`mmc 1:1`) on ODROID N2+. Both reached Armbian's first-login prompt. N2 and SPI/Petitboot remain untested. Repeat both tests on the GitHub-built artifact.

## Build and publish

Dispatch **ODROID N2+ Armbian Release** from the Actions tab once the workflow is on the default branch. The build needs an x86-64 Linux runner with passwordless sudo and at least 30 GiB free on the checkout filesystem. The workflow checks out the pinned Armbian tree and registers the patch before invoking the build script. To mirror those steps locally, run from the `comp` checkout:

```sh
# Export ARMBIAN_REV, LINUX_REV, and UBOOT_TAG from the workflow's top-level env.
git clone https://github.com/armbian/build.git armbian
git -C armbian checkout --detach "$ARMBIAN_REV"
patch=9000-odroid-n2-fclk.patch
install -Dm644 "odroidn2/patches/$patch" \
    "armbian/userpatches/u-boot/$UBOOT_TAG/board_odroidn2/$patch"
(cd armbian && bash ../odroidn2/build.sh ../odroidn2-output)
```

Armbian applies the registered patch after preparing its U-Boot worktree. Applying it directly with `git apply` before the build would bypass that patch pipeline.

The workflow's top-level `env` pins Armbian and Linux by commit and names the Armbian board's U-Boot tag. The manifest records those values, the resolved FIP revision, the package version, and the patch hash. Ubuntu packages and some Armbian dependencies resolve at build time, so this is not a promise of byte-for-byte reproducibility.

CI verifies Armbian's image checksum, checks both gate markers in the U-Boot package, compares the packed bootloader bytes in the image against the package, and tests the `.xz`. It then attests the assets and publishes them under `odroidn2/<version>` without marking the release as Latest. Rerunning the same version can replace its assets; use a new version for a distinct build.

## Verify the release on hardware

1. Download the release assets and run `sha256sum -c SHA256SUMS` beside the `.img.xz`. Flash the archive with a compatible imager, or decompress it with `xz -dk` and flash the resulting `.img`. Confirm the target device: flashing overwrites it.
2. Test each medium separately, with only the selected microSD or eMMC attached and no USB storage. Set the switch to **MMC**, connect UART at 115200 baud, and power-cycle. Don't interrupt autoboot or write registers manually.
3. For microSD, check that `/boot/boot.scr` loads from `mmc 0:1`; for eMMC, check `mmc 1:1`. Each boot should reach the Armbian first-login prompt. Capture the `N2 SD` or `N2 eMMC` gate marker when the gate starts off. Attach both logs and record the board tested.

The workflow publishes automatically, before these hardware tests. Before dispatching, meet redistribution requirements for the image: provide applicable license notices and corresponding source for shipped packages, and verify firmware redistribution terms. The build manifest and patch alone are not a corresponding-source bundle.
