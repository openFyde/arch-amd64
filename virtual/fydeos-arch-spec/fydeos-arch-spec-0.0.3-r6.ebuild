# Copyright (c) 2022 Fyde Innovations Limited and the openFyde Authors.
# Distributed under the license specified in the root directory of this project.

EAPI=7

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
    app-arch/zstd
    chromeos-base/suspend-mode-switch
    chromeos-base/crossystem_mode-switch
"

DEPEND="${RDEPEND}"
