#!/bin/bash
# check for iso before asking for root
srciso=install-amd64-minimal-*.iso
for f in $srciso; do
  if [[ ! -e "$f" ]]; then
    echo "Matching minimal iso not found:"
    echo "   $f"
    echo " please run get_minimal_cd.sh to fetch latest version"
    exit 1
  fi
  srciso=$f
done
echo will be using $srciso as source

ALLPOSITIONAL=()
POSITIONAL=()
KEYMAP=se
while (($#)); do
  ALLPOSITIONAL+=("$1") # save it in an array for later
  case $1 in
  auto)
    AUTO=YES
  ;;
  --keymap)
    KEYMAP=$2
    shift
  ;;
  setupdonehalt)
    SETUPDONEHALT=YES
  ;;
  *)
    # unknown arguments are passed thru
    POSITIONAL+=("$1") # save it in an array for later
  ;;
esac
shift
done
set -- "${POSITIONAL[@]}" # restore positional parameters
ALLPOSITIONAL=${ALLPOSITIONAL[@]}

# check for root since we are using tmpfs and need root to not risk getting incorrect permissions on the new squashfs
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root, please provide password to su" 1>&2
  su -c "sh $0 ${ALLPOSITIONAL}" && [ "$AUTO" == "YES" ] && (rm kvm_lxgentootest.qcow2; sh test_w_qemu.sh -cdrom install-amd64-mod.iso $*)
  exit
fi
# files that contains kernelcmdlines that should be patched
bootmenufiles="isolinux/isolinux.cfg boot/grub/grub-512.cfg"
echo emerge -uv1 cdrtools squashfs-tools
set -x
# unmount in case we got something left over since before
[ -d gentoo_boot_cd ] && umount gentoo_boot_cd
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=2G,nr_inodes=1048576
cd gentoo_boot_cd || exit 1
# 7z x is broken in version 16.02, it does work with 9.20
# use isoinfo extraction from cdrtools instead
isoinfo -R -i ../$srciso -X || exit 1
[ -d "[BOOT]" ] && rm -rf "[BOOT]"

unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot

# we will rebuild the efimg
rm gentoo.efimg
mv gentoo.efimg.mountPoint boot
rm boot/gentoo.igz boot/gentoo
mkdir boot
# copy files from our cd source
cp -rv ../cdsource/* .

echo make changes...
# Try to get rid of the PredictableNetworkInterfaceNames unpredicatability With it we never know what the nics are called.
mkdir -p squashfs-root/lib64/udev/rules.d
echo > squashfs-root/lib64/udev/rules.d/80-net-name-slot.rules
echo > squashfs-root/lib64/udev/rules.d/80-net-setup-link.rules

cat ../gentoo_cd_bashrc_addon >> squashfs-root/root/.bashrc
# Change the default of ISOLINUX config to gentoo cd instead of local boot
sed -i 's/ontimeout localhost/ontimeout gentoo/' isolinux/isolinux.cfg
# remove do keymap
sed -i 's/ dokeymap / /' $bootmenufiles
# default to swedish keyboard and add autoinstall TODO make it settable
sed -i "s/vga=791\$/vga=791 keymap=${KEYMAP} autoinstall/" $bootmenufiles

if [ "$AUTO" == "YES" ]; then
  echo running with auto - wont stop
  [[ "$SETUPDONEHALT" == "YES" ]] && sed -i 's/ autoinstall$/ autoinstall setupdonehalt/' $bootmenufiles
  cp ../install.sh g-install.sh
else
  echo Giving user possibility to modify boot settings - if you dont want this add auto to the $0 commandline
  nano isolinux/isolinux.cfg
# TODO color ths to make it readable
echo -e "\n\tStarting separate shell, just exit if no changes should be done.\n\n\tWhen exit, the iso will be rebuilt."
bash
fi

mksquashfs squashfs-root image.squashfs || exit 1
rm -rf squashfs-root
#/usr/sbin/mkfs.vfat -v -C install-amd64-mod.usb $(( ($(stat -c %s install-amd64-mod.iso) / 1024 + 511) / 32 * 32 ))
# rebuild efimg https://gitweb.gentoo.org/proj/catalyst.git/tree/targets/support/create-iso.sh#n256
clst_target_path=.
	    if [ ! -e "${clst_target_path}/gentoo.efimg" ]
	    then
		iaSizeTemp=$(du -sk "${clst_target_path}/boot" 2>/dev/null)
		iaSizeB=$(echo ${iaSizeTemp} | cut '-d ' -f1)
		iaSize=$((${iaSizeB}+32+32)) # Add slack

		dd if=/dev/zero of="${clst_target_path}/gentoo.efimg" bs=1k \
		    count=${iaSize}
		mkfs.vfat -F 16 -n GENTOO "${clst_target_path}/gentoo.efimg"

		mkdir "${clst_target_path}/gentoo.efimg.mountPoint"
		mount -t vfat -o loop "${clst_target_path}/gentoo.efimg" \
		    "${clst_target_path}/gentoo.efimg.mountPoint"

		echo "Populating EFI image"
		cp -rv "${clst_target_path}"/boot/* \
		    "${clst_target_path}/gentoo.efimg.mountPoint"

		umount "${clst_target_path}/gentoo.efimg.mountPoint"
		rmdir "${clst_target_path}/gentoo.efimg.mountPoint"
		if [ ! -e "${clst_target_path}/boot/grub/stage2_eltorito" ]
		then
		    echo "Removing /boot"
		    rm -rf "${clst_target_path}/boot"
		fi
	    else
		echo "Found populated EFI image at \
		    ${clst_target_path}/gentoo.efimg"
	    fi

cd ..
echo "Creating ISO using both ISOLINUX and EFI bootloader"
mkisofs -J -R -l -V "Gentoo-HAI" -o install-amd64-mod.iso \
 -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
 -eltorito-alt-boot -b gentoo.efimg -c boot.cat -no-emul-boot -z gentoo_boot_cd/

umount gentoo_boot_cd
rm -rf gentoo_boot_cd
