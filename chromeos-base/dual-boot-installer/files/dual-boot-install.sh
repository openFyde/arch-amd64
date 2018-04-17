#!/bin/bash
# vim: noexpandtab:ts=4:sw=4

# Stop executing the script on error
set -e

#### Print usage help text and exit
print_usage() {
	echo "Usage: $0 -d | --dst <target disk device>

The system must boot in UEFI mode. The target disk must be using GPT partition table, have a EFI system partition, and have at least 8GB of free space.

For the safety of your data, this scrpit NEVER remove any existing partition. You have to make free space for Flin OS by yourself.

On Mac, the Disk Utility tool does not leave spare space on disk when you shrink existing partition, instead they always create an \"Untitled\" partition. You have to remove that \"Untitled\" partition first to release its space."
	exit
}

#### All pre-installation checkes
precheck() {
	precheck_system
	precheck_part_table
	precheck_esp
	precheck_space
}

# Check whether system meets requirement, such as EFI
precheck_system() {
	if [[ ! -d /sys/firmware/efi ]]; then
		echo "This script currently support UEFI system only, your system either does not support UEFI or is not boot in UEFI mode."
		return 1
	fi
}

# Check whether disk parition type meets requirement
precheck_part_table() {
	if [[ -z "$(gdisk -l $target_disk | grep 'GPT: present')" ]]; then
		echo "This script currently supports GPT partitioned disk only."
		return 1
	fi
}

precheck_esp() {
	local espdev=$(find_esp_dev)

	if [[ -z ${espdev} ]]; then
		echo "There is no EFI system partition on disk. To run Flint OS your disk must have one."
		return 1
	else
		local mntpt=$(mktemp -d -p /tmp flintos.XXXXXX)

		if mount $espdev $mntpt; then
			local free=$(findmnt -o avail -b -n $mntpt)
			umount $mntpt

			if [[ $free -lt $(( 20 * 1024 * 1024 )) ]]; then
				echo "EFI system partition $espdev free space is less than 20MB, aborting..."
				return 1
			fi
		else
			echo "Failed to mount EFI system partition $espdev, is it corrupted?"
			return 1
		fi
	fi
}

# Check disk spare space
precheck_space() {
	local free_sector_start=$(sgdisk -F $target_disk)
	local free_sector_end=$(sgdisk -E $target_disk)
	local free_sectors=$(($free_sector_end - $free_sector_start))

	if [[ $free_sectors -lt $(( 8 * 1024 * 1024 * 1024 / 512)) ]]; then
		echo "Disk free space is less than 8GB, abort."
		return 1
	fi
}

#### Print disk information for user review
printcfg() {
	echo -e "Will install Flint OS to disk $target_disk."
	echo -e "Current partitions:\n\n$(fdisk -l $target_disk)\n\n"
}

#### Ask if user would like to proceed
userconfirm() {
	# Ask for confirmation before start to install
	echo "This will install Flint OS to $target_disk."
	echo "No existing partition will be removed, a few new paritions will be created."
	echo -e "\nPlease confirm you are aware of the risks of losing data during the process and have made necessary backup.\n"

	local sure
	read -p "Are you sure to proceed (y/N)? " sure
	if [[ "${sure}" != "y" ]]; then
		echo -e "\nYou have chosed to not install, exiting..."
		return 1
	fi
}

#### All installation tasks
install() {
	install_mkpart
	discover_part_devs
	discover_part_nums
	install_rootfs
	install_stateful
	install_bootmgr
}

# Create partitions
install_mkpart() {
	# Stop CrOS disk mounting daemon first. It may operate on disks in the background thus could
	# interfere with below partition operations. No proof yet, just in case.
	initctl stop cros-disks

	# Below partitions are created in the order as they exist on the
	# real ChromeOS device, except the ESP partition which is already
	# there and usually the 1st one in most cases.
	# Parition numbers are in sequence instead of like in a real ChromeOS
	# device which are out of order.
	local sgdisk_opt="-a 2048"

	echo "Creating partitions on target disk $target_disk"

	# RWFW
	sgdisk $sgdisk_opt -n 0:0:+8M  -t 0:CAB6E88E-ABF3-4102-A07A-D4BB9BE3C1D3 -c 0:RWFW $target_disk
	# KERN-C
	sgdisk $sgdisk_opt -n 0:0:+1   -t 0:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 -c 0:KERN-C $target_disk
	# ROOT-C
	sgdisk $sgdisk_opt -n 0:0:+1   -t 0:3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC -c 0:ROOT-C $target_disk
	# Reserved
	sgdisk $sgdisk_opt -n 0:0:+1   -t 0:2E0A753D-9E48-43B0-8337-B15192CB1B5E -c 0:reserved $target_disk
	# Reserved
	sgdisk $sgdisk_opt -n 0:0:+1   -t 0:2E0A753D-9E48-43B0-8337-B15192CB1B5E -c 0:reserved $target_disk
	# KERN-A
	sgdisk $sgdisk_opt -n 0:0:+16M -t 0:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 -c 0:KERN-A $target_disk
	# KERN-B
	sgdisk $sgdisk_opt -n 0:0:+16M -t 0:FE3A2A5D-4F32-41A7-B725-ACCC3285A309 -c 0:KERN-B $target_disk
	# OEM customization
	sgdisk $sgdisk_opt -n 0:0:+16M -t 0:EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 -c 0:OEM $target_disk
	# ROOT-B
	sgdisk $sgdisk_opt -n 0:0:+$(get_rootfs_sectors) -t 0:3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC -c 0:ROOT-B $target_disk
	# ROOT-A
	sgdisk $sgdisk_opt -n 0:0:+$(get_rootfs_sectors) -t 0:3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC -c 0:ROOT-A $target_disk
	# Stateful
	sgdisk $sgdisk_opt -n 0:0:0 -t 0:EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 -c 0:STATE $target_disk

	# Sleep for a while before re-read partition table.
	# It is suspected that the occasional "device busy thus the kernel is unable to update partition table"
	# error from below partprobe command can be fixed by this workaround. Although no firm proof it doesn't hurt to do so.
	sleep 2

	# Re-read parition table, yeah this is dirty.
	partprobe -s $target_disk || partx -u $target_disk || blockdev --rereadpt $target_disk || /bin/true

	# Re-start the disk mounting daemon
	initctl start cros-disks
}

# Install rootfs to disk
install_rootfs() {
	echo "Installing root filesystem A on $root_a_dev ..."
	dd if=$boot_rootdev of=$root_a_dev bs=1M status=progress
	config_rootfs $root_a_dev

	echo "Installing root filesystem B on $root_b_dev ..."
	dd if=$root_a_dev of=$root_b_dev bs=1M status=progress
}

# Install stateful parition to disk
install_stateful() {
	echo "Formatting stateful partition $state_dev..."

	# umount it first in case it already has a fs and automounted by the running OS
	umount -f $state_dev > /dev/null 2>&1 || true

	mkfs.ext4 -F -F $state_dev

	# Copy over files on stateful partition: dev_image, var_overlay, vmlinuz_hd.vblock
	local source_state=/mnt/stateful_partition
	local target_state=$(mktemp -d -p /tmp flintos.XXXXXX)

	[[ -d ${target_state} ]] || mkdir ${target_state}
	mntpart state ${target_state}

	echo "Copying over necessary files to the new stateful partition..."
	[[ -f ${source_state}/vmlinuz_hd.vblock ]] && cp ${source_state}/vmlinuz_hd.vblock ${target_state}
	[[ -d ${source_state}/dev_image ]] && cp -a ${source_state}/dev_image ${target_state}
	[[ -d ${source_state}/var_overlay ]] && cp -a ${source_state}/var_overlay ${target_state}

	umount ${target_state}
}

# Install rEFInd boot manager
install_bootmgr() {
	# Install rEFInd files and GRUB config file
	local mntpt=$(mktemp -d -p /tmp flintos.XXXXXX)
	if mntpart esp $mntpt; then
		# This dir should have already existed on a dual boot machine, i.e. it
		# should have been created by other OS. But it doesn't hurt to create it again.
		# Note that ESP partion is FAT32 formatted so file names are case insensitive but
		# internally stored all capital.
		mkdir -p $mntpt/efi/boot

		# Copy rEFInd files to the ESP partition, remove existing one first to avoid
		# copying a new flintos/ under existing flintos/.
		rm -rf $mntpt/efi/flintos
		cp -a /usr/share/dual-boot-installer/refind $mntpt/efi/flintos

		# Install refind as default boot manager.
		# If there is a bootx64.efi and is not refind_x64.efi installed by us previously, backup it
		if [[ -f $mntpt/efi/boot/bootx64.efi ]]; then
			cmp -s $mntpt/efi/boot/bootx64.efi $mntpt/efi/flintos/refind_x64.efi \
				|| mv -f $mntpt/efi/boot/bootx64.efi $mntpt/efi/boot/bootx64.efi.backup-by-flintos
		fi
		cp $mntpt/efi/flintos/refind_x64.efi $mntpt/efi/boot/bootx64.efi

		# Install rEFI config file
		generate_refind_cfg > $mntpt/efi/flintos/refind.conf

		# Install GRUB2 and config file
		cp /boot/efi/boot/bootx64.efi $mntpt/efi/boot/grubx64.efi
		# If there is a grub.cfg that is not generated by us previously, backup it
		if [[ -f $mntpt/efi/boot/grub.cfg
			&& ! $(grep -q -s '^# Automatically generated by FlintOS$' $mntpt/efi/boot/grub.cfg) ]]; then
			mv -f $mntpt/efi/boot/grub.cfg $mntpt/efi/boot/grub.cfg.backup-by-flintos
		fi
		generate_grub_cfg > $mntpt/efi/boot/grub.cfg

		# Install A/B kernel files.
		# Although we don't use syslinux to boot, we mimic the CrOS dir structure as much as possible
		# to avoid unnecessary change to other CrOS scripts/programs.
		mkdir -p $mntpt/syslinux
		# Don't copy A/B kernel files as some times the ESP partition could be very small.
		# But left the syslinux dir created as the system update postinst task may expect its existance.
		# cp -L /boot/vmlinuz $mntpt/syslinux/vmlinuz.A
		# cp -L /boot/vmlinuz $mntpt/syslinux/vmlinuz.B

		# Mount efivarfs that efibootmgr requires to run
	#	mount -t efivarfs none /sys/firmware/efi/efivars

		# Remove existing rEFInd boot entry
	#	local existing=$(efibootmgr | sed -n 's/^Boot\([0-9]*\).*rEFInd$/\1/p')
	#	if [[ -n "$existing" ]]; then
	#		echo "Existing rEFInd boot entry found, possibly left from last install. Removing..."

			# There could be multiple entries with the same name...
	#		for e in $existing; do
	#			efibootmgr -B -b $e > /dev/null 2>&1 || /bin/true
	#		done
	#	fi

		# Add rEFInd to UEFI boot entry list
		echo "Installing rEFInd boot manager. If you see error messages similar to 'Could not prepare Boot variable: No space left on device', that probably means your UEFI firmware is buggy. A workaround is to append 'efi_no_storage_paranoia' to kernel command line at boot time."
	#	efibootmgr -c -l "\efi\flintos\refind_x64.efi" -L rEFInd -d $target_disk -p $esp_num

		umount $mntpt

		echo "Boot manager installed successfully."
	else
		echo "Mount ESP partion failed, boot manager not installed."
		return 1
	fi
}

# Setup the rootfs on target disk, including change partition number info and set dual boot flag.
# Since we do dual boot, the partition numbers are no longer the same as standard scheme.
# If we don't modify the system according to the actual layout on disk then OS simply can't boot successfully.
# Parameter: <root partition device>
config_rootfs() {
	case "$1" in
		/dev/*)
			local rootpart=$1
			local mntpt=$(mktemp -d -p /tmp flintos.XXXXXX)

			if mount $rootpart $mntpt; then
				modify_part_num $mntpt
				set_dualboot_flag $mntpt
				umount $mntpt
			else
				echo "Mount root partion failed, root partition $rootpart not modified."
				return 1
			fi
			;;
		*)
			local root=$1

			# For system update postinst the new rootfs is mounted ro
			mount -o remount,rw $root

			modify_part_num $root
			set_dualboot_flag $root
			;;
	esac

}

# Entry point for partition number modification
modify_part_num() {
	local root=$1
	local osv=$(detect_os_version $root)

	case "$osv" in
		55|56)
			echo "Detected Flint OS version ${osv}"
			modify_part_num_gen1 $root
			;;
		59)
			echo "Detected Flint OS version ${osv}"
			modify_part_num_gen2 $root
			;;
		60|61|62|63|64)
			echo "Detected Flint OS version ${osv}"
			modify_part_num_gen3 $root
			;;
		*)
			echo "Not a supported version: ${osv}"
			return 1
			;;
	esac
}

# For CrOS 55 and 56, they are the same.
modify_part_num_gen1() {
	local root=$1

	# CrOS version 55 and 56 store parittion numbers in the file /usr/share/misc/chromeos-common.sh
	echo "Modifing parition numbers in file /usr/share/misc/chromeos-common.sh on rootfs $rootpart"
	sed -e "s/^\([ \t]*PARTITION_NUM_STATE\)=.*$/\1=${state_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_A\)=.*$/\1=${kern_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_B\)=.*$/\1=${kern_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_C\)=.*$/\1=${kern_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_A\)=.*$/\1=${root_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_B\)=.*$/\1=${root_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_C\)=.*$/\1=${root_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_OEM\)=.*$/\1=${oem_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_RWFW\)=.*$/\1=${rwfw_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_EFI_SYSTEM\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/share/misc/chromeos-common.sh
}

# We didn't release any 57/58 based version, so no handler for them.

# For CrOS 59
modify_part_num_gen2() {
	local root=$1

	# CrOS version 59 store parittion numbers in the file /usr/share/misc/chromeos-common.sh,
	# and /usr/sbin/write_gpt.sh
	echo "Modifing parition numbers in file /usr/share/misc/chromeos-common.sh & /usr/sbin/write_gpt.sh on rootfs $rootpart"
	sed -e "s/^\([ \t]*PARTITION_NUM_STATE\)=.*$/\1=${state_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_A\)=.*$/\1=${kern_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_B\)=.*$/\1=${kern_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_C\)=.*$/\1=${kern_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_A\)=.*$/\1=${root_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_B\)=.*$/\1=${root_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_C\)=.*$/\1=${root_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_OEM\)=.*$/\1=${oem_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_RWFW\)=.*$/\1=${rwfw_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_EFI_SYSTEM\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/share/misc/chromeos-common.sh -i $root/usr/sbin/write_gpt.sh

	sed -e "s/^\([ \t]*PARTITION_NUM_1\)=.*$/\1=${state_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_2\)=.*$/\1=${kern_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_4\)=.*$/\1=${kern_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_6\)=.*$/\1=${kern_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_3\)=.*$/\1=${root_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_5\)=.*$/\1=${root_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_7\)=.*$/\1=${root_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_8\)=.*$/\1=${oem_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_11\)=.*$/\1=${rwfw_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_12\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/sbin/write_gpt.sh
}

# For CrOS 60, 61, 62, 63, 64, they are the same
modify_part_num_gen3() {
	local root=$1

	# CrOS version 60 store parittion numbers in the file /usr/share/misc/chromeos-common.sh,
	# and /usr/sbin/write_gpt.sh. But the pattern in chromeos-common.sh is slightly different than 59.
	echo "Modifing parition numbers in file /usr/share/misc/chromeos-common.sh & /usr/sbin/write_gpt.sh on rootfs $rootpart"
	sed -e "s/^\([ \t]*local PARTITION_NUM_EFI_SYSTEM\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/share/misc/chromeos-common.sh

	sed -e "s/^\([ \t]*PARTITION_NUM_STATE\)=.*$/\1=${state_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_A\)=.*$/\1=${kern_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_B\)=.*$/\1=${kern_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_KERN_C\)=.*$/\1=${kern_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_A\)=.*$/\1=${root_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_B\)=.*$/\1=${root_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_ROOT_C\)=.*$/\1=${root_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_OEM\)=.*$/\1=${oem_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_RWFW\)=.*$/\1=${rwfw_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_EFI_SYSTEM\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/sbin/write_gpt.sh

	sed -e "s/^\([ \t]*PARTITION_NUM_1\)=.*$/\1=${state_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_2\)=.*$/\1=${kern_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_4\)=.*$/\1=${kern_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_6\)=.*$/\1=${kern_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_3\)=.*$/\1=${root_a_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_5\)=.*$/\1=${root_b_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_7\)=.*$/\1=${root_c_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_8\)=.*$/\1=${oem_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_11\)=.*$/\1=${rwfw_num}/g" \
		-e "s/^\([ \t]*PARTITION_NUM_12\)=.*$/\1=${esp_num}/g" \
		-i $root/usr/sbin/write_gpt.sh
}

# Set the dualboot flag in /etc/flintos-release file
set_dualboot_flag() {
	local root=$1

	sed -e "s/^FLINTOS_DUALBOOT=.*$/FLINTOS_DUALBOOT=1/" \
		-i $root/etc/flintos-release

	cat <<-EOF >> $root/etc/flintos-release
	DUALBOOT_STATE=${state_num}
	DUALBOOT_KERN_A=${kern_a_num}
	DUALBOOT_KERN_B=${kern_b_num}
	DUALBOOT_KERN_C=${kern_c_num}
	DUALBOOT_ROOT_A=${root_a_num}
	DUALBOOT_ROOT_B=${root_b_num}
	DUALBOOT_ROOT_C=${root_c_num}
	DUALBOOT_OEM=${oem_num}
	DUALBOOT_RWFW=${rwfw_num}
	DUALBOOT_EFI_SYSTEM=${esp_num}
	EOF
}

# Generate content for refind.conf
generate_refind_cfg() {
	cat <<-EOF
	timeout 15

	use_graphics_for osx,linux,grub,windows

	dont_scan_files + /efi/boot/bootx64.efi.backup-by-flintos /efi/boot/grubx64.efi
	dont_scan_volumes KERN-A,KERN-B,KERN-C,ROOT-A,ROOT-B,ROOT-C,RWFW,reserved,OEM,STATE

	menuentry "Flint OS" {
	    icon /efi/flintos/icons/os_flintos.png
	    loader /efi/boot/grubx64.efi
	}
	EOF
}

# Generate content for grub.cfg
generate_grub_cfg() {
	cat <<-EOF
	# Automatically generated by FlintOS
	defaultA=0
	defaultB=1
	gptpriority \$grubdisk ${kern_a_num} prioA
	gptpriority \$grubdisk ${kern_b_num} prioB

	if [ \$prioA -lt \$prioB ]; then
	    set default=\$defaultB
	else
	    set default=\$defaultA
	fi

	set timeout=2

	# NOTE: These magic grub variables are a Chrome OS hack. They are not portable.

	menuentry "local image A" {
	    #linux /syslinux/vmlinuz.A init=/sbin/init boot=local rootwait ro noresume noswap loglevel=7 noinitrd console=  i915.modeset=1 cros_efi cros_debug root=PARTUUID=$(get_part_uuid $root_a_dev)
	    linux (\$grubdisk,gpt$root_a_num)/boot/vmlinuz init=/sbin/init boot=local rootwait ro noresume noswap loglevel=7 noinitrd console=  i915.modeset=1 cros_efi cros_debug root=PARTUUID=$(get_part_uuid $root_a_dev)
	}

	menuentry "local image B" {
	    #linux /syslinux/vmlinuz.B init=/sbin/init boot=local rootwait ro noresume noswap loglevel=7 noinitrd console=  i915.modeset=1 cros_efi cros_debug root=PARTUUID=$(get_part_uuid $root_b_dev)
	    linux (\$grubdisk,gpt$root_b_num)/boot/vmlinuz init=/sbin/init boot=local rootwait ro noresume noswap loglevel=7 noinitrd console=  i915.modeset=1 cros_efi cros_debug root=PARTUUID=$(get_part_uuid $root_b_dev)
	}
	EOF
}

#### Helper functions
# Mount a partition of the target disk(usually a HDD/SSD)
# Args: Part Name, Mount Point
# Part Name: esp, rootA, rootB, state, oem
# Mount Point: a dir
mntpart() {
	local pn=$1
	local mntpt=$2
	local dev=""

	case $pn in
		esp)
			dev=$(find_esp_dev)
			;;
		rootA)
			dev=$(find_part_dev ROOT-A)
			;;
		rootB)
			dev=$(find_part_dev ROOT-B)
			;;
		state)
			dev=$(find_part_dev STATE)
			;;
		oem)
			dev=$(find_part_dev OEM)
			;;
		*)
			echo "mntpart: unsupported parition name: $pn"
			return 1
			;;
	esac

	[[ -d $mntpt ]] || mkdir -p $mntpt
	mount $dev $mntpt
}

# Return the root device name(e.g. /dev/sda3) of current running OS
get_boot_rootdev() {
	rootdev -s
}

# Return the root device size of current running OS, in bytes
get_rootfs_bytes() {
	partx -s -b -g -o size $boot_rootdev
}

# Return the root device size of current running OS, in sectors
get_rootfs_sectors() {
	partx -s -g -o sectors $boot_rootdev
}

# Return the device name (e.g. /dev/sda3) by its name(aka label, such as STATE, ROOT-A)
# Arg: Part Name
find_part_dev() {
	cgpt find -l $1 $target_disk
}

# Return the partition number (e.g. 3 of /dev/sda3) by its name(aka label, such as STATE, ROOT-A)
# Arg: Part Name
find_part_num() {
	cgpt find -n -l $1 $target_disk
}

# Return ESP partition device name on target disk
find_esp_dev() {
	cgpt find -t efi $target_disk
}

# Return ESP partition number on target disk
find_esp_num() {
	cgpt find -n -t efi $target_disk
}

# Discover partition devices on target disk according to actual layout
# It is called after partitions are created on target disk.
discover_part_devs() {
	kern_a_dev=$(find_part_dev KERN-A)
	kern_b_dev=$(find_part_dev KERN-B)
	kern_c_dev=$(find_part_dev KERN-C)
	root_a_dev=$(find_part_dev ROOT-A)
	root_b_dev=$(find_part_dev ROOT-B)
	root_c_dev=$(find_part_dev ROOT-C)
	oem_dev=$(find_part_dev OEM)
	rwfw_dev=$(find_part_dev RWFW)
	state_dev=$(find_part_dev STATE)
	esp_dev=$(find_esp_dev)
}

# Discover partition numbers on target disk according to actual layout
# It is called after partitions are created on target disk.
discover_part_nums() {
	kern_a_num=$(find_part_num KERN-A)
	kern_b_num=$(find_part_num KERN-B)
	kern_c_num=$(find_part_num KERN-C)
	root_a_num=$(find_part_num ROOT-A)
	root_b_num=$(find_part_num ROOT-B)
	root_c_num=$(find_part_num ROOT-C)
	oem_num=$(find_part_num OEM)
	rwfw_num=$(find_part_num RWFW)
	state_num=$(find_part_num STATE)
	esp_num=$(find_esp_num)
}

# Get partition UUID
# Arg: Partition Device
# Return: UUID string
get_part_uuid() {
	partx -g -o uuid $1
}

# Get CrOS major version number of a rootfs
# Parameter: <root fs dir>
# Return: version number string
detect_os_version() {
	local rootdir=$1
	grep CHROMEOS_RELEASE_CHROME_MILESTONE ${rootdir}/etc/lsb-release | cut -d= -f2
}


#### The entry point for dual boot install
dualboot_install() {
	precheck
	printcfg
	userconfirm
	install
	echo "Installation finished successfully."
}

#### The entry point for post install/update rootfs modification
# It will be call after the system is installed by the chromeos-install script, or by the
# update engine after system update.
post_install() {
	source /etc/flintos-release

	case ${FLINTOS_DUALBOOT} in
		1)
			# The system is in dual boot mode, and is booted from the root fs on disk, not USB.
			# In such case, this script is called by the update_engine as post installation task
			# against the new rootfs. It should modify the new root fs accordingly.
			echo "Dual boot install detected, move on to modify new root fs..."
			state_num=${DUALBOOT_STATE}
			kern_a_num=${DUALBOOT_KERN_A}
			kern_b_num=${DUALBOOT_KERN_B}
			kern_c_num=${DUALBOOT_KERN_C}
			root_a_num=${DUALBOOT_ROOT_A}
			root_b_num=${DUALBOOT_ROOT_B}
			root_c_num=${DUALBOOT_ROOT_C}
			oem_num=${DUALBOOT_OEM}
			rwfw_num=${DUALBOOT_RWFW}
			esp_num=${DUALBOOT_EFI_SYSTEM}

			config_rootfs $rootpart
			;;
		*)
			# The FLINTOS_DUALBOOT flag is 0(no dual boot) or anything else(error)
			# There are three cases then,
			#  1. The system is boot from USB
			#  2. The system is in standalone mode, i.e. the CrOS standard installation, and this
			#     script is called by the chromeos-install script as post installation task. It
			#     should do nothing.
			#  3. The system is in standalone mode and this script is called by update engine as
			#     post installation task. It should do nothing.
			echo "Not a dual boot install, no modification required, exiting..."
			return
			;;
	esac
}

#### Global vars
# INSTALL / POSTINSTALL mode
declare mode

# The device name of the target disk
declare target_disk

# The device name of the root partition to modify, for the -r / --root option after system update
declare rootpart

# The device name of each partition on target disk
declare kern_a_dev
declare kern_b_dev
declare kern_c_dev
declare root_a_dev
declare root_b_dev
declare root_c_dev
declare oem_dev
declare rwfw_dev
declare state_dev
declare esp_dev

# The number of each partitions on target disk
declare -i kern_a_num
declare -i kern_b_num
declare -i kern_c_num
declare -i root_a_num
declare -i root_b_num
declare -i root_c_num
declare -i oem_num
declare -i rwfw_num
declare -i state_num
declare -i esp_num

# The rootfs device of current running OS
boot_rootdev=$(get_boot_rootdev)


#### Now it all begins
# Check whether the script is run by root
if [[ $(id -u) -ne 0 ]]; then
	echo "You must be root to run this script."
	exit
fi


[[ $# -le 1 ]] && print_usage
while [[ $# -gt 1 ]]; do
	opt=$1

	case $opt in
		-d | --dst )
			target_disk=$2
			dualboot_install
			shift
			;;
		-r | --root )
			rootpart=$2
			post_install
			shift
			;;
		* )
			print_usage
			;;
	esac

	shift
done
