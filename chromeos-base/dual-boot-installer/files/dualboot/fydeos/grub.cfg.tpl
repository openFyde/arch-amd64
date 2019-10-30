#FydeOS 2018-12-29 Author: yang@fydeos.io
set default=0
set timeout=1

# NOTE: find rootfs by label (not partion label)

menuentry "FydeOS dual-boot" {
  search --label --set root FYDEOS-DUAL-BOOT
  linux /boot/fydeos_vmlinuzA init=/sbin/init root=%ROOTDEV% boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi cros_debug  fydeos_dualboot
  initrd /boot/dual_boot_ramfs.cpio.xz
}

menuentry "FydeOS dual-boot Backup" {
  search --label --set root FYDEOS-DUAL-BOOT
  linux /boot/fydeos_vmlinuzB init=/sbin/init root=%ROOTDEV% boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi cros_debug fydeos_dualboot
  initrd /boot/dual_boot_ramfs.cpio.xz
}

menuentry "FydeOS Recovery Tools" {
  search --label --set root FYDEOS-DUAL-BOOT
  linux /boot/fydeos_vmlinuzB init=/sbin/init root=%ROOTDEV% boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi cros_debug
  initrd /boot/core_util_ramfs.cpio.xz
}
