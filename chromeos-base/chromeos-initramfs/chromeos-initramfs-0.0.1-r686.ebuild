# Copyright 2012 The ChromiumOS Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="7"
CROS_WORKON_COMMIT="419612a16c5e8b4848666643a5157577bdf7d465"
CROS_WORKON_TREE="09f4a57f21115d833427ffc19312afd602dc99d1"
CROS_WORKON_PROJECT="chromiumos/platform/initramfs"
CROS_WORKON_LOCALNAME="platform/initramfs"
CROS_WORKON_OUTOFTREE_BUILD="1"

inherit cros-workon cros-board cros-constants

DESCRIPTION="Create Chrome OS initramfs"
HOMEPAGE="https://chromium.googlesource.com/chromiumos/platform/initramfs/"

LICENSE="BSD-Google"
SLOT="0"
KEYWORDS="*"
IUSE="+cros_ec_utils detachable device_tree +interactive_recovery"
IUSE="${IUSE} legacy_firmware_ui -mtd +power_management"
IUSE="${IUSE} unibuild +oobe_config no_factory_flow"
IUSE="${IUSE} nvme ufs"
IUSE="${IUSE} cr50_onboard ti50_onboard tpm"
IUSE="${IUSE} lvm_stateful_partition"
IUSE="${IUSE} fydeos"

# Build Targets
TARGETS_IUSE="
	factory_netboot_ramfs
	factory_shim_ramfs
	recovery_ramfs
	minios_ramfs
	flexor_ramfs
	prod_ramfs
"
TARGETS_IUSE="${TARGETS_IUSE} dual_boot_ramfs core_util_ramfs"

IUSE="${IUSE} test ${TARGETS_IUSE}"
# Allow absence of the build target when running tests via cros_run_unit_tests.
REQUIRED_USE="|| ( test ${TARGETS_IUSE} )"

# Packages required for building recovery initramfs.
RECOVERY_DEPENDS="
	chromeos-base/chromeos-installer
	chromeos-base/common-assets
	chromeos-base/vboot_reference
	chromeos-base/vpd
	sys-apps/flashrom
	sys-apps/pv
	virtual/assets
	virtual/chromeos-regions
	"

MINIOS_DEPENDS="
	app-shells/bash
	chromeos-base/chromeos-installer
	chromeos-base/common-assets
	chromeos-base/factory_installer
	chromeos-base/minijail
	chromeos-base/minios
	chromeos-base/screen-capture-utils
	chromeos-base/update-utils
	chromeos-base/vboot_reference
	chromeos-base/vpd
	dev-util/strace
	net-firewall/iptables
	net-misc/curl
	net-misc/dhcp
	net-misc/dhcpcd-legacy
	net-wireless/wpa_supplicant-cros
	nvme? ( sys-apps/nvme-cli )
	sys-apps/coreutils
	sys-apps/flashrom
	sys-apps/pv
	virtual/assets
	virtual/chromeos-regions
	"

FLEXOR_DEPENDS="
	app-shells/bash
	chromeos-base/chromeos-installer
	chromeos-base/common-assets
	chromeos-base/flexor
"

PROD_DEPENDS="
	app-shells/bash
	sys-apps/rootdev
	sys-apps/coreutils
	sys-apps/util-linux
"

# Packages required for building factory installer shim initramfs.
FACTORY_SHIM_DEPENDS="
	chromeos-base/factory_installer
	chromeos-base/vboot_reference
	"

# Packages required for building factory netboot installer initramfs.
FACTORY_NETBOOT_DEPENDS="
	app-arch/lbzip2
	app-arch/pigz
	app-arch/sharutils
	app-misc/jq
	app-shells/bash
	chromeos-base/chromeos-base
	chromeos-base/chromeos-installer
	chromeos-base/chromeos-installshim
	chromeos-base/chromeos-storage-info
	chromeos-base/dlcservice
	chromeos-base/ec-utils
	chromeos-base/factory_installer
	ufs? ( chromeos-base/factory_ufs )
	chromeos-base/vboot_reference
	chromeos-base/vpd
	dev-libs/openssl:0=
	dev-util/shflags
	dev-util/xxd
	net-misc/curl
	net-misc/htpdate
	net-misc/uftp
	net-misc/wget
	sys-apps/coreutils
	sys-apps/flashmap
	sys-apps/flashrom
	sys-apps/iproute2
	sys-apps/util-linux
	sys-fs/dosfstools
	sys-fs/e2fsprogs
	sys-libs/ncurses
	virtual/udev
	amd64? ( sys-apps/coreboot-utils )
	"

DEPEND="
	!no_factory_flow? (
		factory_netboot_ramfs? ( ${FACTORY_NETBOOT_DEPENDS} )
		factory_shim_ramfs? ( ${FACTORY_SHIM_DEPENDS} )
	)
	recovery_ramfs? ( ${RECOVERY_DEPENDS} )
	minios_ramfs? ( ${MINIOS_DEPENDS} )
	flexor_ramfs? ( ${FLEXOR_DEPENDS} )
	prod_ramfs? ( ${PROD_DEPENDS} )
	sys-apps/busybox[-make-symlinks]
	sys-fs/lvm2
	chromeos-base/chromeos-init
	sys-apps/frecon-lite
	power_management? ( chromeos-base/power_manager )
	unibuild? ( chromeos-base/chromeos-config )
	chromeos-base/chromeos-config-tools
"

FYDEOS_DEPENDS="
       app-arch/lbzip2
       app-arch/pigz
       app-arch/sharutils
       app-misc/jq
       app-shells/bash
       chromeos-base/chromeos-base
       chromeos-base/chromeos-installer
       chromeos-base/chromeos-storage-info
       chromeos-base/ec-utils
       chromeos-base/factory_installer
       chromeos-base/vboot_reference
       chromeos-base/vpd
       dev-libs/openssl
       dev-util/shflags
       dev-util/xxd
       net-misc/curl
       net-misc/htpdate
       net-misc/wget
       sys-apps/coreutils
       sys-apps/flashrom
       sys-apps/iproute2
       sys-apps/mosys
       sys-apps/util-linux
       sys-block/parted
       sys-fs/dosfstools
       sys-fs/e2fsprogs
       sys-libs/ncurses
       sys-libs/efivar
       sys-boot/efibootmgr
       sys-apps/pv
       app-shells/dash
       "
DEPEND="${DEPEND}
       dual_boot_ramfs? ( ${FYDEOS_DEPENDS} )
       core_util_ramfs? ( ${FYDEOS_DEPENDS} sys-apps/frecon-lite virtual/udev )
  "

RDEPEND=""

src_prepare() {
	export BUILD_LIBRARY_DIR="${CHROOT_SOURCE_ROOT}/src/scripts/build_library"
	export INTERACTIVE_COMPLETE="$(usex interactive_recovery true false)"

	# Need the lddtree from the chromite dir.
	export PATH="${CHROMITE_BIN_DIR}:${PATH}"

	eapply_user
}

src_compile() {
	local deps=()
	use mtd && deps+=(/usr/bin/cgpt)
	if use factory_netboot_ramfs; then
		if ! use no_factory_flow; then
			use power_management && deps+=(/usr/bin/backlight_tool)
		fi
	fi

	local targets=()
	for target in ${TARGETS_IUSE}; do
		use "${target}" && targets+=("${target%_ramfs}")
	done
	einfo "Building targets: ${targets[*]:-(only running tests)}"

	if [[ ${#targets[@]} -gt 0 ]]; then
		local tpm_type="default"
		if use cr50_onboard || use ti50_onboard; then
			tpm_type="cros"
		elif use tpm; then
			tpm_type="infineon"
		fi
		emake SYSROOT="${SYSROOT}" \
			BOARD="$(get_current_board_with_variant)" \
			DETACHABLE="$(usex detachable 1 0)" \
			INCLUDE_ECTOOL="$(usex cros_ec_utils 1 0)" \
			INCLUDE_FACTORY_UFS="$(usex ufs 1 0)" \
			FACTORY_TPM_SCRIPT="${tpm_type}" \
			INCLUDE_IFDTOOL="$(usex amd64 1 0)" \
			INCLUDE_FIT_PICKER="$(usex device_tree 1 0)" \
			INCLUDE_NVME_CLI="$(usex nvme 1 0)" \
			LEGACY_UI="$(usex legacy_firmware_ui 1 0)" \
			LIBDIR="$(get_libdir)" \
			LVM_STATEFUL="$(usex lvm_stateful_partition 1 0)" \
			LOCALE_LIST="${RECOVERY_LOCALES:-}" \
			OOBE_CONFIG="$(usex oobe_config 1 0)" \
			OUTPUT_DIR="${WORKDIR}" EXTRA_BIN_DEPS="${deps[*]}" \
			UNIBUILD="$(usex unibuild 1 0)" \
			"${targets[@]}"
	fi
}

src_test() {
	local targets=()
	for target in ${TARGETS_IUSE}; do
		use "${target}" && targets+=("${target%_ramfs}_check")
	done
	einfo "Testing targets: ${targets[*]}"

	if [[ ${#targets[@]} -gt 0 ]]; then
		emake SYSROOT="${SYSROOT}" "${targets[@]}"
	fi
}

src_install() {
	insinto /var/lib/initramfs
	for target in ${TARGETS_IUSE}; do
		use "${target}" &&
			doins "${WORKDIR}/${target}.cpio"
	done
}
