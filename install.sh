#!/bin/bash
# Copyleft Christian Nilsson
# Please do what you want! Use on your own risk and all that!
#
# This script partitions ${IDEV}, creates filesystem and installs gentoo.
# Everything is done including the first reboot (just before reboot it will stop and let you edit the network configuration)
#
# root password will be set to SET_PASS parameter or "password" if not given
# ssh server will be started on the live medium directly after the password have been set.
#
# Hostname will be set to the same as the host
# Keyboard layout will be configured to be swedish (sv-latin1) and timezone Europe/Stockholm (and ntp.se will be used as a timeserver)
#

# Make sure our root mountpoint exists
mkdir -p /mnt/gentoo

if [ -b /dev/nvme0n1 ]; then
  IDEV=${IDEV:-/dev/nvme0n1}
  NVMETOOLS=sys-apps/nvme-cli
  NVMEKERNEL=CONFIG_BLK_DEV_NVME=y
fi
[[ -b /dev/vda ]] && [[ ! -b /dev/sda ]] && IDEV=${IDEV:-/dev/vda}

IDEV=${IDEV:-/dev/sda}
IDEVP=${IDEV}
# if disk name ends with number, then partition is sepparated with p
echo ${IDEV} | grep -q -e "[0-9]$" && IDEVP=${IDEV}p

if [ "$(hostname)" == "livecd" ]; then
  echo Change hostname before you continue since it will be used for the created host.
  exit 1
fi
#IF NOT SET_PASS is set then the password will be "password"
SET_PASS=${SET_PASS:-password}

set -x
# Try to update to a correct system time
ntpdate ntp.se &
pid_ntp=$!
echo "trying to grab Gentoo releng & infrastructure gpg key in the background ..."
(gpg --locate-key releng@gentoo.org; gpg --locate-key infrastructure@gentoo.org) &
pid_gpg=$!

PLATFORM=pcbios
if [ -d /sys/firmware/efi ]; then
  PLATFORM=efi
fi

#Create bios boot, 128MB boot, 128MB EFI, 4GB Swap and the rest root on ${IDEV}
echo "gpt
print
new
99

+2M
type
21686148-6449-6E6F-744E-656564454649
xpert
A
return
new
1

+128M
new
2

+128M
type
2
uefi
new
3

+4G
type
3
swap
new
4


type
4
4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
xpert
name
1
/boot
name
2
/boot/efi
name
3
swap0
name
4
/
name
99
GRUB BIOS Data
return
print
write
" | fdisk ${IDEV} || exit 1
sfdisk -d ${IDEV}
file -s ${IDEV}
# Wait a bit for the dust to settle on the new devices
sleep 1

#we should detect and use md if we multiple disks with same size...
#sfdisk -d ${IDEV} | sfdisk --force /dev/sdb || exit 1
#for a in /dev/md*; do mdadm -S $a; done

#mdadm --help
#mdadm -C --help

#mdadm -Cv /dev/md1 -l1 -n2 /dev/sd[ab]1 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md3 -l1 -n2 /dev/sd[ab]3 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md4 -l4 -n3 /dev/sd[ab]4 missing --metadata=0.90 || exit 1

mkswap -L swap0 ${IDEVP}3 || exit 1
swapon -p1 ${IDEVP}3 || exit 1
mkfs.ext2 ${IDEVP}1 || exit 1
mkfs.vfat ${IDEVP}2 || exit 1
mkfs.ext4 ${IDEVP}4 || exit 1

mount ${IDEVP}4 /mnt/gentoo -o discard,noatime || exit 1
mkdir -p /mnt/gentoo/boot || exit 1
mount ${IDEVP}1 /mnt/gentoo/boot || exit 1
mkdir -p /mnt/gentoo/boot/efi || exit 1
mount ${IDEVP}2 /mnt/gentoo/boot/efi || exit 1

# wait to make sure ntpdate is done
wait $pid_ntp
cd /mnt/gentoo || exit 1
#cleanup in case of previous try...
[ -f "*.tar.{bz2,xz,sqfs}" ] && rm *.tar.{bz2,xz,sqfs}
DISTMIRROR=http://distfiles.gentoo.org
wget ${DISTMIRROR}/snapshots/squashfs/sha512sum.txt
SNAPSHOT=$(grep -o -E "\w*-[0-9]*\.xz.sqfs" sha512sum.txt | sort -r | head -1)
# Use rsync for later updates
wget ${DISTMIRROR}/snapshots/squashfs/$SNAPSHOT &
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-stage3-amd64-openrc/
FILE=$(wget -q $DISTBASE -O - | grep -o -E 'stage3-amd64-openrc-\w*\.tar\.xz' | sort -r | head -1)
[ -z "$FILE" ] && echo -e "\e[91mNo stage3 found on $DISTBASE\e[0m" && exit 1
echo -e "\e[93mdownload latest stage file $FILE\e[0m"
wget $DISTBASE$FILE || bash
wget $DISTBASE$FILE.DIGESTS || bash
wait $pid_gpg > /dev/null
gpg --verify $FILE.DIGESTS || bash
echo "Verifying stage3 SHA512 ..."
# grab SHA512 lines and line after, then filter out line that ends with iso
echo "$(grep -A1 SHA512 $FILE.DIGESTS | grep $FILE\$)" | sha512sum -c || bash
echo -e "- \e[92mAwesome!\e[0m stage3 verification looks good."
rm $FILE.DIGESTS
time tar xpf $FILE --xattrs-include='*.*' --numeric-owner

wait || exit 1
gpg --verify sha512sum.txt || bash
ls -lha
mv $SNAPSHOT gentoo-current.xz.sqfs || bash
snapshot512=$(sha512sum gentoo-current.xz.sqfs | awk '{print $1}')
echo -e "\e[93mSnapshot  SHA512 $snapshot512 ...\e[0m"
echo -e "\e[93mExpecting SHA512 $(grep gentoo-current.xz.sqfs sha512sum.txt)\e[0m"
grep $snapshot512 sha512sum.txt && echo -e " \e[92m - OK\e[0m" || (echo " \e[91mnot found in sha512sum.txt\e[0m"; bash)
rm sha512sum.txt
mkdir -p var/db/repos/gentoo && \
  mount -rt squashfs -o loop,nodev,noexec gentoo-current.xz.sqfs var/db/repos/gentoo || bash
rm $FILE
cp /etc/resolv.conf etc
# make sure we are done with root unpack...

echo "# Set to the hostname of this machine
hostname=\"$(hostname)\"
" > etc/conf.d/hostname
#change fstab to match disk layout
echo -e "
${IDEVP}1		/boot		ext2		noauto,noatime	1 2
${IDEVP}2		/boot/efi		vfat		noauto,noatime	1 2
${IDEVP}4		/		ext4		discard,noatime	0 1
LABEL=swap0		none		swap		sw		0 0

none			/var/tmp	tmpfs		size=4G,nr_inodes=1M 0 0
" >> etc/fstab
sed -i '/\/dev\/BOOT.*/d' etc/fstab
sed -i '/\/dev\/ROOT.*/d' etc/fstab
sed -i '/\/dev\/SWAP.*/d' etc/fstab
mount --types proc /proc proc
for p in sys dev; do mount --rbind /$p $p; mount --make-rslave $p; done  || exit 1
for p in run; do mount --bind /$p $p; mount --make-slave $p; done  || exit 1

MAKECONF=etc/portage/make.conf
[ ! -f $MAKECONF ] && [ -f etc/make.conf ] && MAKECONF=etc/make.conf
echo $MAKECONF

# CPU_FLAGS_X86 should be handled but must be done inside chroot, see below

#Updating Makefile
echo >> $MAKECONF
echo "# add valid -march= to CFLAGS" >> $MAKECONF
echo "MAKEOPTS=\"-j$(nproc)\"" >> $MAKECONF
echo "FEATURES=\"parallel-fetch buildpkg\"" >> $MAKECONF
# tty-helpers is needed py apcupsd
echo "USE=\"\${USE} -X qemu gnutls idn iproute2 logrotate snmp tty-helpers\"" >> $MAKECONF

grep -q autoinstall /proc/cmdline || nano $MAKECONF

echo "keymap=\"sv-latin1\"" >> etc/conf.d/keymaps

echo "rc_logger=\"YES\"" >> etc/rc.conf
echo "rc_sys=\"\"" >> etc/rc.conf

echo "
# https://wiki.gentoo.org/wiki/Netifrc/Brctl_Migration
config_br0=\"dhcp\"
bridge_br0=\"eth0\"
bridge_forward_delay_br0=0
bridge_stp_state_br0=0
dhcp_br0=\"nodns nontp nonis nosendhost\"

#config_br0=\"192.168.0.251/24\"
#routes_br0=\"default via 192.168.0.254\"

config_eth0="null"
rc_net_br0_need="net.eth0"

config_eth1=\"null\"
bridge_br1=\"eth1\"

config_br1=\"10.100.1.254/24\"
bridge_forward_delay_br1=0
bridge_stp_state_br1=0

vlans_eth1=\"101 120 140\"
config_eth1_101=\"null\"
config_eth1_120=\"10.100.20.254/24\"
config_eth1_140=\"10.100.40.254/24\"


tuntap_vpnUA=\"tap\"
#keep same MAC
mac_vpnUA=\"00:14:0A:01:64:65\"
rc_before_vpnUA=\"openvpn.vpnua\"
config_vpnUA=\"10.1.100.101/24\"
routes_vpnUA=\"10.100.0.0/16 via 10.1.100.1\"

" >> etc/conf.d/net

#generate chroot script
cat > chrootstart.sh << EOF
#!/bin/bash
env-update
source /etc/profile
# do some dance around to be able to set password
cp /etc/pam.d/system-auth system-auth.bak
sed -i 's/^password/#password/' /etc/pam.d/system-auth
echo 'password required pam_unix.so' >> /etc/pam.d/system-auth
echo "root:${SET_PASS}" | chpasswd
mv system-auth.bak /etc/pam.d/system-auth
set -x
mount /var/tmp
getuto & > /dev/null
export FEATURES="getbinpkg"
export EMERGE_DEFAULT_OPTS="--binpkg-respect-use=y"

# fix for new mtab init
ln -snf /proc/self/mounts /etc/mtab

[ -d /etc/portage/repos.conf ] || mkdir -p /etc/portage/repos.conf
[ -d /etc/portage/package.accept_keywords ] || mkdir -p /etc/portage/package.accept_keywords
[ -d /etc/portage/package.use ] || mkdir -p /etc/portage/package.use
[ -d /etc/portage/package.mask ] || mkdir -p /etc/portage/package.mask

grep -q gentoo-sources /etc/portage/package.accept_keywords/* || echo sys-kernel/gentoo-sources > /etc/portage/package.accept_keywords/kernel &
grep -q net-dns/bind /etc/portage/package.use/* || echo net-dns/bind dlz idn caps threads >> /etc/portage/package.use/bind &
# The old udev rules are removed and now replaced with the PredictableNetworkInterfaceNames madness instead, and no use flags any more.
#   Will have to revert to the old way of removing the files on boot/shutdown, and just hope they don't change the naming.
#   Looks like udev is just getting worse and worse, unfortunatly eudev is no longer available?
# touch to disable the unpredictable "PredictableNetworkInterfaceNames"
touch /etc/udev/rules.d/80-net-name-slot.rules &
# they made it unpredictable and changed the name, so lets be future prof
touch /etc/udev/rules.d/80-net-setup-link.rules &
wait
time emerge -uvN1 -j8 --keep-going y portage gentoolkit cpuid2cpuflags || bash
#snmp support in current apcupsd is buggy
grep -q sys-power/apcupsd /etc/portage/package.use/* || echo sys-power/apcupsd -snmp >> /etc/portage/package.use/apcupsd
grep -q net-firewall/nftables /etc/portage/package.use/* || echo net-firewall/nftables xtables >> /etc/portage/package.use/nftables
[[ ! -z "${NVMETOOLS}" ]] && (grep -q nvme /etc/portage/package.accept_keywords/* || echo ${NVMETOOLS} > /etc/portage/package.accept_keywords/nvme) &

#add new CPU_FLAGS_X86
echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpuflags

#start out with being up2date
#we expect that this can fail
time emerge -uvDN -j4 --keep-going y world --exclude gcc glibc
etc-update --automode -5

[ -f /etc/portage/package.mask/gentoo.conf ] || cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

time emerge -uv -j8 installkernel grub gentoo-sources pciutils usbutils ntp iproute2 sys-apps/memtest86+ ${NVMETOOLS} || bash
mkdir /tftproot
lspci
ntpdate ntp.se

eselect kernel set 1
cd /usr/src/linux
#getting a base kernel config
wget https://raw.githubusercontent.com/ASoft-se/Gentoo-HAI/master/krn330.conf -O .config
echo "
# Gentoo Linux
CONFIG_GENTOO_LINUX=y
CONFIG_GENTOO_LINUX_UDEV=y
CONFIG_GENTOO_LINUX_INIT_SCRIPT=y
CONFIG_SQUASHFS=m
CONFIG_SQUASHFS_XZ=y

#fix hotplug (vmware)
CONFIG_HOTPLUG_PCI_SHPC=y
#no use for sound in virtual machine
CONFIG_SOUND=n
#scsi support vmware but also intel sas card
CONFIG_FUSION=y
CONFIG_FUSION_SPI=y
CONFIG_FUSION_FC=y
CONFIG_FUSION_SAS=y
CONFIG_FUSION_CTL=y
#vmware -only- scsi
CONFIG_VMWARE_PVSCSI=y
CONFIG_SCSI_BUSLOGIC=y
CONFIG_SCSI_SYM53C8XX_2=y
CONFIG_I2C_PIIX4=y
#vmware ensure network
CONFIG_VMXNET3=m
CONFIG_NET_VENDOR_AMD=y
CONFIG_PCNET32=m
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=y
CONFIG_E1000E=y
CONFIG_NLMON=y
#KVM/XEN Virtio
CONFIG_VIRTIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_BLK_SCSI=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_INPUT=y
CONFIG_VIRTIO_MMIO=m
#ups support...
CONFIG_HIDRAW=m
CONFIG_HIDRAW=y
#iotop stuff
CONFIG_TASK_IO_ACCOUNTING=y
CONFIG_TASK_DELAY_ACCT=y
CONFIG_TASKSTATS=y
CONFIG_VM_EVENT_COUNTERS=y
#qemu kvm_stat need
CONFIG_DEBUG_FS=y

# use old vesa, vga= mode
CONFIG_FB_VESA=y
# and make uvesafb a module instead
CONFIG_FB_UVESA=m

# make sure the kernel supports EFI boot
CONFIG_EFI_STUB=y
CONFIG_FB_EFI=y

# New Netfilter (to get iptables nat working)
CONFIG_NF_TABLES=m
CONFIG_NFT_MASQ=m
CONFIG_NFT_REDIR=m
CONFIG_NFT_NAT=m
CONFIG_NFT_COMPAT=m
CONFIG_NETFILTER_XT_NAT=m
CONFIG_NETFILTER_XT_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV4=m
CONFIG_NFT_CHAIN_ROUTE_IPV4=m
CONFIG_NF_NAT_IPV4=m
CONFIG_NFT_CHAIN_NAT_IPV4=m
CONFIG_NF_NAT_MASQUERADE_IPV4=m
CONFIG_NFT_MASQ_IPV4=m
CONFIG_NFT_REDIR_IPV4=m
CONFIG_IP_NF_NAT=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV6=m
CONFIG_NFT_CHAIN_ROUTE_IPV6=m

# if we have nvme hardware
${NVMEKERNEL}

# Serial console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_DEPRECATED_OPTIONS=n

" >> .config

# v86d is dead so remove its initramfs
sed -i 's#/usr/share/v86d/initramfs##' .config
echo "x
y
" | make menuconfig > /dev/null
time make -j$(($(nproc)*2)) bzImage modules && make modules_install install || bash
ls -lh /boot
cd /boot
ln -s vmlinuz-* vmlinuz && cd /usr/src/linux && make install

grub-install --target=x86_64-efi --efi-directory=/boot/efi ${IDEV}
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable ${IDEV}
grub-install --target=i386-pc ${IDEV}
sed -i 's/^#GRUB_DISABLE_LINUX_UUID=[a-z]*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sed -i 's/^#GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="rootfstype=ext4 panic=30 vga=791"/' /etc/default/grub
sed -i 's/^#*GRUB_TIMEOUT=[0-9]+/GRUB_TIMEOUT=3/' /etc/default/grub
grep -q console= /proc/cmdline && sed -i 's/ vga=791/ console=tty0 console=ttyS0,115200/' /etc/default/grub
grep -q console= /proc/cmdline && sed -i 's/^#GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
grep -q console= /proc/cmdline && echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0"' >> /etc/default/grub
# enable in inittab
grep -q console= /proc/cmdline && sed -i 's/^#s0:/s0:/' /etc/inittab
grub-mkconfig -o /boot/grub/grub.cfg
ls -lh /boot; find /boot/efi; efibootmgr

cd /etc
ln -fs /usr/share/zoneinfo/Europe/Stockholm localtime
emerge -uv -j8 --keep-going y iptables nftables net-snmp dev-vcs/git php openvpn apcupsd iotop iftop ddrescue tcpdump nmap netkit-telnetd dmidecode hdparm \
 mlocate postfix bind bind-tools dhcp atftp dhcpcd app-misc/mc smartmontools syslog-ng virtual/cron ntp lsof || bash
#rerun make sure up2date
time emerge -uvDN -j4 world --exclude gcc glibc || bash
etc-update --automode -5
sed -i 's/^#CHROOT=/CHROOT=/' /etc/conf.d/named
emerge --config net-dns/bind
# fix some possibly missing files #51 just in case
# should be fixed in https://bugs.gentoo.org/793860 by gentoo/gentoo@6e8faaad077caf9048e2c5a132ddade0b0b316aa
[ -e /chroot/dns/dev/urandom ] || cp -a /dev/urandom /chroot/dns/dev/
find /chroot/dns
#TODO sed fix syslog unix-stream("/chroot/dns/dev/log");
sed -i 's/^# DHCPD_CHROOT=/DHCPD_CHROOT=/' /etc/conf.d/dhcpd
#TODO syslog unix-stream("...dhcp");
dispatch-conf

#todo fix with sed ... but virtual machine dont save clock ;)
#mcedit /etc/conf.d/hwclock
#/etc/init.d/hwclock save
sed -i 's/^c1:12345:respawn:\/sbin\/agetty .* tty1 linux\$/& --noclear/' /etc/inittab || bash
cd /etc/init.d
ln -s net.lo net.eth0
ln -s net.lo net.br0
rc-update add syslog-ng default
rc-update add *cron* default
rc-update add atftp default
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
rc-update add sshd default

# Start creating fix script
echo # Remove udev rules that make network interface names compleatly unpredictable and unmanagable. > /etc/local.d/remove.net.rules.start
echo setterm -blank 0 >> /etc/local.d/remove.net.rules.start
echo rm -rf /lib/udev/rules.d/80-net-name-slot.rules >> /etc/local.d/remove.net.rules.start

# Make it executable, and run also on shutdown
chmod a+x /etc/local.d/remove.net.rules.start
ln -fs /etc/local.d/remove.net.rules.start /etc/local.d/remove.net.rules.stop
rc-update add local default
# run it now and add clean exit (rm will fail if there is no file so always exit with ok)
sh /etc/local.d/remove.net.rules.start
echo exit 0 >> /etc/local.d/remove.net.rules.start

sed -i 's/^smtp.*inet/#&/' /etc/postfix/master.cf
rc-update add postfix default
echo root:           root@asoft.se >> /etc/mail/aliases
newaliases

# TODO detect if username should be included or not
#sed -i 's/\troot\t/\t/' /etc/crontab
echo -e "*/30  *  * * *\troot\tntpdate -s ntp.se" >> /etc/crontab
crontab /etc/crontab

rc-update add named default

# move to git based portage tree
umount /var/db/repos/gentoo
rm /gentoo-current.xz.sqfs
sed -i 's#sync-type = rsync#sync-type = git#' /etc/portage/repos.conf/gentoo.conf
sed -i 's#sync-uri = rsync://rsync.gentoo.org/gentoo-portage#sync-uri = git://anongit.gentoo.org/repo/gentoo.git#' /etc/portage/repos.conf/gentoo.conf
cd /var/db/repos/gentoo/
git clone --depth 1 git://anongit.gentoo.org/repo/gentoo.git -n && mv gentoo/.git .
git checkout -f
git clean -d -x -f -q
chown -R portage:portage .
#if some lingring unexpected files are left behind remove it
rmdir gentoo
emerge --sync

#todo if local ups... rc-update add apcupsd.powerfail shutdown
#todo configure snmp and add to startup

#todo... if vmware emerge open-vm-tools?

#mcedit /etc/rc.conf
grep -q autoinstall /proc/cmdline || mcedit /etc/conf.d/net
rc-update add net.br0 default
#sleep 5 || bash

umount /var/tmp
EOF
chmod a+x chrootstart.sh

time chroot . ./chrootstart.sh
rm chrootstart.sh

umount var/tmp
rm -rf var/tmp/*
rm -rf var/cache/distfiles
umount *
cd /
## umount somehow fails recently, but can not find usage, lets go lazy
umount -l /mnt/gentoo  || exit 1
# halt in QEMU guest instead of reboot to messure and autohandle on vm shutdown
grep -q setupdonehalt /proc/cmdline && halt || reboot
