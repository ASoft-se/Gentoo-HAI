#!/bin/bash
set -euo pipefail
# Needed packages for grub-mkrescue emerge -uv1 sys-fs/mtools dev-libs/libisoburn app-cdr/cdrtools
# check for iso before asking for root
ebegin() { echo $* ...; }
eerror() { echo ERROR: $*; }
einfo() { echo $*; }
# Always verify script without this source after changes
[[ -f /lib/gentoo/functions.sh ]] && source /lib/gentoo/functions.sh

find_and_extractiso() {
srciso=install-amd64-minimal-*.iso
for f in $srciso; do
  if [[ ! -e "$f" ]]; then
    eerror "Matching minimal iso not found:"
    echo "   $f"
    echo " please run get_minimal_cd.sh to fetch latest version"
    exit 1
  fi
  isoname=$f
done
einfo "Using $isoname as source"

echo emerge -uv1 app-cdr/cdrtools squashfs-tools dev-libs/libisoburn mtools
ebegin "Extracting parts of iso"
set -x
# use isoinfo extraction from cdrtools
# -X keeps original mtime
mkdir -p isoextract pxe; pushd isoextract
isoinfo -j UTF-8 -R -i ../${isoname} -X -find -path /image.squashfs && mv -vf image.squashfs ../pxe
isoinfo -j UTF-8 -R -i ../${isoname} -X -find -path /boot/gentoo && mv -vf boot/gentoo ../pxe
isoinfo -j UTF-8 -R -i ../${isoname} -X -find -path /boot/gentoo.igz && mv -vf boot/gentoo.igz ../pxe
popd; rm -rf isoextract
grubkernel=$(isoinfo -j UTF-8 -R -i ${isoname} -x /boot/grub/grub.cfg | grep "linux /boot" | grep -v docache)
set +x
[[ -z "$grubkernel" ]] && eerror "No kernel info from grub.cfg found"

kernel=${grubkernel#*/boot/gentoo }
einfo "Official kernel cmdline:\n     $kernel"
#kernel=${kernel/dokeymap/\$\{keymap\}}
for i in *.ipxe; do
  ipxekernel=$(grep "kernel gentoo " "$i" | sed "s/^.*kernel gentoo /gentoo /")
  einfo "Checking for cmdline in $i:\n     $ipxekernel"
  grep -q "$kernel" "$i" && echo " - Looks good" || echo " - Might need update"
done
cat > pxe/autoexec.ipxe << EOF
#!ipxe
ifopen

kernel gentoo $kernel

initrd gentoo.igz
initrd image.squashfs /image.squashfs
initrd ../cdhelpers/cdupdate.sh /cdupdate.sh mode=755
initrd ../cdhelpers/gentoo_cd_bashrc_addon /gentoo_cd_bashrc_addon
initrd ../install.sh /g-install.sh mode=755
initrd ../portagehelper.sh /portagehelper.sh mode=755

imgstat

boot
EOF
update_cmdline pxe/autoexec.ipxe
echo "EXAMPLE: rm kvm_lxgentootest.qcow2; time sh test_w_qemu.sh auto useefi usenvme"
}
update_cmdline() {
  bootfile=$1
  # change to defined keymap and cmdline
  sed -i "s/ dokeymap/ keymap=${KEYMAP} net.ifnames=0 autoinstall/" $bootfile

  if [ "$AUTO" == "YES" ]; then
    echo running with auto - wont stop
    [[ "$SETUPDONEHALT" == "YES" ]] && sed -i 's/ autoinstall$/ autoinstall setupdonehalt/' $bootfile
    sed -i 's/ autoinstall/ autoinstall console=tty0 console=ttyS0,115200/' $bootfile
    # use console for -nographics, sga and curses
  fi
}

AUTO=
USEISO=
SETUPDONEHALT=
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
  useiso)
    USEISO=YES
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

[[ -z "${isoname:-}" ]] && find_and_extractiso

if [[ $USEISO == "YES" ]]; then
# check for root since we are using tmpfs and need root to not risk getting incorrect permissions on the new squashfs
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (to mount tmpfs), please provide password to su" 1>&2
  su -c "isoname=$isoname sh $0 ${ALLPOSITIONAL}" && [ "$AUTO" == "YES" ] && (rm kvm_lxgentootest.qcow2; time sh test_w_qemu.sh -cdrom install-amd64-mod.iso ${POSITIONAL})
  exit
fi
elif [[ "$AUTO" == "YES" ]]; then
  echo "To use ISO boot instead, add useiso argument, it does require root access"
  rm kvm_lxgentootest.qcow2; time sh test_w_qemu.sh ${POSITIONAL}
  exit $?
else # USEISO
  echo "Add auto argument to include run continuation"
  exit
fi # USEISO
# files that contains kernelcmdlines that should be patched
bootmenufiles="boot/grub/grub.cfg"
set -x
# unmount in case we got something left over since before
[ -d gentoo_boot_cd ] && umount gentoo_boot_cd || true
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=3G,nr_inodes=1048576
pushd gentoo_boot_cd || exit 1
isoinfo -j UTF-8 -R -i ../$isoname -X || exit 1

if [ $DOSQUASH == 1 ]; then
unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot

echo make changes...
# net.ifnames=0 is set, but ...
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

update_cmdline $bootmenufiles

if [ "$AUTO" == "YES" ]; then
  cp ../install.sh g-install.sh
  cp ../portagehelper.sh .
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
