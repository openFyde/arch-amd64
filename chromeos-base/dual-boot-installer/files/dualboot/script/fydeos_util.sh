#!/bin/bash
FYDEOS_ROOT_LABEL="FYDEOS-ROOT-A"
FYDEOS_STATE_LABEL="FYDEOS-STATE"
LOG_FILE="/tmp/dual_boot.log"
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

create_tmp_gpt_conf() {
    local source_gpt_conf=$1
    local disk=$2
    local root_num=$(find_partition_num_by_label $FYDEOS_ROOT_LABEL $disk)
    local state_num=$(find_partition_num_by_label $FYDEOS_STATE_LABEL $disk)
    local tmp_conf="/tmp/${source_gpt_conf##*/}"
    sed -e "s/^\([ \t]*PARTITION_NUM_STATE\)=.*$/\1=${state_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_ROOT_A\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_ROOT_B\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_ROOT_C\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_OEM\)=.*$/\1=${state_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_1\)=.*$/\1=${state_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_3\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_5\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_7\)=.*$/\1=${root_num}/g" \
        -e "s/^\([ \t]*PARTITION_NUM_8\)=.*$/\1=${state_num}/g" \
        $source_gpt_conf \
        > $tmp_conf
    echo $tmp_conf
}

#find ext4 file system is exist in a partition (like /dev/sda5)
is_ext4_exist() {
    local dev=$1
    dumpe2fs -h $dev >null 2>&1; 
}

flog_init() {
    echo "FydeOS dual boot install log:" > $LOG_FILE
}

flog() {
    echo $@ | tee -a $LOG_FILE
}

die() {
    flog $@
    flog "Error occured, the log file: $LOG_FILE"
    exit 1
}
