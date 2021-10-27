# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=5

inherit toolchain-funcs

DESCRIPTION="User-space application to modify the EFI boot manager"
HOMEPAGE="https://github.com/rhinstaller/efibootmgr"
SRC_URI="https://github.com/rhinstaller/efibootmgr/releases/download/${PV}/${P}.tar.bz2"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="amd64 ~arm64 ~ia64 ~x86"
IUSE=""

RDEPEND="sys-apps/pciutils
	sys-libs/efivar"
DEPEND="${RDEPEND}"

src_prepare() {
	default
	sed -i -e 's/-Werror //' Make.defaults || die
}

src_configure() {
	tc-export CC
	export EFIDIR="Gentoo"
}

src_compile() {
	emake PKG_CONFIG="$(tc-getPKG_CONFIG)" CPPFLAGS="-I${ROOT}/usr/include/efivar -L${ROOT}/usr/include/efivar"  
#  emake PKG_CONFIG="${ROOT}/usr/lib64/pkgconfig" # cflags="${cflags} -L${ROOT}/usr/lib64 -I${ROOT}/usr/include/efivar"
}
