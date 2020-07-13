#!/bin/bash

source "${SCRIPTSDIR}/distribution.sh"

# Configure PAM
#
# Enable null passwords for password logins
chroot_cmd /usr/sbin/pam-config --add --unix --unix-nullok