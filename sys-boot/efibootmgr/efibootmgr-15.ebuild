# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

inherit toolchain-funcs linux-info

DESCRIPTION="User-space application to modify the EFI boot manager"
HOMEPAGE="https://github.com/rhinstaller/efibootmgr"
SRC_URI="https://github.com/rhinstaller/efibootmgr/releases/download/${PV}/${P}.tar.bz2"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="amd64 ~arm64 ~ia64 x86"
IUSE=""

RDEPEND="sys-apps/pciutils
	>=sys-libs/efivar-25:="
DEPEND="
	${RDEPEND}
	virtual/linux-sources"

pkg_setup() {
	CONFIG_CHECK="EFIVAR_FS"
	check_extra_config
}

src_prepare() {
	default
	sed -i -e s/-Werror// Make.defaults || die
}

src_configure() {
	tc-export CC
	export EFIDIR="Gentoo"
	# Help find efivar.h
	export CPPFLAGS="-I/usr/include/efivar"
}
