EAPI=5

DESCRIPTION="Script to install dual bootable FydeOS along with existing OS."
HOMEPAGE="https://fydeos.com"

SLOT="0"
KEYWORDS="amd64 x86"
LICENSE="GPL-3"

RDEPEND="
	sys-apps/diffutils
	sys-apps/gptfdisk[-ncurses]
	sys-block/parted
"

DEPEND="
	${RDEPEND}
"

S=${WORKDIR}

src_install() {
    local dual_dir=${FILESDIR}/dualboot
	insinto /usr/share/dualboot
	doins -r ${dual_dir}/fydeos
    doins ${dual_dir}/script/*.sh
    doins ${dual_dir}/script/*.override
    doins ${dual-dir}/script/update_manager.conf
    insinto /boot
    doins ${dual_dir}/boot/*
    exeinto /usr/sbin
	doexe ${dual_dir}/script/dual-boot-install
    doexe ${dual_dir}/script/dual-boot-remove
    doexe ${dual_dir}/script/fix_write_gpt
}
