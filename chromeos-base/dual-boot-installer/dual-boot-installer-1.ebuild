EAPI=5
EGIT_REPO_URI="https://gitee.com/openFyde/fydeos-refind-theme.git"
EGIT_BRANCH="master"

inherit git-r3

DESCRIPTION="Script to configure FydeOS to boot alongside existing OS."
HOMEPAGE="https://fydeos.com"

SLOT="0"
KEYWORDS="amd64 x86"
LICENSE="GPL-3"

RDEPEND="
	sys-apps/diffutils
	sys-apps/gptfdisk[-ncurses]
    sys-boot/efibootmgr
	sys-block/parted
"

DEPEND="
	${RDEPEND}
	chromeos-base/chromeos-initramfs
	chromeos-base/chromeos-installer
"
grub_args=(
    -p "/efi/fydeos"
    -c embedded.cfg
    part_gpt test fat ext2 hfs hfsplus normal boot chain loopback gptpriority
    efi_gop configfile linux search echo cat
  )

src_compile() {
  cat ${SYSROOT}/usr/sbin/chromeos-install | \
	   sed -e "s/\/sbin\/blockdev\ --rereadpt/partx\ -a/g" > \
	   chromeos-install.sh
  echo 'configfile $cmdpath/grub.cfg' > embedded.cfg
	grub-mkimage -O x86_64-efi -o bootx64.efi "${grub_args[@]}"    
}

src_install() {
    local dual_dir=${FILESDIR}/dualboot
    insinto /usr/share/dualboot
    doins -r ${dual_dir}/fydeos
    doins -r ${dual_dir}/refind
    doins ${dual_dir}/script/BOOT.CSV

    insinto /usr/share/dualboot/fydeos
    doins bootx64.efi

    exeinto /usr/share/dualboot
    doexe ${dual_dir}/script/*.sh
    doexe chromeos-install.sh

    insinto /usr/share/dualboot/initrd
    doins ${SYSROOT}/var/lib/initramfs/*.xz

    insinto /usr/share/dualboot/refind/rEFInd-minimal
    doins -r icons
    doins *.png
    doins theme.conf
    doins LICENSE
}
