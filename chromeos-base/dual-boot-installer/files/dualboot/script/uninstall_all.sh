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
  if [ -n "${dualboot_part}" ]; then
    safe_format $dualboot_part
  fi
  info "Done"
}

if [ $# -gt 0 ]; then
  print_usage
  exit 0
fi

main
