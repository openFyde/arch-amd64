#!/bin/bash
DUALBOOT_LABEL="FYDEOS-DUAL-BOOT"
LOG_MOD=fydeos_dualboot
LOG_FILE=/tmp/fydeos_dualboot.log
DUALBOOT_DIR="/fydeos"
DUALBOOT_IMG="${DUALBOOT_DIR}/fydeos_dual_boot.img"
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

info_init() {
    if [ -n "$1" ]; then
      LOG_FILE=$1
    fi
    LOG_FILE=$1
    LOG_MOD=${LOG_FILE##*/}
    LOG_MOD=${LOG_MOD%.*}
    echo "FydeOS dual boot install log:" > $LOG_FILE
}

info() {
    echo "[$(date --rfc-3339=seconds)]:${LOG_MOD}:" $@ | tee -a $LOG_FILE
}

die() {
    info $@
    info "Error occured, the log file: $LOG_FILE"
    exit 1
}

#arg1: like /dev/sda1
get_partition_free_space() {
    [ ! -b $1 ] && die "error partiton dev."
    df -k --output=avail $1 | tail -n1
}

create_dualboot_image() {
    local mnt_dir=$1
    create_dir ${mnt_dir}${DUALBOOT_DIR}
    local img="${mnt_dir}${DUALBOOT_IMG}"
    local partdev=$(rootdev ${mnt_dir})
    local freespace=$(get_partition_free_space $partdev)
    local imgspace=$(($freespace/100*100 - 1024*100))
    if [ $imgspace -lt $((1024*1024*10)) ];then
        die "need more freespace to create image"
    fi
    if [ -f $img ];then
        rm -f $img      
    fi
    fallocate -l $(($imgspace*1024)) $img
    echo $img
}

load_img_to_dev() {
    local img=$1
    if [ ! -f $img ]; then
        die "disk image does not exist."
    fi
    local loopdev=$(losetup -f)
    losetup $loopdev $img
    echo $loopdev
}

umount_dev() {
    [ ! -b $1 ] && die "device:${1} doesn't exist"
    partx -d $1
    losetup -d $1    
}

get_dualboot_part() {
    cgpt find -l $DUALBOOT_LABEL
}

get_efi_part() {
    cgpt find -t C12A7328-F81F-11D2-BA4B-00A0C93EC93B
}

get_mnt_of_part() {
    local partdev=$1
    [ ! -b $partdev ] && die "device:${1} doesn't exist"
    local mntdir=$(lsblk -o mountpoint -l -n $partdev)
    if [ -z "${mntdir}" ];then
        mntdir=$(mktemp -d -p /tmp ${LOG_MOD}XXXXX)
        mount $partdev $mntdir
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
    local efi_path=`echo ${sys_path//\//\\\}`
    echo ${efi_path}
}

convert_efi_path2() {
    local sys_path=$1
    local efi_path=$(convert_efi_path $sys_path)
    efi_path=`echo $efi_path | sed s/\\\\\\\\/\\\\\\\\\\\\\\\\/g`
    echo ${efi_path}  
}

is_efi_in_boot_entries() {
    local efi_path=$(convert_efi_path2 $1)
    [ -n "$(efibootmgr | grep -i "$efi_path")" ]    
}

get_boot_entry_by_path() {
    local efi_path=$(convert_efi_path2 $1)
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
    local efi_path=$(convert_efi_path2 $1)
    local first_boot=$(get_first_boot_entry)
    [ -n "$(efibootmgr | grep -i "$efi_path" | grep "Boot$first_boot")" ]
}

create_entry() {
    local efi_path=$(convert_efi_path $1)
    local label=$2
    local part_dev=$3
    efibootmgr -c -l "${efi_path}" -L "${label}" -d "$(parse_disk_dev $part_dev)" \
        -p "$(parse_partition_num $part_dev)"        
}

remove_entry() {
    local efi_entry=$(get_boot_entry_by_path $1)
    efibootmgr -b $efi_entry -B
}
