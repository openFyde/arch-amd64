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
	chromeos-base/chromeos-initramfs
	chromeos-base/chromeos-installer
"

S=${WORKDIR}

src_compile() {
    cat ${SYSROOT}/usr/sbin/chromeos-install | \
	   sed -e "s/\/sbin\/blockdev\ --rereadpt/partx\ -a/g" > \
	   chromeos-install.sh
}

src_install() {
    local dual_dir=${FILESDIR}/dualboot
    insinto /usr/share/dualboot
    doins -r ${dual_dir}/fydeos
    doins -r ${dual_dir}/refind
    doins ${dual_dir}/script/BOOT.CSV

    exeinto /usr/share/dualboot
    doexe ${dual_dir}/script/*.sh
    doexe chromeos-install.sh

    insinto /usr/share/dualboot/initrd
    doins ${SYSROOT}/var/lib/initramfs/*.xz
}
