#!/bin/bash

source "${SCRIPTSDIR}/distribution.sh"

# Configure PAM
#
# Enable null passwords for password logins
chroot_cmd /usr/sbin/pam-config --add --unix --unix-nullok

# Install repos for zypper
chroot_cmd /usr/bin/zypper addrepo --refresh http://download.opensuse.org/distribution/leap/${DIST_VER}/repo/oss/ repo-oss
chroot_cmd /usr/bin/zypper addrepo --refresh http://download.opensuse.org/update/leap/${DIST_VER}/oss/ repo-updates
