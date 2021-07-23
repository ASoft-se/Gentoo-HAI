#!/bin/bash
DISTMIRROR=http://distfiles.gentoo.org
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-install-amd64-minimal/
FILES=$(wget -q ${DISTBASE} -O - | grep -o -E "\w*-[-0-9A-Za-z\.]*\.(xz|iso)" | sort | uniq)
FILE_MINIMAL_ISO=$(echo ${FILES} | grep -o -e "install-amd64-minimal-\w*.iso")
echo Latest Minimal: $FILE_MINIMAL_ISO
FILE_STAGE3=$(echo ${FILES} | grep -o -E 'stage3-amd64-openrc-20\w*\.tar\.(bz2|xz)')
echo Latest Stage3: $FILE_STAGE3
