# Copyright (c) 2022 Fyde Innovations Limited and the openFyde Authors.
# Distributed under the license specified in the root directory of this project.

cros_pre_src_prepare_arch_arm64() {
  eapply -p2 ${ARCH_AMD64_BASHRC_FILESDIR}/001-keep-debug-flag-after-OTA.patch
}
