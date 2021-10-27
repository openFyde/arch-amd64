# Copyright (c) 2010 The Chromium OS Authors. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

EAPI=7
CROS_WORKON_COMMIT="b2f37be7c25bc83b76f1b7063a4ef38b824dc4ef"
CROS_WORKON_TREE="40c0bf77fe822e8e504d99f2ef90f3e3c5b58084"
CROS_WORKON_PROJECT="chromiumos/third_party/rootdev"
CROS_WORKON_OUTOFTREE_BUILD="1"

inherit toolchain-funcs cros-sanitizers cros-workon

DESCRIPTION="Chrome OS root block device tool/library"
HOMEPAGE="https://chromium.googlesource.com/chromiumos/third_party/rootdev/"
SRC_URI=""

LICENSE="BSD-Google"
KEYWORDS="*"
IUSE="-asan"

src_configure() {
	sanitizers-setup-env
	tc-export CC
	default
}

src_compile() {
	emake OUT="${WORKDIR}"
}

src_test() {
	if ! use x86 && ! use amd64 ; then
		einfo Skipping unit tests on non-x86 platform
	else
		sudo LD_LIBRARY_PATH=${WORKDIR} \
			./rootdev_test.sh "${WORKDIR}/rootdev" || die
	fi
}

src_install() {
	cd "${WORKDIR}"
	dobin rootdev
	dolib.so librootdev.so*
	insinto /usr/include/rootdev
	doins "${S}"/rootdev.h
}

src_prepare() {
  eapply ${FILESDIR}/dual_boot_loopdev0_support.patch  
  default
}
