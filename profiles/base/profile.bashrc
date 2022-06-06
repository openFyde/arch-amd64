arch_amd64_stack_bashrc() {
  local cfg cfgd

  cfgd="/mnt/host/source/src/overlays/arch-amd64/${CATEGORY}/${PN}"
  for cfg in ${PN} ${P} ${PF} ; do
    cfg="${cfgd}/${cfg}.bashrc"
    [[ -f ${cfg} ]] && . "${cfg}"
  done

  export ARCH_AMD64_BASHRC_FILESDIR="${cfgd}/files"
}

arch_amd64_stack_bashrc
