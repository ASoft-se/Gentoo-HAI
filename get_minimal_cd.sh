#!/bin/bash
DISTMIRROR=http://distfiles.gentoo.org
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-install-amd64-minimal/
FILE=$(wget -q $DISTBASE -O - | grep -o -e "install-amd64-minimal-\w*.iso" | uniq)

wget -c $DISTBASE$FILE || exit 1
wget -c $DISTBASE$FILE.DIGESTS || exit 2

# https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Media#Linux_based_verification
#wget -O- https://gentoo.org/.well-known/openpgpkey/hu/wtktzo4gyuhzu8a4z5fdj3fgmr1u6tob?l=releng | gpg --import
# slow:
#gpg --keyserver hkps://keys.gentoo.org --recv-keys 0xBB572E0E2D182910

# Download key if missing
gpg --locate-key releng@gentoo.org
# Verify DIGESTS
gpg --verify $FILE.DIGESTS || exit 2

echo "Verifying SHA512 ..."
# grab SHA512 lines and line after, then filter out line that ends with iso
echo "$(grep -A1 SHA512 $FILE.DIGESTS | grep iso$)" | sha512sum -c || exit 2
echo "Verifying BLAKE2 ..."
# grab BLAK2 lines and line after, then filter out line that ends with iso
blake2line=$(grep -A1 BLAKE2 $FILE.DIGESTS | grep iso$)
# remove /var/tmp*.../ part of filename
echo "${blake2line/\/*\//}" | b2sum -c || exit 2
echo " - Awesome! everything looks good."
