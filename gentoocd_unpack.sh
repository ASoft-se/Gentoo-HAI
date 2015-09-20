#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root, please provide password to su" 1>&2
  su -c "sh $0 $*" && [ "$1" == "auto" ] && rm kvm_lxgentootest.img && sh test_w_qemu.sh -cdrom install-amd64-mod.iso
  exit
fi
echo emerge -uv1 p7zip cdrtools squashfs-tools
set -x
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=2G,nr_inodes=1048576
cd gentoo_boot_cd || exit 1
# BUG error if there is multiple matching filenames
7z x ../install-amd64-minimal-*.iso || exit 1
rm -rf "[BOOT]/Bootable_NoEmulation.img"

unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot


echo do changes...
# Try to get rid of the PredictableNetworkInterfaceNames unpredicatability With it we never know what the nics are called.
echo > squashfs-root/lib64/udev/rules.d/80-net-name-slot.rules
echo > squashfs-root/lib64/udev/rules.d/80-net-setup-link.rules

cp ../gentoo_cdupdate.sh cdupdate.sh
chmod a+x cdupdate.sh
# Change the default to gentoo cd instead of local boot
sed -i 's/ontimeout localhost/ontimeout gentoo/' isolinux/isolinux.cfg
# remove do keymap
sed -i 's/ dokeymap / /' isolinux/isolinux.cfg
# default to swedish keyboard and add autoinstall TODO make it settable
sed -i 's/vga=791$/vga=791 keymap=se autoinstall/' isolinux/isolinux.cfg

if [ "$1" == "auto" ]; then
  echo running with auto - wont stop
  cp ../install.sh g-install.sh
else
  echo Giving user possibility to modify boot settings - if you dont want this add auto to the $0 commandline
mcedit isolinux/isolinux.cfg
# TODO color ths to make it readable
echo -e "\n\tStarting separate shell, just exit if no changes should be done.\n\n\tWhen exit, the iso will be rebuilt."
bash
fi

mksquashfs squashfs-root image.squashfs || exit 1
rm -rf squashfs-root
cd ..
mkisofs -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -iso-level 4 \
 -hide-rr-moved -c isolinux/boot.cat -o install-amd64-mod.iso gentoo_boot_cd || exit 1

umount gentoo_boot_cd
rm -rf gentoo_boot_cd

#something else if we use grub...

#from www.gentooo-wiki.info/SSH-ebabled_installation_CD
