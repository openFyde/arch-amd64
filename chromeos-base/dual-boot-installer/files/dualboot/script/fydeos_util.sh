#!/bin/bash
DUALBOOT_LABEL="FYDEOS-DUAL-BOOT"
CHROME_INSTALL_CMD="/usr/share/dualboot/chromeos-install.sh"
LOG_MOD=${LOG_MOD:-fydeos_dualboot}
LOG_FILE=/tmp/fydeos_dualboot.log
DUALBOOT_DIR="/fydeos"
DUALBOOT_IMG="${DUALBOOT_DIR}/fydeos_dual_boot.img"
VERSION="2.0.3"
FYDEOS_FINGERPRINT=".fydeos_dualboot"
# test if system in dualboot mode
is_dualboot() {
  [ -n "$(grep fydeos_dualboot /proc/cmdline)" ]
}

# get disk device from partition device.
# para $1: /dev/sda1 return /dev/sda    $1: /dev/mmcblk0p3 return /dev/mmcblk0
# para $1: /dev/nvme0n1p10 return /dev/nvme0n1
parse_disk_dev() {
  local disk=$1
  local disk=$(echo $1 | sed 's/[0-9_]*$//')
  if [ -z "$(echo $disk | grep sd)" ]; then
    disk=${disk%p}
  fi
  echo $disk
}

# label: $1 like FYDEOS-ROOT-A (partition lable) device: $2 like /dev/sda
# return : 4 (if partition is /dev/sda4)
find_partition_num_by_label() {
  local label=$1
  local device=$2
  cgpt find -l $label -n $device
}


#find the partition dev with partition lable
find_partition_by_label() {
  local label=$1
  local device=$2
  cgpt find -l $label $device
}


# $1 as /dev/mmcblk0p12 return 12
# $1 as /dev/nvme0n1p10 return 10
parse_partition_num() {
  local dev=$1
  echo ${dev##*[a-z]}
}

# $1 like /dev/sda4 return partition UUID
get_partuuid() {
  local dev=$1
  local disk=$(parse_disk_dev $dev)
  local part_num=$(parse_partition_num $dev)
  cgpt show -i $part_num -u $disk
}

get_partlabel() {
  local dev=$1
  local disk=$(parse_disk_dev $dev)
  local part_num=$(parse_partition_num $dev)
  cgpt show -i $part_num -l $disk
}

#sync partition label and fs label
sync_label() {
  local dev=$1
  local label=$(get_partlabel $dev)
  info "Sync label, label: $label, dev: $dev"
  tune2fs -L $label $dev
}

md5() {
  local file=$1
  local mdstr=$(md5sum $file)
  echo ${mdstr% *}
}

# true if $1 and $2 is equal
cmp_files() {
  local md_a=$(md5 $1)
  local md_b=$(md5 $2)
  [ "$md_a" == "$md_b" ]
}

#find ext4 file system exist in a partition (like /dev/sda5)
does_ext4_exist() {
  local dev=$1
  dumpe2fs -h $dev >null 2>&1; 
}

create_dir() {
  if [ ! -d $1 ]; then
    mkdir -p $1
  fi
}

touch_dir() {
  if [ -d $1 ]; then
    touch $1/${FYDEOS_FINGERPRINT}  
  fi
}

list_touched_dir() {
  if [ -d $1 ]; then
    for v_dir in `find $1 -name ${FYDEOS_FINGERPRINT}`; do
      echo ${v_dir%/*}
    done
  fi   
}

remove_touched_dir() {
  if [ -d $1 ]; then
    for v_dir in `find $1 -name ${FYDEOS_FINGERPRINT}`; do
      rm -rf ${v_dir%/*}
    done
  fi  
}

info_init() {
  if [ -n "$1" ]; then
    LOG_FILE=$1
  fi
}

clear_log() {
  cat /dev/null > "$LOG_FILE"
}

info() {
  echo "[$(date --rfc-3339=seconds)]:${LOG_MOD}:" "$@"
}

die() {
  info "$@"
  info "Error occured, the log file: $LOG_FILE"
  exit 1
}

#arg1: like /dev/sda1
get_partition_free_space() {
  [ ! -b $1 ] && die "error partiton dev."
  df -k --output=avail $1 | tail -n1
}

create_dualboot_image() {
  local part_dev=$1
  local mnt_dir=$(get_mnt_of_part $part_dev)
  create_dir ${mnt_dir}${DUALBOOT_DIR}
  local img="${mnt_dir}${DUALBOOT_IMG}"
  local partdev=$(rootdev ${mnt_dir})
  local freespace=$(get_partition_free_space $partdev)
  local imgspace=$(($freespace/100*100 - 1024*100))
  if [ $imgspace -lt $((1024*1024*9)) ];then
    die "Need more free space to create FydeOS image, abort."
  fi
  if [ -f $img ];then
    rm -f $img
  fi
  info "Creating FydeOS multi-boot image..."
  fallocate -l $(($imgspace*1024)) $img
  info "Allocate :${img}"
  local loopdev=$(load_img_to_dev $img)
  info "Installing FydeOS image..."
  ${CHROME_INSTALL_CMD} --yes --dst ${loopdev}
  info "Recycling system resources..."
  partx -d ${loopdev}
  losetup -d ${loopdev}
  umount ${mnt_dir}
  rmdir ${mnt_dir}
  info "Done."
}

load_img_to_dev() {
  local img=$1
  if [ ! -f $img ]; then
    die "Disk image does not exist, abort."
  fi
  local loopdev=$(losetup -f)
  losetup $loopdev $img
  echo $loopdev
}

umount_dev() {
  [ ! -b $1 ] && die "device:${1} does not exist, abort."
  partx -d $1
  losetup -d $1
}

get_dualboot_part() {
  cgpt find -l $DUALBOOT_LABEL
}

set_dualboot_part() {
  local part_dev=$1
  if [ -z "$(get_dualboot_part)" ];then
    info "Running command: cgpt add -i $(parse_partition_num $part_dev) -l $DUALBOOT_LABEL $(parse_disk_dev $part_dev)"
    cgpt add -i $(parse_partition_num $part_dev) -l $DUALBOOT_LABEL $(parse_disk_dev $part_dev) || info "set_dualboot_part, cgpt add boot entry error"
  fi
  sync_label $part_dev
}

get_efi_part() {
  cgpt find -t C12A7328-F81F-11D2-BA4B-00A0C93EC93B
}

get_mnt_of_part() {
  local partdev=$1
  [ ! -b $partdev ] && die "device:${1} does not exist, abort."
  local mntdir=$(lsblk -o mountpoint -l -n $partdev)
  if [ -z "${mntdir}" ];then
    mntdir=$(mktemp -d -p /tmp ${LOG_MOD}_XXXXX)
    mount -w $partdev $mntdir
  else
    local ro=$(lsblk -o ro ${partdev} |tail -n1)
    if [ $ro -eq 0 ]; then
      mount -o remount,rw ${mntdir}
    fi
  fi
  echo $mntdir
}

get_release_version() {
  local ver=$(grep CHROMEOS_RELEASE_VERSION /etc/lsb-release)
  echo ${ver#*=}
}

list_boot_entry() {
  efibootmgr -v |grep "Boot0"
}

get_first_boot_entry() {
  efibootmgr |grep BootOrder: |cut -c 12-15
}

convert_efi_path() {
  local sys_path=$1
  echo ${sys_path//\//\\\\}
}

convert_efi_path2() {
  local sys_path=$1
  echo ${sys_path//\//\\}
}

is_efi_in_boot_entries() {
  local efi_path=$(convert_efi_path $1)
  local efi_info=$(efibootmgr -v | grep -i "$efi_path")
  [ -n "${efi_info}" ]
}

get_boot_entry_by_path() {
  local efi_path=$(convert_efi_path $1)
  local entry=$(efibootmgr -v | grep -i "$efi_path" | head -n 1)
  echo $entry | cut -c 5-8    
}

list_all_efi() {
  local efi_mnt=$1
  local efi_files=$(find $efi_mnt -name *.efi)
  for efi in $efi_files; do
    echo ${efi#$efi_mnt}
  done    
}

is_efi_first_boot_entry() {
  local efi_path=$(convert_efi_path $1)
  local first_boot=$(get_first_boot_entry)
  local boot_info=$(efibootmgr | grep -i "${efi_path}" | grep "Boot${first_boot}")
  [ -n "${boot_info}" ]
}

create_entry() {
  local efi_path=""
  efi_path=$(convert_efi_path2 "$1")
  local label=$2
  local part_dev=$3
  info "Create entry, running command efibootmgr, loader: ${efi_path}, label: ${label}, device: ${part_dev}"
  efibootmgr -v -c -l "${efi_path}" -L "${label}" -d "$(parse_disk_dev "$part_dev")" \
    -p "$(parse_partition_num "$part_dev")" || info "Create entry, efibootmgr error"
  info "Create entry done."
}

safe_create_entry() {
  local efi=$1
  local label=$2
  local part_dev=$3
  if ! is_efi_in_boot_entries "$efi"; then
    create_entry "$efi" "${label}" "$part_dev"
  fi
}

remove_entry() {
  local efi_entry=""
  efi_entry=$(get_boot_entry_by_path "$1")
  info "Remove entry, $efi_entry, $1"
  efibootmgr -v -b "$efi_entry" -B
  info "Remove entry done."
}

safe_format() {
  local partdev=$1
  info "Safe format ${partdev}"
  [ ! -b "$partdev" ] && die "device:${1} does not exist, abort."
  local mntdir=""
  mntdir=$(lsblk -o mountpoint -l -n "$partdev")
  if [ -n "${mntdir}" ];then
    info "Un-mounting the partition:${partdev}"
    umount "$partdev" || die "The partition is being used, abort..."
  fi
  info "Formatting partition:${partdev}..."
  mkfs.ext4 -F "$partdev" || die "Safe format, mkfs error, abort."
  info "Modifying multi-boot partition label..."
  set_dualboot_part "$partdev"
  info "Safe format ${partdev} done."
}
