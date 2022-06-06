# Copyright (c) 2022 Fyde Innovations Limited and the openFyde Authors.
# Distributed under the license specified in the root directory of this project.

cros_pre_src_prepare_arch_amd64_patches() {
  eapply ${ARCH_AMD64_BASHRC_FILESDIR}/dual_boot_loopdev0_support.patch  
}
