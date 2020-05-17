#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
SELF=$(basename $0)

. $DUAL_SCRIPT_DIR/fydeos_util.sh

print_version() {
    echo "$SELF version:${VERSION} Copyright By FydeOS"
}

print_usage() {
    print_version
    echo
    echo "Uninnsall FydeOS dualboot2"
    echo "Usage: $SELF [-h | --help]
       Example:
           $SELF                 #Uninstall all FydeOS's stuff on disk
       "
}

remove_boot_entry() {
  local efi="/EFI/refind/refind_x64.efi"
  if is_efi_in_boot_entries $efi ; then
    remove_entry $efi
  fi
}

delete_dualboot_loop_dev() {
  mnt="$1"
  losetup | grep "${mnt}/fydeos/fydeos_dual_boot.img" | awk '{print $1}' | while read dev; do
    info "Delete loop device $dev"
    losetup | while read line; do
      local temp_back_file=$(echo $line | awk '{print $6}')
      if [[ "$temp_back_file" = "$dev" ]]; then
        local temp_name=$(echo $line | awk '{print $1}')
        losetup -d "$temp_name"
      fi
    done
    losetup -d "$dev"
  done
  sleep 2
}

kill_dualboot_chrome_install() {
  local re="^[0-9]+$"
  ps -ef | grep "${DUAL_SCRIPT_DIR}/chromeos-install.sh" | grep -v grep | awk '{print $2}' | while read ppid; do
    if [[ $ppid =~ $re ]] ; then
      info "kill chrome-install process $ppid"
      kill "$ppid"
    fi
    ps -ef | grep "$ppid" | grep -v grep | while read line; do
      local p=$(echo "$line" | awk '{print $3}')
      if [[ "$p" = "$ppid" ]]; then
        local pid=$(echo "$line" | awk '{print $2}')
        if [[ $pid =~ $re ]] ; then
          kill "$pid"
        fi
      fi
    done
  done
  sleep 2
}

main() {
  info_init /tmp/uninstall_dualboot.log
  info "Remove FydeOS grub and refind..."
  for efi_part in $(get_efi_part); do
    efi_dir=$(get_mnt_of_part $efi_part)
    for fyde_dir in $(list_touched_dir $efi_dir); do
      if [ -n "$(echo $fyde_dir | grep refind)" ]; then
        remove_boot_entry
      fi
      rm -rf $fyde_dir
    done
  done
  info "Remove FydeOS Dualboot part..."
  dualboot_part=$(get_dualboot_part)
  dualboot_mnt=$(get_mnt_of_part "$dualboot_part")
  if [ -n "${dualboot_part}" ]; then
    kill_dualboot_chrome_install
    delete_dualboot_loop_dev "$dualboot_mnt"
    safe_format $dualboot_part
  fi
  info "Done"
}

if [ $# -gt 0 ]; then
  print_usage
  exit 0
fi

main
