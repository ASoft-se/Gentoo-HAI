#!/bin/bash
DISTMIRROR=http://distfiles.gentoo.org
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-install-amd64-minimal/
FILES=$(wget -q ${DISTBASE} -O - | grep -o -E "\w*-[-0-9A-Za-z\.]*\.iso" | sort -r | head -1)
FILE_MINIMAL_ISO=$(echo ${FILES} | grep -o -e "install-amd64-minimal-\w*.iso")
echo Latest Minimal: $FILE_MINIMAL_ISO
STAGEBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-stage3-amd64-openrc/
FILE_STAGE3=$(wget -q ${STAGEBASE} -O - | grep -o -E "stage3-amd64-openrc-\w*\.tar\.xz" | sort -r | head -1)
echo Latest Stage3: $FILE_STAGE3
