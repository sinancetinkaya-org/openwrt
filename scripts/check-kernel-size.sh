#!/bin/sh
# check-kernel-size.sh
#
# Check that the kernel FIT inside a Zyxel NBG7815 sysupgrade image fits into the
# 6 MiB eMMC kernel partition (0:HLOS / 0:HLOS_1). zloader only reads 6 MiB, and
# emmc_do_upgrade would truncate a larger kernel, which leaves the board unbootable.
#
# Usage:
#   scripts/check-kernel-size.sh [SYSUPGRADE_IMAGE]
#
# Environment overrides:
#   LIMIT           partition size in bytes          (default: 6291456)
#   WARN_HEADROOM   warn below this many free bytes  (default: 131072)
#
# Exit codes: 0 = fits, 1 = too large, 2 = usage / image problem.
# Works the same on a PC and in GitHub Actions (annotations and the step summary
# are only emitted when running there).

set -eu

DEFAULT_IMG="bin/targets/qualcommax/ipq807x/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin"
IMG="${1:-$DEFAULT_IMG}"
LIMIT="${LIMIT:-$((6 * 1024 * 1024))}"
WARN_HEADROOM="${WARN_HEADROOM:-$((128 * 1024))}"

error() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::$*"; else echo "ERROR: $*" >&2; fi
}

warning() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi
}

if [ ! -f "$IMG" ]; then
	error "sysupgrade image not found: $IMG"
	exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

if ! tar -xf "$IMG" -C "$tmp" 2>/dev/null; then
	error "$IMG is not a tar archive (is this a sysupgrade image?)"
	exit 2
fi

KERNEL="$(find "$tmp" -type f -name kernel | head -n 1)"
if [ -z "$KERNEL" ]; then
	error "no 'kernel' member found in $IMG; members are:"
	tar -tf "$IMG" >&2
	exit 2
fi

SIZE="$(wc -c < "$KERNEL" | tr -d ' ')"
HEADROOM=$((LIMIT - SIZE))

echo "image:    $IMG"
echo "kernel:   $SIZE bytes"
echo "limit:    $LIMIT bytes"
echo "headroom: $HEADROOM bytes"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Kernel size (NBG7815 HLOS partition)"
		echo "- kernel: $SIZE B"
		echo "- limit: $LIMIT B"
		echo "- headroom: $HEADROOM B"
	} >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$SIZE" -gt "$LIMIT" ]; then
	error "kernel ($SIZE B) is larger than the HLOS partition ($LIMIT B); flashing would truncate it"
	exit 1
fi

if [ "$HEADROOM" -lt "$WARN_HEADROOM" ]; then
	warning "only $HEADROOM B of headroom left in the HLOS partition"
fi

echo "OK: kernel fits"
