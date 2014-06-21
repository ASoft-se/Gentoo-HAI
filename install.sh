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
# Partitioning will be 100MB boot(ext2) 4GB Swap and the rest root(ext4) on /dev/sda
#
# Hostname will be set to the same as the host
# Keyboard layout will be configured to be swedish (sv-latin1) and timezone Europe/Stockholm (and ntp.se will be used as a timeserver)
#

# Make sure our root mountpoint exists
mkdir -p /mnt/gentoo

IDEV=/dev/sda
FSTABDEV=${IDEV}

if [ "$(hostname)" == "livecd" ]; then
  echo Change hostname before you continue since it will be used for the created host.
  exit 1
fi
#IF NOT SET_PASS is set then the password will be "password"
SET_PASS=${SET_PASS:-password}
/etc/init.d/sshd start
echo -e "${SET_PASS}\n${SET_PASS}\n" | passwd

setterm -blank 0
set -x
# Try to update to a correct system time
ntpdate ntp.se &

#Create a 100MB boot 4GB Swap and the rest root on ${IDEV}
echo "
p
o
n
p


+100M
t
L
83
n
p


+4G
t
2
82
n
p



t
3
83
n
p


w
" | fdisk ${IDEV} || exit 1

#we should detect and use md if we multiple disks with same size...
#sfdisk -d ${IDEV} | sfdisk --force /dev/sdb || exit 1
#for a in /dev/md*; do mdadm -S $a; done

#mdadm --help
#mdadm -C --help

#mdadm -Cv /dev/md1 -l1 -n2 /dev/sd[ab]1 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md3 -l1 -n2 /dev/sd[ab]3 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md4 -l4 -n3 /dev/sd[ab]4 missing --metadata=0.90 || exit 1

mkswap -L swap0 ${IDEV}2 || exit 1
#mkswap -L swap1 /dev/sdb2 || exit 1

swapon -p1 ${IDEV}2 || exit 1

mkfs.ext2 ${IDEV}1 || exit 1
mkfs.ext4 ${IDEV}3 || exit 1

#cat /proc/mdstat

mount ${IDEV}3 /mnt/gentoo -o discard,noatime || exit 1
mkdir /mnt/gentoo/boot || exit 1
mount ${IDEV}1 /mnt/gentoo/boot || exit 1

cd /mnt/gentoo || exit 1
#cleanup in case of previous try...
[ -f *.bz2 ] && rm *.bz2
FILE=$(wget -q http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/ -O - | grep -o -e "stage3-amd64-20\w*.tar.bz2" | uniq)
[ -z "$FILE" ] && exit 1
#download latest stage file.
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/$FILE || exit 1
mkdir -p usr
time tar -xjpf stage3-*bz2 &

(wget http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.bz2 && \
  cd usr && \
  time tar -xjf ../portage-latest.tar.bz2) || exit 1
wait
cp /etc/resolv.conf etc
# make sure we are done with root unpack...

echo "# Set to the hostname of this machine
hostname=\"$(hostname)\"
" > etc/conf.d/hostname
#change fstab to match disk layout
echo -e "
${FSTABDEV}1		/boot		ext2		noauto,noatime	1 2
${FSTABDEV}3		/		ext4		discard,noatime	0 1
LABEL=swap0		none		swap		sw		0 0

none			/var/tmp	tmpfs		size=4G,nr_inodes=1M 0 0
" >> etc/fstab
sed -i '/\/dev\/BOOT.*/d' etc/fstab
sed -i '/\/dev\/ROOT.*/d' etc/fstab
sed -i '/\/dev\/SWAP.*/d' etc/fstab
for p in sys dev proc; do mount /$p $p -o bind; done  || exit 1

MAKECONF=etc/portage/make.conf
[ ! -f $MAKECONF ] && [ -f etc/make.conf ] && MAKECONF=etc/make.conf
echo $MAKECONF

#Updating Makefile
echo >> $MAKECONF
echo "# add valid -march= to CFLAGS" >> $MAKECONF
echo "MAKEOPTS=\"-j4\"" >> $MAKECONF
echo "FEATURES=\"parallel-fetch\"" >> $MAKECONF
# tty-helpers is needed py apcupsd
echo "USE=\"\${USE} -X -bindist python qemu gnutls idn iproute2 logrotate snmp tty-helpers\"" >> $MAKECONF

grep -q autoinstall /proc/cmdline || nano $MAKECONF

echo "keymap=\"sv-latin1\"" >> etc/conf.d/keymaps

echo "rc_logger=\"YES\"" >> etc/rc.conf
echo "rc_sys=\"\"" >> etc/rc.conf

echo "
dhcp_eth0=\"nodns nontp nonis nosendhost\"
#config_eth0=\"dhcp\"
config_eth0=\"192.168.0.251/24\"
routes_eth0=\"default via 192.168.0.254\"

config_eth1=\"null\"
bridge_br1=\"eth1\"

config_br1=\"10.100.1.254/24\"
brctl_br1=\"setfd 0
stp off\"

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
echo -e "${SET_PASS}\n${SET_PASS}\n" | passwd
set -x
rm *.bz2
mount /var/tmp

[ -d /etc/portage/package.keywords ] || mkdir -p /etc/portage/package.keywords
grep -q gentoo-sources /etc/portage/package.keywords/* || echo sys-kernel/gentoo-sources > /etc/portage/package.keywords/kernel
touch /etc/portage/package.use
grep -q net-dns/bind /etc/portage/package.use || echo net-dns/bind dlz geoip idn caps threads >> /etc/portage/package.use
# The old udev rules are removed and now replaced with the PredictableNetworkInterfaceNames madness instead, and no use flags any more.
#   Will have to revert to the old way of removing the files on boot/shutdown, and just hope they don't change the naming.
#   Looks like udev is just getting worse and worse, switching to eudev.
# touch to disable the unpredictable "PredictableNetworkInterfaceNames"
touch /etc/udev/rules.d/80-net-name-slot.rules
# they made it unpredictable and changed the name, so lets be future prof
touch /etc/udev/rules.d/80-net-setup-link.rules
grep -q sys-fs/eudev /etc/portage/package.use || echo sys-fs/eudev hwdb gudev keymap -rule-generator >> /etc/portage/package.use
time emerge -C --quiet-unmerge-warn sys-fs/udev
# will reinstall eudev further down after kernel sources
time emerge -uvN sys-fs/eudev
# mask old udev so it is not pulled in.
echo sys-fs/udev >> /etc/portage/package.mask
#snmp support in current apcupsd is buggy
grep -q sys-power/apcupsd /etc/portage/package.use || echo sys-power/apcupsd -snmp >> /etc/portage/package.use

#start out with being up2date
#we expect that this can fail
time emerge -uv -j4 portage python-updater gentoolkit
time emerge -uvDN -j4 world
etc-update --automode -5
time python-updater -v -- -j4 || bash
time revdep-rebuild -vi -- -j4
etc-update --automode -5

time emerge -uv -j8 gentoo-sources mlocate postfix iproute2 bind quagga dhcp atftp dhcpcd app-misc/mc pciutils usbutils smartmontools syslog-ng vixie-cron ntp lsof || bash
# reinstall eudev, TODO detect if we did switch above and only install if needed
time emerge -uvN -j8 eudev
time emerge -uv -j8 iptables grub bridge-utils v86d ebtables vconfig || bash
lspci
ntpdate ntp.se
#rerun make sure up2date
time emerge -uvDN -j4 world || bash
etc-update --automode -5
time python-updater -v -- -j4 || bash
time revdep-rebuild -vi -- -j4
etc-update --automode -5

cd /usr/src/linux
#getting a base kernel config
wget https://raw.github.com/ASoft-se/Gentoo-HAI/master/krn330.conf -O .config
echo "
# Gentoo Linux
CONFIG_GENTOO_LINUX=y
CONFIG_GENTOO_LINUX_UDEV=y
CONFIG_GENTOO_LINUX_INIT_SCRIPT=y

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

" >> .config

echo "x
y
" | make menuconfig
time make -j16 bzImage modules && make modules_install install
ls -lh /boot
cd /boot
ln -s vmlinuz-* vmlinuz && cd /usr/src/linux && make install
ls -lh /boot
echo "
# added auto fix timeout ?
timeout 3
title Gentoo
root (hd0,0)
# video=uvesafb:1024x768-32 is not stable on ex intel integrated gfx
#kernel /vmlinuz root=${FSTABDEV}3 ro rootfstype=ext4 panic=30 vga=791" >> /boot/grub/grub.conf
#mcedit /boot/grub/grub.conf
#echo "root (hd0,0)
#setup (hd0)
#quit
#" | grub
grub2-install /dev/sda
sed -i '/\^//' /etc/default/grub
sed -i 's/^#GRUB_DISABLE_LINUX_UUID=[a-z]*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sed -i 's/^#GRUB_CMDLINE_LINUX_DEFAULT=""/GRUB_CMDLINE_LINUX_DEFAULT="rootfstype=ext4 panic=30 vga=791"/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=10/GRUB_TIMEOUT=3/' /etc/default/grub
grub2-mkconfig -o /boot/grub/grub.cfg

cd /etc
ln -fs /usr/share/zoneinfo/Europe/Stockholm localtime
touch /lib64/rc/init.d/softlevel
#make sure everything is up2date
sed -i 's/^#CHROOT=/CHROOT=/' /etc/conf.d/named
emerge --config net-dns/bind
#TODO sed fix syslog unix-stream("/chroot/dns/dev/log");
sed -i 's/^# DHCPD_CHROOT=/DHCPD_CHROOT=/' /etc/conf.d/dhcpd
#TODO syslog unix-stream("...dhcp");
dispatch-conf

#todo fix with sed ... but virtual machine dont save clock ;)
#mcedit /etc/conf.d/hwclock
#touch /lib64/rc/init.d/softlevel
#/etc/init.d/hwclock save
date
sleep 3
sed -i 's/^c1:12345:respawn:\/sbin\/agetty .* tty1 linux\$/& --noclear/' /etc/inittab || bash
cd /etc/init.d
ln -s net.lo net.eth0
rc-update add syslog-ng default
rc-update add vixie-cron default
rc-update add atftp default
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
rc-update add sshd default
/etc/init.d/sshd gen_keys

# Start creating fix script
echo # Remove udev rules that make network interface names compleatly unpredictable and unmanagable. > /etc/local.d/remove.net.rules.start
echo setterm -blank 0 >> /etc/local.d/remove.net.rules.start
echo rm -rf /lib/udev/rules.d/80-net-name-slot.rules >> /etc/local.d/remove.net.rules.start

# Make it executable, and run also on shutdown
chmod a+x /etc/local.d/remove.net.rules.start
ln -fs /etc/local.d/remove.net.rules.start ln -fs /etc/local.d/remove.net.rules.stop
rc-update add local default
# run it now and add clean exit (rm will fail if there is no file so always exit with ok)
sh /etc/local.d/remove.net.rules.start
echo exit 0 >> /etc/local.d/remove.net.rules.start

touch /etc/quagga/zebra.conf
touch /etc/quagga/ospfd.conf
echo EXTRA_OPTS=\"-A 127.0.0.1 -P 0\" >> /etc/conf.d/zebra
echo EXTRA_OPTS=\"-A 127.0.0.1 -P 0\" >> /etc/conf.d/ospfd

sed -i 's/^smtp.*inet/#&/' /etc/postfix/master.cf
rc-update add postfix default
echo root:           root@asoft.se >> /etc/mail/aliases
newaliases

sed -i 's/\troot\t/\t/' /etc/crontab
echo -e"*/30  *  * * *\tntpdate -s ntp.se" >> /etc/crontab
crontab /etc/crontab

rc-update add named default
sleep 5 || bash

# fix problem with apcupsd...
[ -d /run/lock ] || mkdir /run/lock
emerge -uv -j4 net-snmp squid vsftpd subversion php openvpn apcupsd iotop iftop dd-rescue tcpdump nmap netkit-telnetd dmidecode hdparm parted || bash
#todo if local ups... rc-update add apcupsd.powerfail shutdown
#todo configure snmp and add to startup

#todo... if vmware emerge open-vm-tools?

#mcedit /etc/rc.conf
mcedit /etc/conf.d/net
rc-update add net.eth0 default
#sleep 5 || bash

umount /var/tmp
rm chrootstart.sh
EOF
chmod a+x chrootstart.sh

chroot . ./chrootstart.sh
rm chrootstart.sh

umount var/tmp
rm -rf var/tmp/*
rm -rf usr/portage/distfiles
umount *
cd /
umount /mnt/gentoo  || exit 1
reboot
