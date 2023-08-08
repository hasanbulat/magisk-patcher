#!/bin/bash

ORI_BOOT=$1
SHA1=$(./magiskboot sha1 ${ORI_BOOT})

exit_if_failed() {
    if [ $? -ne 0 ]; then
        echo "ERROR - Previous step failed!"
        exit 1
    fi
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
./magiskboot unpack ${ORI_BOOT} 2>/dev/null

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

echo "# Patching fstab in boot image"
./magiskboot dtb dtb patch 2>/dev/null
exit_if_failed

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

echo "# Creating - patched boot"
./magiskboot repack ${ORI_BOOT} 2>/dev/null
exit_if_failed