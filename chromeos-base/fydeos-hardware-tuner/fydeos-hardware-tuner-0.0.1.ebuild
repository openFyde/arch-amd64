# Copyright (c) 2018 The Fyde OS Authors. All rights reserved.
# Distributed under the terms of the BSD

EAPI="5"

EGIT_REPO_URI="git@gitlab.fydeos.xyz:misc/fydeos_hardware_tuning.git"
EGIT_BRANCH="master"

inherit git-r3
DESCRIPTION="Tunning system driver and configrations in console mode"
HOMEPAGE="http://fydeos.com"

LICENSE="BSD-Google"
SLOT="0"
KEYWORDS="*"
IUSE=""

RDEPEND=""

DEPEND="${RDEPEND}"

src_install() {
  insinto /usr/share/hwtuner-script
  doins -r lib
  doins -r menu
  exeinto /usr/share/hwtuner-script
  doexe hwtuner
  dosym /usr/share/hwtuner-script/hwtuner /usr/bin/hwtuner
}
