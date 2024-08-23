# Copyright (c) 2022 Fyde Innovations Limited and the openFyde Authors.
# Distributed under the license specified in the root directory of this project.

EAPI=7
EGIT_REPO_URI="${OPENFYDE_GIT_HOST_URL}/fydeos-refind-theme.git"
EGIT_BRANCH="main"

inherit git-r3

DESCRIPTION="Script to configure FydeOS to boot alongside existing OS."
HOMEPAGE="https://fydeos.com"

SLOT="0"
KEYWORDS="amd64 x86"
IUSE="fydeos"
LICENSE="GPL-3"

RDEPEND="
	sys-apps/diffutils
	sys-apps/gptfdisk[-ncurses]
	sys-block/parted
  sys-boot/efibootmgr
"

DEPEND="
	${RDEPEND}
	chromeos-base/chromeos-initramfs
	chromeos-base/chromeos-installer
"
grub_args=(
    -c embedded.cfg
    part_gpt test fat ext2 hfs hfsplus normal boot chain loopback gptpriority
    efi_gop configfile linux search echo cat
  )

src_compile() {
  cat ${SYSROOT}/usr/sbin/chromeos-install | \
	   sed -e "s/\/sbin\/blockdev\ --rereadpt/partx\ -a/g" > \
	   chromeos-install.sh
  echo 'configfile $cmdpath/grub.cfg' > embedded.cfg

  if use fydeos; then
	 grub-mkimage -O x86_64-efi -o bootx64.efi -p "/efi/fydeos" "${grub_args[@]}"
  else
     grub-mkimage -O x86_64-efi -o bootx64.efi  -p "/efi/openfyde" "${grub_args[@]}"
  fi
}

src_install() {
    local dual_dir=${FILESDIR}/dualboot
    insinto /usr/share/dualboot

    if use fydeos; then
      doins -r "${dual_dir}/fydeos"
    else
      doins -r "${dual_dir}/openfyde"
    fi

    doins -r ${dual_dir}/refind

    doins ${dual_dir}/script/BOOT.CSV

    if use fydeos; then
      insinto /usr/share/dualboot/fydeos
    else
      insinto /usr/share/dualboot/openfyde
    fi

    doins bootx64.efi

    exeinto /usr/share/dualboot
    doexe ${dual_dir}/script/*.sh
    if use fydeos; then
      newexe ${dual_dir}/script/is_openfyde/fydeos.sh is_openfyde.sh
    else
      newexe ${dual_dir}/script/is_openfyde/openfyde.sh is_openfyde.sh
    fi
    doexe chromeos-install.sh

    insinto /usr/share/dualboot/initrd
    doins ${SYSROOT}/var/lib/initramfs/*.cpio

    insinto /usr/share/dualboot/refind/rEFInd-minimal
    doins -r icons
    doins *.png
    doins theme.conf
    doins LICENSE
}
