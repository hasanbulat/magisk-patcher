#!/bin/bash

ORI_BOOT=$1
SHA1=$(./magiskboot sha1 ${ORI_BOOT})
RANDOMSEED=$(tr -dc 'a-f0-9' < /dev/urandom | head -c 16)
BUILD_PROP="system/etc/ramdisk/build.prop"
DATE=$(date +%d%m%y)
PATCH_MODE="boot"
if [ $(basename ${ORI_BOOT}) == "init_boot.img" ]; then
  PATCH_MODE="init_boot"
fi
echo "boot mode: ${PATCH_MODE}"
IF_SAMSUNG=0
exit_if_failed() {
    if [ $? -ne 0 ]; then
        echo "ERROR - Previous step failed!"
        exit 1
    fi
}

# Read img prop from ramdisk
get_prop() {
  cpio -i --to-stdout --quiet < ramdisk.cpio $BUILD_PROP | grep $1 | cut -d "=" -f 2
}

cleanup() {
    ./magiskboot cleanup
    if [ -f new-boot.img ]; then
      rm new-boot.img
    fi
}

if [ $# -ne 1 ]; then
    echo "USAGE - ./patch.sh <ori_boot.img>"
    exit 1
fi

cleanup

# Unpack Boot image
./magiskboot unpack ${ORI_BOOT} 2>/dev/null

BRAND=$(get_prop bootimage.brand)
DEVICE=$(get_prop bootimage.device)
MODEL=$(get_prop bootimage.model)
MODEL="${MODEL// /_}"
NAME=$(get_prop bootimage.name)
IMG_ID=$(get_prop build.id)
INCR_VER=$(get_prop version.incremental)
SDK_VER=$(get_prop version.sdk)
PATCHED_IMG="AZQ_${PATCH_MODE}_${BRAND}_${MODEL}_${IMG_ID}_${DATE}"

if [ ${BRAND} == "samsung" ]; then
  IF_SAMSUNG=1
  PATCHED_IMG="AZQ_${PATCH_MODE}_${BRAND}_${MODEL}_${INCR_VER}_${DATE}"
fi
PATCHED_IMG="${PATCHED_IMG// /_}"
PATCHED_IMG=$(tr [:lower:] [:upper:] <<< ${PATCHED_IMG})

echo "${MODEL}"

# Write  config file
CONFIG="devices_config/${BRAND}/${MODEL}"
config() {
  cat ${CONFIG} > config
  echo "SHA1=$SHA1" >> config
  echo "RANDOMSEED=0x$RANDOMSEED" >> config
}

if [ -f ${CONFIG} ]; then
  config
else
  echo "ERROR - Can't find config for ${CONFIG}"
  exit 1
fi

# Patch Ramdisk
echo "# Patching ramdisk"
./magiskboot cpio ramdisk.cpio \
  "add 0750 init magiskinit" \
  "mkdir 0750 overlay.d" \
  "mkdir 0750 overlay.d/sbin" \
  "add 0644 overlay.d/sbin/magisk64.xz magisk64.xz" \
  "add 0644 overlay.d/sbin/stub.xz stub.xz" \
  "patch" \
  "backup ramdisk.cpio.orig" \
  "mkdir 000 .backup" \
  "add 000 .backup/.magisk config" 2>/dev/null
exit_if_failed

# Pacth Kernel
if [ -f kernel ]; then
  echo "# Patching fstab in boot image"
  ./magiskboot dtb dtb patch 2>/dev/null

  echo "# Patching Remove Samsung RKP"
  ./magiskboot hexpatch kernel \
    49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
    A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054

  echo "# Patching remove samsung defex"
  ./magiskboot hexpatch kernel 821B8012 E2FF8F12

  echo "# Patching skip_initramfs -> want_initramfs"
  ./magiskboot hexpatch kernel \
    736B69705F696E697472616D667300 \
    77616E745F696E697472616D667300 2>/dev/null
fi

# Repack Boot image
./magiskboot repack ${ORI_BOOT} ${PATCHED_IMG}.img 2>/dev/null
echo "# Created - ${PATCHED_IMG}.img"
exit_if_failed

if [ $IF_SAMSUNG -eq 1 ]; then
  echo "it's samsung, make tar"
  mv ${PATCHED_IMG}.img ${PATCH_MODE}.img
  lz4 -B6 -f --content-size ${PATCH_MODE}.img ${PATCH_MODE}.img.lz4 2>/dev/null
  exit_if_failed
  tar -H ustar -cf "${PATCHED_IMG}.tar" ${PATCH_MODE}.img.lz4 2>/dev/null
  exit_if_failed
  echo "Created - ${PATCHED_IMG}.tar"
fi