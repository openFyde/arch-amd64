# Copyright (c) 2018 The Fyde OS Authors. All rights reserved.
# Distributed under the terms of the BSD

EAPI="4"

DESCRIPTION="empty project"
HOMEPAGE="http://fydeos.com"

LICENSE="BSD"
SLOT="0"
KEYWORDS="*"
IUSE="+dual_boot"

RDEPEND="
    dual_boot? ( chromeos-base/dual-boot-installer )
    chromeos-base/bring-all-cpus-online
    chromeos-base/fydeos-hardware-tuner
"

DEPEND="${RDEPEND}"
