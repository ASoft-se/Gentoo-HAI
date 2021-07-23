#!/bin/bash
DISTMIRROR=http://distfiles.gentoo.org
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-install-amd64-minimal/
FILE=$(wget -q $DISTBASE -O - | grep -o -e "install-amd64-minimal-\w*.iso" | uniq)

wget -c $DISTBASE$FILE || exit 1
