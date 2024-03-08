#!/bin/bash
SCRIPT_DIR=$(dirname $0)
INITRD_DIR=$SCRIPT_DIR/initrd
INITRD_TAR="boot"

. $SCRIPT_DIR/fydeos_util.sh

info_to_file() {
  echo $@ > /tmp/update_initrd.log
}

main() {
  if ! is_dualboot; then
    exit 0
  fi
  local dualboot_dev=$(get_dualboot_part)
  [ -z "${dualboot_dev}" ] && exit 0
  local dualboot_mnt=$(get_mnt_of_part $dualboot_dev)
  local src
  local tar
  info_to_file "update initrd to $dualboot_mnt"
  for src_name in $(ls $INITRD_DIR); do
    src="${INITRD_DIR}/$src_name"
    tar="${dualboot_mnt}/${INITRD_TAR}/$src_name"
    if ! cmp_files $src $tar; then
      cp -f $src $tar
      info_to_file "$src_name is updated."
    else
      info_to_file "$src_name is not need update."
    fi
  done
  sync
  umount $dualboot_mnt
}

main $@
