#!/bin/busybox sh
# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# To bootstrap the factory installer on rootfs. This file must be executed as
# PID=1 (exec).
# Note that this script uses the busybox shell (not bash, not dash).
set -x

. /usr/sbin/factory_tty.sh
. /bin/dual_boot_mount.sh

NEWROOT_MNT=/newroot

LOG_DEV=
LOG_DIR=/log
LOG_FILE=${LOG_DIR}/dualboot_initramfs.log

# Special file systems required in addition to the root file system.
BASE_MOUNTS="/sys /proc /dev"
TRANSPORT=

# To be updated to keep logging after move_mounts.
TAIL_PID=

# Print message on both main TTY and log file.
info() {
  echo "$@" | tee -a "${TTY}" "${LOG_FILE}"
}

is_cros_debug() {
  grep -qw cros_debug /proc/cmdline 2>/dev/null
}

invoke_terminal() {
  local tty="$1"
  local title="$2"
  shift
  shift
  # Copied from factory_installer/factory_shim_service.sh.
  echo "${title}" >>${tty}
  setsid sh -c "exec script -afqc '$*' /dev/null <${tty} >>${tty} 2>&1 &"
}

enable_debug_console() {
  local tty="$1"
  if ! is_cros_debug; then
    info "To debug, add [cros_debug] to your kernel command line."
  elif [ "${tty}" = /dev/null ] || ! tty_is_valid "${tty}"; then
    # User probably can't see this, but we don't have better way.
    info "Please set a valid [console=XXX] in kernel command line."
  else
    info -e '\033[1;33m[cros_debug] enabled on '${tty}'.\033[m'
    invoke_terminal "${tty}" "[Bootstrap Debug Console]" "/bin/busybox sh"
  fi
}

on_error() {
  trap - EXIT
  info -e '\033[1;31m'
  info "ERROR: Factory installation aborted."
  save_log_files
  enable_debug_console "${TTY}"
  sleep 1d
  exit 1
}

strip_partition() {
  local dev="${1%[0-9]*}"
  # handle mmcblk0p case as well
  echo "${dev%p*}"
}

# Saves log files stored in LOG_DIR in addition to demsg to the device specified
# (/ of stateful mount if none specified).
save_log_files() {
  # The recovery stateful is usually too small for ext3.
  # TODO(wad) We could also just write the data raw if needed.
  #           Should this also try to save
  local log_dev="${1:-$LOG_DEV}"
  [ -z "$log_dev" ] && return 0

  info "Dumping dmesg to $LOG_DIR"
  dmesg >"$LOG_DIR"/dmesg

  local err=0
  local save_mnt=/save_mnt
  local save_dir_name="dual_boot_logs"
  local save_dir="${save_mnt}/${save_dir_name}"

  info "Saving log files from: $LOG_DIR -> $log_dev $(basename ${save_dir})"
  mkdir -p "${save_mnt}"
  mount -n -o sync,rw "${log_dev}" "${save_mnt}" || err=$?
  [ ${err} -ne 0 ] || rm -rf "${save_dir}" || err=$?
  [ ${err} -ne 0 ] || cp -r "${LOG_DIR}" "${save_dir}" || err=$?
  # Attempt umount, even if there was an error to avoid leaking the mount.
  umount -n "${save_mnt}" || err=1

  if [ ${err} -eq 0 ] ; then
    info "Successfully saved the log file."
    info ""
    info "Please remove the USB media, insert into a Linux machine,"
    info "mount the first partition, and find the logs in directory:"
    info "  ${save_dir_name}"
  else
    info "Failures seen trying to save log file."
  fi
}

stop_log_file() {
  # Drop logging
  exec >"${TTY}" 2>&1
  [ -n "$TAIL_PID" ] && kill $TAIL_PID
}

# Extract and export kernel arguments
export_args() {
  # We trust our kernel command line explicitly.
  local arg=
  local key=
  local val=
  local acceptable_set='[A-Za-z0-9]_'
  info "Exporting kernel arguments..."
  for arg in "$@"; do
    key=$(echo "${arg%%=*}" | tr 'a-z' 'A-Z' | \
                   tr -dc "$acceptable_set" '_')
    val="${arg#*=}"
    export "KERN_ARG_$key"="$val"
    info -n " KERN_ARG_$key=$val,"
  done
  info ""
}

move_mounts() {
  info "Moving $BASE_MOUNTS to $NEWROOT_MNT"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mount -n -o move "$mnt" "$NEWROOT_MNT$mnt"
  done

  # Adjust /dev files.
  TTY="${NEWROOT_MNT}${TTY}"
  LOG_TTY="${NEWROOT_MNT}${LOG_TTY}"
  [ -z "${LOG_DEV}" ] || LOG_DEV="${NEWROOT_MNT}${LOG_DEV}"

}

use_new_root() {
  move_mounts
  
  # Chroot into newroot, erase the contents of the old /, and exec real init.
  info "About to switch root... Check VT2/3/4 if you stuck for a long time."
  info "switch root:${NEWROOT_MNT}, arg: $@"
  stop_log_file

  # If you have problem getting console after switch_root, try to debug by:
  #  1. Try a simple shell.
  #     exec <"${TTY}" >"${TTY}" 2>&1
  #     exec switch_root "${NEWROOT_MNT}" /bin/sh
  #  2. Try to invoke factory installer directly
  #     exec switch_root "${NEWROOT_MNT}" /usr/sbin/factory_shim_service.sh

  ###` -v prints upstart info in kmsg (available in INFO_TTY).

  exec switch_root "${NEWROOT_MNT}" /sbin/init "$@" 
}

check_ota_and_update() {
    info "Check OTA kernel state..."
    local origin_root=$1
    local loopdev_root=$2
    if [ "$(get_release_version_from_lsb $loopdev_root)" != \
         "$(get_release_version_from_kernel $origin_root)" ];then
         invoke_terminal "${TTY}" "[Dual Boot Kernel Update]" "/bin/busybox sh"
         info "New OTA kernel detected, update..."
         update_kernel $origin_root $loopdev_root
         blockdev --flushbufs $(get_dualboot_dev)
         info "Kernel updated, reboot..."
         reboot -f -d 1
         info "If your PC doesn't reboot, please reboot manually."
         sleep 1d
         exit 1
    else
       info "Check done."
    fi
}

main() {
  # Setup environment.
  tty_init
  if [ -z "${LOG_TTY}" ]; then
    LOG_TTY=/dev/null
  fi

  mkdir -p "${LOG_DIR}" "${NEWROOT_MNT}"

  exec >"${LOG_FILE}" 2>&1
  info "...:::||| Bootstrapping FydeOS DualBoot |||:::..."
  info "TTY: ${TTY}, LOG: ${LOG_TTY}, INFO: ${INFO_TTY}, DEBUG: ${DEBUG_TTY}"

  # Send all verbose output to debug TTY.
  (tail -f "${LOG_FILE}" >"${LOG_TTY}") &
  TAIL_PID="$!"

  # Export the kernel command line as a parsed blob prepending KERN_ARG_ to each
  # argument.
  export_args $(cat /proc/cmdline | sed -e 's/"[^"]*"/DROPPED/g')

  if [ -n "${INFO_TTY}" -a -e /dev/kmsg ]; then
    info "Kernel messages available in ${INFO_TTY}."
    cat /dev/kmsg >>"${INFO_TTY}" &
  fi

  # DEBUG_TTY may be not available, but we don't have better choices on headless
  # devices.
  enable_debug_console "${DEBUG_TTY}"

  info "Bootstrapping dual boot overlay."
  
  #switch to new root directory which is offered by overlayfs
  local loopdev_root=$(mount_image ${NEWROOT_MNT})

  check_ota_and_update $NEWROOT_MNT $loopdev_root
  # Kill all running terminals. Comment this line if you need to keep debug
  # console open for debugging.
  killall frecon ||true
  killall udevd || true
  NEWROOT_MNT=$loopdev_root 
  # Switch to the new root.
  use_new_root "$@"
  # Should never reach here.
  return 1
}

trap on_error EXIT
set -e
main "$@"
