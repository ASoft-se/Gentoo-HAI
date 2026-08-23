#!/bin/bash
DISTMIRROR=http://distfiles.gentoo.org
BUILDBASE=${DISTMIRROR}/releases/amd64/autobuilds/
FILE_MINIMAL_ISO=$(curl -sL ${BUILDBASE}latest-install-amd64-minimal.txt | grep -o -E "\w*-[-0-9A-Za-z\.]*\.iso")
echo Latest Minimal: $FILE_MINIMAL_ISO
FILE_STAGE3=$(curl -sL ${BUILDBASE}latest-stage3-amd64-openrc.txt | grep -o -E "\w*-[-0-9A-Za-z\.]*\.tar\.xz")
echo Latest Stage3: $FILE_STAGE3
