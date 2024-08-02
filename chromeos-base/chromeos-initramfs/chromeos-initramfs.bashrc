cros_post_src_prepare_dualboot() {
  if [ ${PV} == "9999" ]; then
    return
  fi
	cp -r ${ARCH_AMD64_BASHRC_FILESDIR}/* ${S}
  if use fydeos; then
		cp "${S}/dual_boot/fydeos_dual_boot_mount.sh" "${S}/dual_boot/dual_boot_mount.sh"
  else
		cp "${S}/dual_boot/openfyde_dual_boot_mount.sh" "${S}/dual_boot/dual_boot_mount.sh"
	fi
	eapply ${ARCH_AMD64_BASHRC_FILESDIR}/factory_shim.patch
}
