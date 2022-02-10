#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
. $DUAL_SCRIPT_DIR/fydeos_util.sh


print_usage() {
    die "$(basename "$0") command [args...]"
}

if [ $# -lt 1 ]; then
    print_usage
fi
command=$1
shift
$command "$@" 2>&1 | tee -a "$LOG_FILE"
