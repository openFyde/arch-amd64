# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/bash \
	/bin/busybox \
	/bin/sh

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS ?=

# Programs required by netboot installer
NETBOOT_BIN_DEPS= \
	/bin/dd \
	/bin/ip \
	/usr/bin/kmod \
	/bin/udevadm \
	/bin/xxd \
	/sbin/blockdev \
	/sbin/dumpe2fs \
	/sbin/e2fsck \
	/sbin/resize2fs \
	/sbin/sfdisk \
	/usr/bin/coreutils \
	/usr/bin/curl \
	/usr/bin/getopt \
	/usr/bin/jq \
	/usr/bin/lbzip2 \
	/usr/bin/mktemp \
	/usr/bin/openssl \
	/usr/bin/pigz \
	/usr/bin/setterm \
	/usr/bin/uudecode \
	/usr/bin/uuidgen \
	/usr/bin/wget \
	/usr/sbin/flashrom \
	/usr/sbin/fsck.vfat \
	/usr/sbin/htpdate \
	/usr/sbin/partprobe

# ChromeOS specific dependency.
CROS_DEPS=\
	/usr/bin/cgpt \
	/usr/bin/cros_payload \
	/usr/bin/crossystem \
	/usr/bin/futility \
	/usr/sbin/chromeos-install \
	/usr/sbin/ectool \
	/usr/sbin/factory_*.sh \
	/usr/sbin/mosys \
	/usr/sbin/secure_less.sh \
    /usr/bin/efivar \
    /usr/sbin/efibootmgr \
    /usr/sbin/efibootdump \
	/usr/sbin/vpd

# Non-executables.
DATA_DEPS=\
	/root/.pmbr_code \
	/usr/share/misc/chromeos-common.sh \
	/usr/share/misc/shflags \
	/usr/share/misc/storage-info-common.sh

# Directories to be cloned into initramfs.
DATA_DIR_DEPS= \
	/etc/terminfo

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	usr/share/misc \
	mnt/stateful_partition/dev_image/etc \
	newroot \
	stateful \
	usb

SERVER_ADDR		?= 10.0.0.1

RAMFS_BIN_DEPS = \
	$(BIN_DEPS) \
	$(NETBOOT_BIN_DEPS) \
	$(CROS_DEPS) \
	$(EXTRA_BIN_DEPS)

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	mkdir -p $(STAGE)/lib/udev/rules.d
	cp bootstrap.sh $(STAGE)/bin
	cp $(SYSROOT)/lib/udev/rules.d/10-dm.rules $(STAGE)/lib/udev/rules.d
	cp $(SYSROOT)/lib/udev/rules.d/95-dm-notify.rules \
		$(STAGE)/lib/udev/rules.d
	lddtree --verbose --copy-non-elfs --root=$(SYSROOT) \
		--copy-to-tree=$(STAGE) \
		$(DATA_DEPS)
	for data in $(DATA_DIR_DEPS); do \
		cp -r $(SYSROOT)/$${data} $(STAGE)/$${data}; \
	done
	(BOARD=$(BOARD) BUILD_LIBRARY_DIR=$(BUILD_LIBRARY_DIR) bash -c \
		". $(BUILD_LIBRARY_DIR)/disk_layout_util.sh; \
		write_partition_script usb $(STAGE)/bin/write_gpt.sh")
	cp etc/* $(STAGE)/etc/
	chmod 400 $(STAGE)/etc/passwd
	sed -i "s/%BOARD%/$(BOARD)/g;s/%SERVER_ADDR%/$(SERVER_ADDR)/g" \
		$(STAGE)/etc/lsb-factory
	mv $(STAGE)/etc/lsb-factory \
		$(STAGE)/mnt/stateful_partition/dev_image/etc/lsb-factory
	ln -s /mnt/stateful_partition/dev_image/etc/lsb-factory \
		$(STAGE)/etc/lsb-release
	chmod a+x $(STAGE)/init $(STAGE)/etc/udhcpc.script
	for name in lsmod rmmod insmod modinfo modprobe depmod; do \
	 ln -s kmod $(STAGE)/bin/$${name}; \
	done
	ln -s ../init $(STAGE)/bin/init
	./kotree.sh usbnet $(SYSROOT) $(STAGE)
	$(foreach rsrc, \
	 $(wildcard $(SYSROOT)/var/lib/factory/resources/netboot*.tar), \
	 tar -xf $(rsrc) -C $(STAGE) ${\n})
	$(call generate_ramfs)
