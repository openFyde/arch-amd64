EAPI=5

inherit git-2

DESCRIPTION="Script to install dual bootable FlintOS along with existing OS."
HOMEPAGE="http://flintos.io"
EGIT_REPO_URI="git@gitlab.fydeos.xyz:pc/dual-boot-pc.git"
EGIT_BRANCH="master"

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

src_install() {
	insinto /usr/share/dual-boot-installer
	doins -r refind-bin-flintos-0.10.8/refind

	dosbin ${FILESDIR}/dual-boot-install.sh
}
