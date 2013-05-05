echo To much needing root :\(
set -x
echo emerge -uv1 cdrtools squashfs-tools
modprobe loop
mount -r -o loop,users install-amd64-minimal-*.iso /mnt/cdrom || exit 1
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=1G,nr_inodes=1048576
cp -av /mnt/cdrom/* gentoo_boot_cd || exit 1
umount /mnt/cdrom || exit 1

cd gentoo_boot_cd || exit 1
unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot


echo do changes...
# Try to get rid of the PredictableNetworkInterfaceNames Shit! With it we never know what the nics are called.
echo > squashfs-root/lib64/udev/rules.d/80-net-name-slot.rules

cp ../gentoo_cdupdate.sh cdupdate.sh
chmod a+x cdupdate.sh
sed -i 's/ontimeout localhost/ontimeout gentoo/' isolinux/isolinux.cfg
sed -i 's/vga=791$/vga=791 keymap=32 autoinstall/' isolinux/isolinux.cfg

echo Giving user possibility to modify boot settings
mcedit isolinux/isolinux.cfg
echo -e "\n\tStarting separate shell, just exit if no changes should be done."
echo -e "\n\tWhen exit, the iso will be rebuilt."
bash

mksquashfs squashfs-root image.squashfs || exit 1
rm -rf squashfs-root
cd ..
mkisofs -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -iso-level 4 \
 -hide-rr-moved -c isolinux/boot.cat -o install-amd64-mod.iso gentoo_boot_cd || exit 1

umount gentoo_boot_cd
rm -rf gentoo_boot_cd

#something else if we use grub...


#from www.gentooo-wiki.info/SSH-ebabled_installation_CD
