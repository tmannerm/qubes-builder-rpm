#!/bin/bash -e
# vim: set ts=4 sw=4 sts=4 et :

source "${SCRIPTSDIR}/distribution.sh"

export YUM_OPTS
${SCRIPTSDIR}/../prepare-chroot-base "${INSTALLDIR}" "${DIST}"

cp "${SCRIPTSDIR}/resolv.conf" "${INSTALLDIR}/etc/"
chmod 644 "${INSTALLDIR}/etc/resolv.conf"

# TODO OpenSUSE has a 'network' directory.
if [ "$DISTRIBUTION" != "opensuse" ]; then
    cp "${SCRIPTSDIR}/network" "${INSTALLDIR}/etc/sysconfig/"
    chmod 644 "${INSTALLDIR}/etc/sysconfig/network"
fi

cp -a /dev/null /dev/zero /dev/random /dev/urandom "${INSTALLDIR}/dev/"

yumInstall $YUM
