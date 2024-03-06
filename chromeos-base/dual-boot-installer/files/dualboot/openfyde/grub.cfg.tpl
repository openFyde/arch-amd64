#FydeOS 2020-08-24 Author: yang@fydeos.io
defaultA=0
defaultB=1
search --label --set dualboot_part OFYDE-DUAL-BOOT
set img=($dualboot_part)/openfyde/openfyde_dual_boot.img
loopback loopdev $img
gptpriority loopdev 2 prioA
gptpriority loopdev 4 prioB
if [ $prioA -lt $prioB ]; then
  set default=$defaultB
else
  set default=$defaultA
fi

set timeout=1
set root=loopdev,gpt12

# NOTE: find rootfs by label (not partion label)

menuentry "openFyde multi-boot A" {
  linux /syslinux/vmlinuz.A init=/sbin/init boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi fydeos_dualboot %EXTRA_FLAG%
  initrd ($dualboot_part)/boot/dual_boot_ramfs.cpio
}

menuentry "openFyde multi-boot B" {
  linux /syslinux/vmlinuz.B init=/sbin/init boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi fydeos_dualboot %EXTRA_FLAG%
  initrd ($dualboot_part)/boot/dual_boot_ramfs.cpio
}

menuentry "FydeOS Recovery Tools" {
  set root=$dualboot_part
  linux /boot/openfyde_vmlinuzB init=/sbin/init root=%ROOTDEV% boot=local rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi %EXTRA_FLAG%
  initrd /boot/core_util_ramfs.cpio
}
