#!/bin/bash
FILE=$(wget -q http://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/ -O - | grep -o -e "install-amd64-minimal-\w*.iso" | uniq)

wget -c http://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/$FILE || exit 1
