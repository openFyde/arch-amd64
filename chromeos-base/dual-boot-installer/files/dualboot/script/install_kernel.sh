#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
BOOT_DIR="/boot"
KERNEL_DIR="${DUAL_SCRIPT_DIR}/kernel"
KERNEL_A="fydeos_vmlinuzA"
KERNEL_B="fydeos_vmlinuzB"
SELF=$(basename $0)

set -e

. $DUAL_SCRIPT_DIR/fydeos_util.sh

print_version() {
    echo "$SELF version:${VERSION} Copyright By FydeOS"
}

print_usage() {
    print_version
    echo
    echo "Insall or update kernel and initramfs of FydeOS for dualboot2"
    echo "Usage: $SELF [-d | --dst <target dev or folder>] [-h | --help]
       Example: 
           $SELF -d /dev/sda5    #partition device as target
           $SELF -d /mnt/sda5    #mount point as target
           $SELF                 #find the partition itself as target
       "
}

main() {
	  local target_dir=${partmnt}${BOOT_DIR}
    local target_kernel=vmlinuz-$(get_release_version)
    local source_kernel=$(ls ${KERNEL_DIR}/vmlinuz-*)
    if [ -z "${source_kernel}" ]; then
      die "Can't find kenel at ${KERNEL_DIR}"
    fi
	  create_dir $target_dir
    pushd $target_dir > /dev/null 2>&1
    info "Install new kernel"
    cp -f $source_kernel $target_kernel
    ln -s -f $target_kernel $KERNEL_A
    if [ ! -L $KERNEL_B ];then
        ln -s -f $target_kernel $KERNEL_B
    fi
    info "Install initramfs images"
    cp -f $DUAL_SCRIPT_DIR/initrd/*.xz $target_dir
    popd > /dev/null 2>&1
    info "Done."
}

partmnt=
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
main 
