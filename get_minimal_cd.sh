#!/bin/bash
FILE=$(wget -q http://distfiles.gentoo.org/releases/amd64/current-iso/ -O - | grep -o -e "install-amd64-minimal-\w*.iso" | uniq)

wget http://distfiles.gentoo.org/releases/amd64/current-iso/$FILE || exit 1
