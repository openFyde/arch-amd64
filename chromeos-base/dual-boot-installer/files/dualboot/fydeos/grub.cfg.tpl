#FydeOS 2018-08-02 Author: yang@fydeos.io
set default=0
set timeout=1

# NOTE: find rootfs by label (not partion label)
search --label --set root FYDEOS-ROOT-A

menuentry "FydeOS" {
  linux /boot/vmlinuz init=/sbin/init root=PARTUUID=%PARTUUID% boot=local noinitrd rootwait noresume noswap ro loglevel=7 console= i915.modeset=1 cros_efi cros_debug fydeos_dualboot 
}

menuentry "Recovery tools" {
  linux /boot/vmlinuz.core loglevel=3
  initrd /boot/core.gz
}
