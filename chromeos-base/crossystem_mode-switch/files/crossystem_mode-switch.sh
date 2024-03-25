#!/bin/bash
ENABLE_KERNEL_FLAG="cros_debug"
GRUB_MNT=""
DUAL_BOOT_GRUB_CFG="/EFI/fydeos/grub.cfg"
DUAL_OPENFYDE_GRUB_CFG="/EFI/openfyde/grub.cfg"
GRUB_CFG="/efi/boot/grub.cfg"
declare -A KERNEL_ARGS

help() {
  echo "Usage:$0 <dev_mode|enable-dev_mode|disable-dev_mode|rootfs-verification|disable-rootfs-verification>
 dev_mode: display dev/base statue
 enable-dev_mode: set OS to dev mode
 disable-dev_mode: set OS to base mode
 rootfs-verification: display rootfs-verification state.
 disable-rootfs-verification: set rootfs to normal mode.
"
}

die() {
  echo "Error:" $@
  echo "------------------------"
  help
  exit 1
}

get_rootdev() {
  local part=""
  part=$(rootdev -s)
  if [[ ! "$part" = *"3" ]] && [[ ! "$part" = *"5" ]]; then
    echo ""
    return 1
  fi
  echo "${part::-1}"
}

parse_command_line() {
  for arg in $(cat /proc/cmdline); do
    if [[ $arg == \"* ]]; then
      arg=${arg:1}
    fi
    if [[ $arg == *\" ]]; then
      arg=${arg%\"}
    fi
    if [[ $arg == *'='* ]]; then
      KERNEL_ARGS["${arg%%=*}"]="${arg#*=}"
    else
      KERNEL_ARGS["$arg"]=1
    fi
  done
}

is_dualboot() {
  [ -n "${KERNEL_ARGS[fydeos_dualboot]}" ]
}

is_openfyde() {
  cat /etc/lsb-release | grep CHROMEOS_RELEASE_BOARD | grep -qi openfyde
}

find_grub_cfg() {
  local tmp_mnt=$(mktemp -d)
  local tmp_grub=$tmp_mnt
  if is_dualboot; then
		if is_openfyde; then
			tmp_grub+=$DUAL_OPENFYDE_GRUB_CFG
		else
    	tmp_grub+=$DUAL_BOOT_GRUB_CFG
		fi
  else
    tmp_grub+=$GRUB_CFG
  fi
  local rootdev=""
  rootdev=$(get_rootdev)
  for efi_dev in $(sudo cgpt find -t efi); do
    if ! is_dualboot && [[ -n "$rootdev" ]] && [[ ! "$efi_dev" = "$rootdev"* ]]; then
      continue
    fi
    sudo mount $efi_dev $tmp_mnt || die "failed to mount $efi_dev"
    if [ -f $tmp_grub ]; then
      GRUB_MNT=$tmp_mnt
      echo $tmp_grub
      return
    fi
    sudo umount $tmp_mnt
  done
  rmdir $tmp_mnt
  die "failed to find grub.cfg"
}

contains_cros_debug() {
  local grub_cfg=$1
  [ -n "$(grep -s $ENABLE_KERNEL_FLAG $grub_cfg)" ]
}

cros_debug_state() {
  if [ "${KERNEL_ARGS[cros_debug]}" -eq 1 ]; then
    echo "dev"
  else
    echo "base"
  fi
}

enable_cros_debug() {
  local grub_cfg=$(find_grub_cfg)
  if ! contains_cros_debug $grub_cfg; then
    echo "update $grub_cfg .."
    sudo sed -i s/cros_efi/cros_efi\ cros_debug/g $grub_cfg
  fi
  echo "Success to enable cros_debug mode. Please reboot system later."
}

disable_cros_debug() {
  local grub_cfg=$(find_grub_cfg)
  if contains_cros_debug $grub_cfg; then
    sudo sed -i s/cros_debug//g $grub_cfg
  fi
  echo "Success to disable cros_debug mode. Please reboot system later."
}

rootfs-verification_state() {
  if [ -n "$(sudo dmsetup ls |grep vroot)" ]; then
    echo "rootfs-verification enabled"
  else
    echo "rootfs-verification disabled"
  fi
}

enable-rootfs-verification() {
  local flag=$2
  if is_dualboot; then
    die "Dualboot mode doesn't support rootfs verification".
  fi
  if [ "${flag}" != "no-warning" ]; then
    read -p "It will make the system unusable, do you want to proceed anyway? Input 'yes' to continue, other to exit :" input
    if [ "$input" != "yes" ]; then
      die "the command is terminated."
    fi
  fi
  local grub_cfg=$(find_grub_cfg)
  cat $grub_cfg | sed s/defaultA=0/defaultA=2/g |sed s/defaultB=1/defaultB=3/g > /tmp/grub_tmp.cfg
  sudo mv /tmp/grub_tmp.cfg $grub_cfg || die "Failed to replace $grub_cfg"
  echo "Success to enable rootfs-verification. Reboot to apply. You can reverse it by running '$0 disable-rootfs-verification'"
}

enable_all_rootfs_rw() {
  source /usr/share/vboot/bin/common_minimal.sh
  local ssd_device=$(rootdev -s -d)
  local bs=$(blocksize ${ssd_device})
  for rootfs_index in 3 5;do
    local root_offset_sector=$(partoffset $ssd_device $rootfs_index)
    local root_offset_bytes=$((root_offset_sector * bs))
    if ! is_ext2 $ssd_device $root_offset_bytes > /dev/null 2>&1; then
      debug_msg "Non-ext2 partition: $ssd_device$rootfs_index, skip."
    elif ! rw_mount_disabled "$ssd_device" "$root_offset_bytes" > /dev/null 2>&1 ; then
      debug_msg "Root file system is writable. No need to modify."
    else
      enable_rw_mount "$ssd_device" "$root_offset_bytes" > /dev/null 2>&1 || die "Failed turning off rootfs RO bit. OS may be corrupted. "
    fi
  done
}

disable-rootfs-verification() {
  local grub_cfg=$(find_grub_cfg)
  enable_all_rootfs_rw
  if ! is_dualboot; then
    cat $grub_cfg | sed s/defaultA=2/defaultA=0/g |sed s/defaultB=3/defaultB=1/g > /tmp/grub_tmp.cfg
    sudo mv /tmp/grub_tmp.cfg $grub_cfg || die "Failed to replace $grub_cfg"
  fi
  echo "Successfully disabled rootfs verification. A reboot is required to activate these changes."
  read -r -p "Would you like to reboot now? [Y/N] " yn
  if [[ "$yn" == "y" ]] || [[ "$yn" == "Y" ]]; then
    echo "Rebooting..."
    reboot
  fi
}

cleanup() {
  if [ -n "$GRUB_MNT" ]; then
    sudo umount $GRUB_MNT
    rmdir $GRUB_MNT
  fi
}

main() {
  parse_command_line
  trap cleanup INT TERM EXIT
  case $1 in
    dev_mode) cros_debug_state;;
    enable-dev_mode) enable_cros_debug;;
    disable-dev_mode) disable_cros_debug;;
    rootfs-verification) rootfs-verification_state;;
    disable-rootfs-verification) disable-rootfs-verification;;
    *) die "unknown command: $1";;
  esac
}

main $@
