#!/usr/bin/env bash
set -euo pipefail

recipe=$(cd -- "$(dirname -- "$0")" && pwd)
: "${ARMBIAN_REV:?Set ARMBIAN_REV from the workflow environment}"
: "${LINUX_REV:?Set LINUX_REV from the workflow environment}"
: "${UBOOT_TAG:?Set UBOOT_TAG from the workflow environment}"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
out=$(realpath -m -- "${1:?Usage: bash odroidn2/build.sh OUTPUT_DIRECTORY}")
mkdir -p "$out"

# Build downloads, source trees, and rootfs staging use the Armbian filesystem.
free=$(df -Pk . | awk 'NR == 2 { print $4 }')
if (( free < 30 * 1024 * 1024 )); then
    echo 'Need at least 30 GiB free in the Armbian checkout; use a larger Linux runner or another filesystem.' >&2
    exit 1
fi

if [[ "$(git rev-parse HEAD)" != "$ARMBIAN_REV" ]]; then
    echo "Run from the Armbian build tree at $ARMBIAN_REV." >&2
    exit 1
fi
patch=9000-odroid-n2-fclk.patch
cmp "$recipe/patches/$patch" "userpatches/u-boot/$UBOOT_TAG/board_odroidn2/$patch"
./compile.sh build BOARD=odroidn2 BRANCH=current RELEASE=resolute \
    BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
    KERNELBRANCH="commit:$LINUX_REV" COMPRESS_OUTPUTIMAGE=sha,img

shopt -s nullglob
images=(output/images/*_6.18.65_minimal.img)
packages=(output/debs/**/linux-u-boot-odroidn2-current_*.deb output/debs/linux-u-boot-odroidn2-current_*.deb)
if (( ${#images[@]} != 1 || ${#packages[@]} != 1 )); then
    echo 'Expected one Linux 6.18.65 Minimal image and one ODROID N2 U-Boot package.' >&2
    exit 1
fi
image=${images[0]}
(cd output/images && sha256sum -c "${image##*/}.sha")
dpkg-deb -x "${packages[0]}" "$work/package"
uboot="$work/package/usr/lib/linux-u-boot-current-odroidn2"
grep -aFq 'N2 SD: enabled FCLK_DIV2' "$uboot/u-boot-dtb.img"
grep -aFq 'N2 eMMC: enabled FCLK_DIV2' "$uboot/u-boot-dtb.img"
# The FIP is packed. Verify the actual pre-partition bytes against the
# corresponding package, rather than searching the root filesystem for a string.
# Armbian preserves the MBR partition table at offsets 442 through 511.
cmp -n 442 "$uboot/u-boot.bin" "$image"
cmp -n "$(($(stat -c %s "$uboot/u-boot.bin") - 512))" "$uboot/u-boot.bin" "$image" 512 512

asset=Armbian-OdroidN2Plus-headless-FCLK.img.xz
xz -T2 -3 -c "$image" > "$out/$asset"
xz -t "$out/$asset"
(cd "$out" && sha256sum "$asset" > SHA256SUMS)
cp "$recipe/patches/$patch" "$out/$patch"
{
    printf 'ARMBIAN_REV=%s\nLINUX_REV=%s\nUBOOT_TAG=%s\n' "$ARMBIAN_REV" "$LINUX_REV" "$UBOOT_TAG"
    printf 'FIP_REV=%s\n' "$(git -C cache/sources/amlogic-boot-fip rev-parse HEAD)"
    printf 'PATCH_SHA256=%s\n' "$(sha256sum "$out/$patch" | cut -d ' ' -f1)"
    printf 'UBOOT_PACKAGE_VERSION=%s\n' "$(dpkg-deb -f "${packages[0]}" Version)"
} > "$out/build-manifest.txt"
