#!/bin/bash
DUAL_SCRIPT_DIR="/usr/share/dualboot"
REFIND_DIR="/usr/share/dualboot/refind"
refind_package="$(ls $REFIND_DIR/*.tar.xz)"
refind_package=$(basename $refind_package)
refind_dir=${refind_package%.tar*}
refind_version=${refind_dir##*-}
TMP_DIR="/tmp"
EFI="/EFI"
refind_install="${EFI}/refind"
SELF=$(basename $0)

set -e

. $DUAL_SCRIPT_DIR/fydeos_util.sh

print_version() {
    echo "$SELF version:${VERSION} Copyright By FydeOS"
}

print_usage() {
    print_version
    echo
    echo "Insall rEFInd boot loader ${refind_version} for FydeOS dualboot2"
    echo "Usage: $SELF [-d | --dst <target dev or folder>] [-h | --help]
       Example: 
           $SELF -d /dev/sda1    #partition device as target
           $SELF -d /mnt/sda1    #mount point as target
           $SELF                 #find the ESP partition as target
       "
}

copy_drivers() {
    local source="${1}/refind/drivers_x64"
    local target="${partmnt}${refind_install}/drivers_x64"
    info "copy drivers..."
    create_dir $target
    cp -f ${source}/* $target 
}

copy_tools() {
    local source="${1}/refind/tools_x64"
    local target="${partmnt}${EFI}/tools"
    create_dir $target
    info "copy tools..."
    cp -f ${source}/* $target    
}

install_theme() {
  local source_dir="${REFIND_DIR}/rEFInd-minimal"
  local target_dir="${partmnt}${refind_install}"
  local conf="${target_dir}/refind.conf"
  mkdir -p ${target_dir}/themes
  cp -rf $source_dir ${target_dir}/themes
  echo "include themes/rEFInd-minimal/theme.conf" >> ${conf}
}

copy_refind() {
    local source="${1}/refind"
    local target="${partmnt}${refind_install}"
    create_dir $target
    touch_dir $target
    cp -f $source/refind_x64.efi $target
    cp -rf $source/icons $target
    cp -f $source/refind.conf-sample $target/refind.conf
    cp -f $DUAL_SCRIPT_DIR/BOOT.CSV $target
    copy_tools $1
    copy_drivers $1
}

AddBootEntry() {
    local efi="${EFI}/refind/refind_x64.efi"
    local install=true
    if is_efi_in_boot_entries $efi ; then
        if is_efi_first_boot_entry $efi ; then
            info "The Boot Entry is already exist."
            install=false
        else
            remove_entry $efi
        fi
    fi
    if $install ; then
        local efi_dev=$(rootdev $partmnt)
        info "Create new boot entry."
        create_entry $efi "rEFInd Boot Manager" $efi_dev
    fi
       
}

main() {
    info "Extract rEFInd to tmp..."
    pushd ${TMP_DIR} > /dev/null 2>&1
    tar -xJf ${REFIND_DIR}/$refind_package
    info "install reFind..."
    local refind_source=${TMP_DIR}/${refind_dir}
    copy_refind $refind_source
    install_theme
    AddBootEntry
    info "Done."
}

partmnt=
if [ -z "$refind_version" ]; then
	die "No rEFInd package founded."
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
    local efi_devs=$(get_efi_part)
	if [ $(echo $efi_devs |wc -w) -gt 1 ]; then
        local index=1
		local selected=1
		declare -a efi_arr
        for efi in $efi_devs; do
            echo "($index):${efi}"
			efi_arr[$index]=$efi
            index=$(($index+1))
        done
        printf "Select the EFI partiton:"
		read -n 1 selected
		if [ -z "${efi_arr[$selected]}" ]; then
            die "no efi founded."
        fi
		efi_devs=${efi_arr[$selected]}
    fi
	partmnt=$(get_mnt_of_part $efi_devs)
fi
main 
