#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
BOOT_LOADER_DIR="/usr/share/dualboot/fydeos"
BOOT_FILES="bootx64.efi os_fydeos.png"
TPL="grub.cfg.tpl"
TMP_DIR="/tmp"
EFI="/EFI/fydeos"
SELF=$(basename $0)
FILTERS=(
 "BOOT_IMAGE="
 "init="
 "root="
 "boot="
 "rootwait"
 "noresume"
 "noinitrd"
 "noswap"
 "ro"
 "loglevel="
 "console="
 "i915.modeset=1"
 "cros_efi"
 "cros_debug"
 "fydeos_dualboot"
)

set -e

. $DUAL_SCRIPT_DIR/fydeos_util.sh

print_version() {
    echo "$SELF version:${VERSION} Copyright By FydeOS"
}

print_usage() {
    print_version
    echo
    echo "Insall FydeOS boot loader for dualboot2"
    echo "Usage: $SELF [-d | --dst <target dev or folder>] [-h | --help]
       Example: 
           $SELF -d /dev/sda1    #partition device as target
           $SELF -d /mnt/sda1    #mount point as target
           $SELF                 #find the ESP partition as target
       "
}

get_cmdline() {
  cat /proc/cmdline
}

get_extra_flags() {
  local extra_flags
  for flag in $(get_cmdline); do
    for filter in ${FILTERS[@]}; do
      if [ -n "$(echo $flag | grep $filter)" ]; then
        continue 2
      fi
    done
    extra_flags="$extra_flags $flag"
  done
  echo $extra_flags
}

main() {
	local target_dir=${partmnt}${EFI}
  local extra_flags=$(get_extra_flags)
  info "Install FydeOS Boot Loader"
  info "Extra command line flags: $extra_flags"
  create_dir $target_dir
  touch_dir $target_dir
	for file in $BOOT_FILES; do
		cp -f ${BOOT_LOADER_DIR}/${file} $target_dir
  done 
  cat ${BOOT_LOADER_DIR}/${TPL} | sed  "s#%ROOTDEV%#${dual_boot_dev}#g" \
    | sed "s#%EXTRA_FLAG%#${extra_flags}#g" \
		> $target_dir/grub.cfg	
  info "Done."
}

partmnt=
dual_boot_dev=$(get_dualboot_part)
if [ -z "$dual_boot_dev" ]; then
	die "please Install FydeOS dualboot partition at first."
fi
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
    efi_devs=$(get_efi_part)
	if [ $(echo $efi_devs |wc -w) -gt 1 ]; then
        index=1
		selected=1
		declare -a efi_arr
        for efi in $efi_devs; do
            echo "($index):${efi}"
			efi_arr[$index]=$efi
            index=$(($index+1))
        done
        printf "Select the EFI partiton:"
		read -n 1 selected
		if [ -z "${efi_arr[$selected]}" ]; then
            die "no efi founded."
        fi
		efi_devs=${efi_arr[$selected]}
    fi
	partmnt=$(get_mnt_of_part $efi_devs)
fi
main 
