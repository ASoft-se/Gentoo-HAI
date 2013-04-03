
DISCDATE=$(wget -q http://distfiles.gentoo.org/releases/amd64/current-iso/default/ -O - | grep -o -E "[0-9]{8}" | uniq)
FILE=$(wget -q http://distfiles.gentoo.org/releases/amd64/current-iso/default/$DISCDATE/ -O - | grep -o -e "install-amd64-minimal-\w*.iso" | uniq)

wget http://distfiles.gentoo.org/releases/amd64/current-iso/default/$DISCDATE/$FILE || exit 1
