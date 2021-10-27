#!/bin/bash
ACPI_PATCH_DIR=/usr/share/fydeos_acpi
ACPI_PATCH_NODE=/sys/kernel/debug/acpi/custom_method

if [ -a "${ACPI_PATCH_NODE}" ]; then
    for patch in $(ls ${ACPI_PATCH_DIR}/*.aml); do
      echo "patch $patch to $ACPI_PATCH_NODE "
      cat $patch > ${ACPI_PATCH_NODE}
    done
fi
