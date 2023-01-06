#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
BOOT_DIR="/boot"
KERNEL_A="fydeos_vmlinuzA"
KERNEL_B="fydeos_vmlinuzB"
SELF=$(basename $0)
LOG_MOD="install_kernel"

set -e

. $DUAL_SCRIPT_DIR/fydeos_util.sh

print_version() {
    echo "$SELF version:${VERSION}, maintained by Fyde Innovations. All rights reserved."
}

print_usage() {
    print_version
    echo
    echo "Installing or updating kernel and initramfs for FydeOS multi-boot configuration."
    echo "Usage: $SELF [-d | --dst <target dev or folder>] [-h | --help]
       Example: 
           $SELF -d /dev/sda5    #partition device as target
           $SELF -d /mnt/sda5    #mount point as target
           $SELF                 #find the partition itself as target
       "
}

_main() {
	  local target_dir=${partmnt}${BOOT_DIR}
    local target_kernel=vmlinuz-$(get_release_version)
	  create_dir $target_dir
    pushd $target_dir > /dev/null 2>&1
    info "Installing new kernel..."
    cp -f /boot/vmlinuz $target_kernel
    ln -s -f $target_kernel $KERNEL_A
    if [ ! -L $KERNEL_B ];then
        ln -s -f $target_kernel $KERNEL_B
    fi
    info "Installing initramfs images..."
    cp -f $DUAL_SCRIPT_DIR/initrd/*.cpio $target_dir
    popd > /dev/null 2>&1
    info "Done."
}

# global variables
partmnt=

main() {
  while [[ $# -gt 0 ]]; do
      opt=$1
      case $opt in
          -d | --dst )
              if [ -d $2 ]; then
                  partmnt=$2
              elif [ -b $2 ]; then
                  partmnt=$(get_mnt_of_part  $2)
              fi
              shift
              ;;
          -h | --help )
        print_usage
        exit 0
              ;;
          * )
              print_usage
        exit 0
              ;;
      esac

      shift
  done
  if [ -z "$partmnt" ]; then
    partmnt=$(get_mnt_of_part $(get_dualboot_part))
  fi

  _main
}

main "$@"  2>&1 | tee -a "$LOG_FILE"
