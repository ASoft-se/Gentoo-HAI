echo To much needing root :\(
set -x
echo emerge -uv1 cdrtools squashfs-tools
modprobe loop
mount -r -o loop,users install-amd64-minimal-*.iso /mnt/cdrom || exit 1
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
cp -av /mnt/cdrom/* gentoo_boot_cd || exit 1
umount /mnt/cdrom || exit 1

cd gentoo_boot_cd || exit 1
#unsquashfs image.squashfs || exit 1
#rm image.squashfs
# mv squashfs-root ~/squashroot


echo do changes...

cp ../gentoo_cdupdate.sh cdupdate.sh
chmod a+x cdupdate.sh
sed -i 's/ontimeout localhost/ontimeout gentoo/' isolinux/isolinux.cfg
sed -i 's/vga=791$/vga=791 keymap=32 autoinstall/' isolinux/isolinux.cfg

mcedit isolinux/isolinux.cfg
bash

#mksquashfs squashfs-root image.squashfs || exit 1
#rm -rf squashfs-root
cd ..
mkisofs -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -iso-level 4 \
 -hide-rr-moved -c isolinux/boot.cat -o install-amd64-mod.iso gentoo_boot_cd || exit 1

rm -rf gentoo_boot_cd

#something else if we use grub...


#from www.gentooo-wiki.info/SSH-ebabled_installation_CD
