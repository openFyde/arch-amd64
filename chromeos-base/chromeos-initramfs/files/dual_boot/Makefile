# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Dependency list of binary programs.
BIN_DEPS= \
	/bin/busybox \
	/usr/bin/cgpt \
	/usr/bin/crossystem \
	/usr/bin/pv \
	/sbin/blockdev \
	/sbin/dumpe2fs \
	/usr/sbin/partx \
	/usr/sbin/factory_tty.sh

# Extra dependency, should be set by builder configuration.
EXTRA_BIN_DEPS ?=

# Layout of directories to be created in initramfs.
RAMFS_LAYOUT_DIRS=\
	usr/share/misc

include ../common/initramfs.mk

$(RAMFS_BIN): stage_init
	mkdir -p $(STAGE)/lib/udev/rules.d
	cp $(SYSROOT)/lib/udev/rules.d/10-dm.rules $(STAGE)/lib/udev/rules.d
	cp $(SYSROOT)/lib/udev/rules.d/95-dm-notify.rules \
		$(STAGE)/lib/udev/rules.d
	cp bootstrap.sh $(STAGE)/bin
	ln -s ../init $(STAGE)/bin/init
	cp dual_boot_mount.sh $(STAGE)/bin
	$(call generate_ramfs)
