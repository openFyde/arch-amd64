#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
BOOT_LOADER_DIR="/usr/share/dualboot/fydeos"
BOOT_FILES="bootx64.efi os_fydeos.png"
LOG_MOD="install_fydeos_loader"
TPL="grub.cfg.tpl"
TMP_DIR="/tmp"
EFI="/EFI/fydeos"
SELF=$(basename $0)
FILTERS=(
 "BOOT_IMAGE="
 "init="
 "boot="
 "rootwait"
 "noresume"
 "noinitrd"
 "noswap"
 "loglevel="
 "console="
 "i915.modeset=1"
 "cros_efi"
 "fydeos_dualboot"
 "linux"
 "vmlinuz"
)

LOOPDEV=""
DUALBOOT_PART_MNT=""
LOOPEFI_MNT=""

set -e

. $DUAL_SCRIPT_DIR/fydeos_util.sh

if is_openfyde; then
  EFI="/EFI/openfyde"
  BOOT_LOADER_DIR="/usr/share/dualboot/openfyde"
  BOOT_FILES="bootx64.efi os_openfyde.png"
fi

print_version() {
    echo "$SELF version:${VERSION}, maintained by Fyde Innovations. All rights reserved."
}

print_usage() {
    print_version
    echo
    echo "Installing openFyde/FydeOS bootloader for multi-boot scheme."
    echo "Usage: $SELF [-d | --dst <target dev or folder>] [-h | --help]
       Example:
           $SELF -d /dev/sda1    #partition as target
           $SELF -d /mnt/sda1    #mount point as target
           $SELF                 #find the ESP partition as target
       "
}

get_cmdline() {
  cat /proc/cmdline
}

clean_up() {
  if [ -n "$LOOPEFI_MNT" ]; then
    umount $LOOPEFI_MNT
  fi
  if [ -n "$LOOPDEV" ]; then
    losetup -d $LOOPDEV
  fi
  if [ -n "$DUALBOOT_PART_MNT" ]; then
    umount $DUALBOOT_PART_MNT
  fi
}

find_dualboot_image_grub_cfg() {
  local dualboot_part=$(get_dualboot_part)
  local tmp_dualboot_mnt=$(mktemp -d)
  mount $dualboot_part $tmp_dualboot_mnt 2>&1 1>/dev/null || die "failed to mount $dualboot_part"
  DUALBOOT_PART_MNT=$tmp_dualboot_mnt
  local dualboot_img="${tmp_dualboot_mnt}$(get_dualboot_img)"
  [ -f $dualboot_img ] || die "Can't find $dualboot_img"
  local loop_dev=$(losetup -f)
  losetup -P $loop_dev $dualboot_img 2>&1 1>/dev/null || die "failed to setup $dualboot_img"
  LOOPDEV=$loop_dev
  local tmp_efi_mnt=$(mktemp -d)
  mount ${loop_dev}p12 $tmp_efi_mnt 2>&1 1>/dev/null || die "faile to mount ${loop_dev}p12"
  [ -f $tmp_efi_mnt/efi/boot/grub.cfg ] || die "Can't find ${tmp_efi_mnt}/efi/boot/grub.cfg"
  echo $tmp_efi_mnt/efi/boot/grub.cfg
}

get_extra_flags() {
  local grub_cfg=$1
  local index=$2
  local extra_flags
  if [ $index -eq 3 ]; then
    #skip verified fs
    index=1
  fi
  for flag in $(grep 'linux ' $grub_cfg | sed -n "${index},1p"); do
    for filter in ${FILTERS[@]}; do
      if [ -n "$(echo $flag | grep $filter)" ]; then
        continue 2
      fi
    done
    extra_flags+=" $flag"
  done
  echo $extra_flags
}

# global variables
partmnt=""
dual_boot_dev=$(get_dualboot_part)

_main() {
	local target_dir=${partmnt}${EFI}
  local extra_flags=""
  info "Installing openFyde/FydeOS bootloader..."
  create_dir $target_dir
  touch_dir $target_dir
  trap clean_up INT EXIT TERM
  local efi_grub_cfg=$(find_dualboot_image_grub_cfg)
  cp ${BOOT_LOADER_DIR}/${TPL} /tmp/${TPL}
  local index=1
  for line in $(grep 'linux ' /tmp/${TPL} -n | awk 'BEGIN {FS= ":"} { print $1}'); do
    extra_flags=$(get_extra_flags $efi_grub_cfg $index)
    sed -i -E "${line}s#%EXTRA_FLAG%#${extra_flags}#g" /tmp/${TPL}
    index=$(($index + 1))
  done
  cp /tmp/${TPL} ${target_dir}/grub.cfg
	for file in $BOOT_FILES; do
		cp -f ${BOOT_LOADER_DIR}/${file} $target_dir
  done
  info "Done."
}

main() {
  if [ -z "$dual_boot_dev" ]; then
    die "openFyde/FydeOS multi-boot partition not found, abort."
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
          printf "Selecting EFI partition:"
      read -n 1 selected
      if [ -z "${efi_arr[$selected]}" ]; then
              die "No ESP found, abort."
          fi
      efi_devs=${efi_arr[$selected]}
      fi
    partmnt=$(get_mnt_of_part $efi_devs)
  fi

  _main
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
