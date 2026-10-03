#!/bin/sh
# estimate-kernel-size.sh
#
# Early estimate of the NBG7815 kernel FIT size, usable right after
# `make target/linux/compile` and before the long package/image build.
#
# The sysupgrade kernel is a FIT containing compressed(Image) + the device tree.
# OpenWrt compresses the kernel with its own host tool (libdeflate-gzip -12),
# which is several percent smaller than plain `gzip -9`, so this script uses the
# same tool from staging_dir. If that tool is missing the script SKIPS (exit 0)
# instead of guessing, because a wrong guess would fail builds that actually fit.
#
# scripts/check-kernel-size.sh on the finished sysupgrade image stays the
# authoritative check.
#
# Usage:
#   scripts/estimate-kernel-size.sh [BUILD_DIR]      (default: build_dir)
#
# Environment overrides:
#   LIMIT           partition size in bytes            (default: 6291456)
#   WARN_HEADROOM   warn below this many free bytes    (default: 131072)
#   FIT_OVERHEAD    bytes added for FIT headers/hashes (default: 8192)
#   DTB_SIZE        device tree size in bytes          (default: 55000)
#   STAGING_DIR_HOST  OpenWrt host staging dir         (default: staging_dir/host)
#
# Exit codes: 0 = fits (or skipped), 1 = too large, 2 = build output not found.

set -eu

BUILD_DIR="${1:-build_dir}"
LIMIT="${LIMIT:-$((6 * 1024 * 1024))}"
WARN_HEADROOM="${WARN_HEADROOM:-$((128 * 1024))}"
FIT_OVERHEAD="${FIT_OVERHEAD:-8192}"
DTB_SIZE="${DTB_SIZE:-55000}"
HOST_DIR="${STAGING_DIR_HOST:-staging_dir/host}"
COMPRESSOR="$HOST_DIR/bin/libdeflate-gzip"

error() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::$*"; else echo "ERROR: $*" >&2; fi
}

warning() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi
}

# Prefer the copy OpenWrt keeps directly in the kernel build dir (KDIR/Image, the
# plain kernel used for the sysupgrade FIT). The copy under linux-*/arch/arm64/boot
# is overwritten by the initramfs build later in the same `make world`, so it is
# only a fallback.
IMAGE="$(find "$BUILD_DIR" -type f -path '*/linux-qualcommax_ipq807x/Image' 2>/dev/null | head -n 1)"
if [ -z "$IMAGE" ]; then
	IMAGE="$(find "$BUILD_DIR" -type f -path '*/linux-qualcommax_ipq807x/*/arch/arm64/boot/Image' 2>/dev/null | head -n 1)"
fi
if [ -z "$IMAGE" ]; then
	error "kernel Image not found under $BUILD_DIR (did 'make target/linux/compile' finish?)"
	exit 2
fi

if [ ! -x "$COMPRESSOR" ]; then
	warning "$COMPRESSOR not found; skipping the early estimate (the final check still runs)"
	exit 0
fi

GZ_SIZE="$("$COMPRESSOR" -n -12 -c "$IMAGE" | wc -c | tr -d ' ')"

# A compressed plain kernel is never anywhere near twice the partition. If it is,
# this is the initramfs kernel (rootfs embedded), which is meant to be large.
if [ "$GZ_SIZE" -gt $((LIMIT * 2)) ]; then
	warning "$IMAGE looks like the initramfs kernel ($GZ_SIZE B compressed); skipping the early estimate"
	exit 0
fi

ESTIMATE=$((GZ_SIZE + DTB_SIZE + FIT_OVERHEAD))
HEADROOM=$((LIMIT - ESTIMATE))

echo "Image:         $IMAGE"
echo "compressed:    $GZ_SIZE bytes (libdeflate-gzip -12)"
echo "dtb (assumed): $DTB_SIZE bytes"
echo "FIT overhead:  $FIT_OVERHEAD bytes (assumed)"
echo "estimate:      $ESTIMATE bytes"
echo "limit:         $LIMIT bytes"
echo "headroom:      $HEADROOM bytes"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Kernel size estimate (before image build)"
		echo "- estimate: $ESTIMATE B"
		echo "- limit: $LIMIT B"
		echo "- headroom: $HEADROOM B"
	} >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$ESTIMATE" -gt "$LIMIT" ]; then
	error "estimated kernel ($ESTIMATE B) exceeds the HLOS partition ($LIMIT B); stopping before the image build"
	exit 1
fi

if [ "$HEADROOM" -lt "$WARN_HEADROOM" ]; then
	warning "estimated headroom is only $HEADROOM B"
fi

echo "OK: estimated kernel fits"
