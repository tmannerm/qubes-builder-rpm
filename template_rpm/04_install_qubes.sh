#!/bin/bash
#
# The Qubes OS Project, http://www.qubes-os.org
#
# Copyright (C) 2015 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
# Copyright (C) 2017 Frédéric Pierret (fepitre) <frederic@invisiblethingslab.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-2.0-or-later

RETCODE=0

# shellcheck source=template_rpm/distribution.sh
source "${TEMPLATE_CONTENT_DIR}/distribution.sh"

RETCODE=0

# Prepare system mount points
prepareChroot

if [ "0${IS_LEGACY_BUILDER}" -eq 1 ]; then
    export YUM0=$PWD/pkgs-for-template
fi
REPO_FILE="${TEMPLATE_CONTENT_DIR}/../repos/qubes-repo-vm-${DIST_NAME}.repo"

cp "${TEMPLATE_CONTENT_DIR}/template-builder-repo-${DIST_NAME}.repo" "${INSTALL_DIR}/etc/yum.repos.d/"
if [ -n "$USE_QUBES_REPO_VERSION" ]; then
    sed -e "s/%QUBESVER%/$USE_QUBES_REPO_VERSION/g" \
        -e "s/\$sysroot//g" \
        < "${REPO_FILE}" \
        > "${INSTALL_DIR}/etc/yum.repos.d/template-qubes-vm.repo"
    if [ -n "$QUBES_MIRROR" ]; then
        sed -i "s#baseurl.*yum.qubes-os.org#baseurl = $QUBES_MIRROR#" "${INSTALL_DIR}/etc/yum.repos.d/template-qubes-vm.repo"
    fi
    keypath="${KEYS_DIR}/qubes-release-${USE_QUBES_REPO_VERSION}-signing-key.asc"
    if [ -r "$keypath" ]; then
        # use stdin to not copy the file into chroot. /dev/stdin
        # symlink doesn't exists there yet
        chroot_cmd rpm --import /proc/self/fd/0 < "$keypath"
        # for DNF to be able to verify metadata too, the file must be copied anyway :/
        cp "$keypath" "${INSTALL_DIR}/etc/pki/rpm-gpg/RPM-GPG-KEY-qubes-${USE_QUBES_REPO_VERSION}-primary"
    fi
    if [ "${DIST_NAME}" = "centos-stream" ]; then
        key_dist=centos
    elif [ "${DIST_NAME}" = "leap" ] || [ "${DIST_NAME}" = "tumbleweed" ]; then
        key_dist=opensuse
    else
        key_dist="${DIST_NAME}"
    fi
    keypath="${KEYS_DIR}/RPM-GPG-KEY-qubes-${USE_QUBES_REPO_VERSION}-${key_dist}"
    if [ -r "$keypath" ]; then
        # use stdin to not copy the file into chroot. /dev/stdin
        # symlink doesn't exists there yet
        chroot_cmd rpm --import /proc/self/fd/0 < "$keypath"
        # for DNF to be able to verify metadata too, the file must be copied anyway :/
        cp "$keypath" "${INSTALL_DIR}/etc/pki/rpm-gpg/"
    fi
    if [ "0$USE_QUBES_REPO_TESTING" -gt 0 ]; then
        yumConfigRepository enable 'qubes-builder-*-current-testing'
    fi
fi

echo "--> Installing RPMs..."
if [ "x$TEMPLATE_FLAVOR" != "x" ]; then
    installPackages "packages_qubes_${TEMPLATE_FLAVOR}.list" || exit 1
else
    installPackages packages_qubes.list || exit 1
fi

chroot_cmd sh -c 'rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-qubes-*'

# WIP: currently limit to Fedora the add_3rd_party_software.sh
if [ "${DIST_NAME}" == "fedora" ]; then
    if [ "$TEMPLATE_FLAVOR" != "minimal" ] && ! elementIn 'no-third-party' "${TEMPLATE_OPTIONS[@]}"; then
        echo "--> Installing 3rd party apps"
        "${TEMPLATE_CONTENT_DIR}/add_3rd_party_software.sh" || exit 1
    fi
fi

# update after adding qubes repos, in case a new version/fork of a package is there
# shellcheck disable=SC2119
yumUpdate

if ! grep -q LANG= "${INSTALL_DIR}/etc/locale.conf" 2>/dev/null; then
    if [ "${DIST_NAME}" == "fedora" ]; then
        echo "LANG=C.UTF-8" >> "${INSTALL_DIR}/etc/locale.conf"
    fi
    if [ "${DIST_NAME}" == "centos-stream" ] || [ "${DIST_NAME}" == "centos" ]; then
        echo "LANG=en_US.UTF-8" >> "${INSTALL_DIR}/etc/locale.conf"
    fi
    if [ "${DIST_NAME}" == "leap" ] || [ "${DIST_NAME}" == "tumbleweed" ]; then
        echo "LANG=en_US.UTF-8" >> "${INSTALL_DIR}/etc/locale.conf"
    fi
fi

if ! containsFlavor "minimal" || containsFlavor "install-kernel" && [ "0$TEMPLATE_ROOT_WITH_PARTITIONS" -eq 1 ]; then
    chroot_cmd mount -t sysfs sys /sys
    chroot_cmd mount -t devtmpfs none /dev
    # find the right loop device, _not_ its partition
    dev=$(df --output=source "${INSTALL_DIR}" | tail -n 1)
    dev=${dev%p?}
    # if root.img have partitions, install kernel and grub there
    if [ "$DIST_NAME" == "opensuse" ]; then
        # on openSUSE, install default kernel
        yumInstall kernel-default || exit 1
    else
        yumInstall kernel || exit 1
    fi
    yumInstall grub2 qubes-kernel-vm-support || exit 1
    if [ -x "${INSTALL_DIR}/usr/sbin/dkms" ]; then
        yumInstall make || exit 1
        for kver in "${INSTALL_DIR}"/lib/modules/*
        do
            kver="$(basename "$kver")"
            yumInstall "kernel-devel-${kver}" || exit 1
            chroot_cmd dkms autoinstall -k "$kver" || exit 1
        done
    fi
    for kver in "${INSTALL_DIR}"/lib/modules/*
    do
        kver="$(basename "$kver")"
        if [ "$DIST_NAME" == "opensuse" ]; then
            # Make sure default initrd file doesn't exist so that the grub2
            # will correctly use the one generated below
            rm -f "${INSTALL_DIR}/boot/initrd-${kver}" || RETCODE=1

            # Check for a corresponding kernel before creating the initramfs
            #
            # This is because on openSUSE, kernel-preempt-devel package is needed for
            # kernel-syms package but that doesn't pull in the actual kernel.
            #
            if [ ! -f "${INSTALL_DIR}/boot/vmlinuz-${kver}" ]; then
                continue
            fi
        fi
        chroot_cmd dracut -f -a "qubes-vm" \
            "/boot/initramfs-${kver}.img" "${kver}" || exit 1
    done
    chroot_cmd grub2-install --target=i386-pc "$dev" || exit 1
    chroot_cmd grub2-mkconfig -o /boot/grub2/grub.cfg || exit 1
    fuser -kMm "${INSTALL_DIR}" || :
    sleep 3
    chroot_cmd umount /sys /dev
fi
if containsFlavor selinux; then
    yumInstall selinux-policy-targeted || exit 1
fi

# Distribution specific steps
buildStep "${0}" "${DIST_CODENAME}"

rm -f "${INSTALL_DIR}/etc/yum.repos.d/template-builder-repo-${DIST_NAME}.repo"
rm -f "${INSTALL_DIR}/etc/yum.repos.d/template-qubes-vm.repo"

exit "$RETCODE"
