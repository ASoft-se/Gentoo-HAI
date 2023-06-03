#!/bin/bash
# Needed packages for grub-mkrescue emerge -uv1 sys-fs/mtools dev-libs/libisoburn app-cdr/cdrtools
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
DOSQUASH=0
KEYMAP=us
while (($#)); do
  ALLPOSITIONAL+=("$1") # save it in an array for later
  case $1 in
  auto)
    AUTO=YES
    POSITIONAL+=("$1") # save it in an array for later
  ;;
  dosquash)
    DOSQUASH=1
  ;;
  --keymap)
    # value for livecd env from https://github.com/gentoo/genkernel/blob/master/defaults/keymaps/keymapList
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
POSITIONAL=${POSITIONAL[@]}

# check for root since we are using tmpfs and need root to not risk getting incorrect permissions on the new squashfs
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (to mount tmpfs), please provide password to su" 1>&2
  su -c "sh $0 ${ALLPOSITIONAL}" && [ "$AUTO" == "YES" ] && (rm kvm_lxgentootest.qcow2; sh test_w_qemu.sh -cdrom install-amd64-mod.iso ${POSITIONAL})
  exit
fi
# files that contains kernelcmdlines that should be patched
bootmenufiles="boot/grub/grub.cfg"
echo emerge -uv1 cdrtools squashfs-tools
set -x
# unmount in case we got something left over since before
[ -d gentoo_boot_cd ] && umount gentoo_boot_cd
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=3G,nr_inodes=1048576
pushd gentoo_boot_cd || exit 1
# 7z x is broken in version 16.02, it does work with 9.20
# use isoinfo extraction from cdrtools instead
isoinfo -R -i ../$srciso -X || exit 1

if [ $DOSQUASH == 1 ]; then
unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot

echo make changes...
# use net.ifnames=0 instead
# Try to get rid of the PredictableNetworkInterfaceNames unpredicatability With it we never know what the nics are called.
mkdir -p squashfs-root/lib/udev/rules.d
echo > squashfs-root/lib/udev/rules.d/80-net-name-slot.rules
echo > squashfs-root/lib/udev/rules.d/80-net-setup-link.rules

cat ../cdhelpers/gentoo_cd_bashrc_addon >> squashfs-root/root/.bashrc
mksquashfs squashfs-root image.squashfs || exit 1
rm -rf squashfs-root
else
  echo Update cdroot from cdhelpers
  cp -rav ../cdhelpers/* .
  [ -f cdupdate.sh ] && chmod a+x cdupdate.sh
fi

if [ -d ../cpiofiles ]; then
pushd ../cpiofiles
  echo Updating cpio initrd from cpiofiles
  find .
  ls -lh ../gentoo_boot_cd/boot/gentoo.igz
  find . -print | cpio -H newc -o | xz --check=crc32 -vT0 >> ../gentoo_boot_cd/boot/gentoo.igz
  ls -lh ../gentoo_boot_cd/boot/gentoo.igz
popd
fi

# remove do keymap and
# default to swedish keyboard and add autoinstall TODO make it settable
sed -i "s/ dokeymap/ keymap=${KEYMAP} autoinstall/" $bootmenufiles

if [ "$AUTO" == "YES" ]; then
  echo running with auto - wont stop
  [[ "$SETUPDONEHALT" == "YES" ]] && sed -i 's/ autoinstall$/ autoinstall setupdonehalt/' $bootmenufiles
# TODO have an option for if using qemu serial instead of vga
  sed -i 's/ autoinstall/ autoinstall console=tty0 console=ttyS0,115200/' $bootmenufiles
  # use console for -nographics, sga and curses
  sed -i 's/vga=791//' $bootmenufiles
  cp ../install.sh g-install.sh
else
# TODO color ths to make it readable
echo -e "\n\tStarting separate shell, just exit if no changes should be done.\n\n\tWhen exit, the iso will be rebuilt."
bash
fi

# rebuild efimg https://gitweb.gentoo.org/proj/catalyst.git/tree/targets/support/create-iso.sh#n256
clst_target_path=.

popd
echo "Creating ISO ..."
grub-mkrescue -joliet -iso-level 3 -o install-amd64-mod.iso gentoo_boot_cd/

umount gentoo_boot_cd
rm -rf gentoo_boot_cd
