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
# Hostname will be set to the same as the host if not overriden by HAIHOSTNAME
# Keyboard layout, timezone and ntp server see settings below
#

# Make sure our root mountpoint exists
esca=$(echo -e "\e[")
mkdir -p /mnt/gentoo

# Parse /proc/cmdline
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        TIMEZONE=*|NTPSERVER=*|KEYMAP=*|ROOTEMAIL=*|IDEV=*|SET_PASS=*|HAIHOSTNAME=*)
            key="${arg%%=*}"
            [[ -z "${!key}" ]] && eval "$key=\"\${arg#*=}\""
            ;;
    esac
done

TIMEZONE=${TIMEZONE:-Europe/Stockholm}
NTPSERVER=${NTPSERVER:-ntp.se}
KEYMAP=${KEYMAP:-sv-latin1}
ROOTEMAIL=${ROOTEMAIL:-root@asoft.se}
#IF NOT SET_PASS is set then the password will be "password"
SET_PASS=${SET_PASS:-password}
HAIHOSTNAME=${HAIHOSTNAME:-$(hostname)}

# Packages that is used by script or init, oneshot installs
PACKAGES_INIT=(
    sys-apps/portage
    net-misc/curl
    net-misc/chrony
    app-portage/gentoolkit
    cpuid2cpuflags
    sys-apps/pv
    sys-apps/iproute2
    app-arch/lz4
)
PACKAGES_PREFETCH=(
    sys-kernel/gentoo-sources
    sys-kernel/installkernel
    sys-apps/pciutils
)
# Packages for kernel
PACKAGES_KRNL=(
    "${PACKAGES_PREFETCH[@]}"
    sys-fs/dosfstools
    sys-apps/usbutils
    sys-apps/memtest86+
)
# some packages to prefetch, not part of KRNL emerge
PACKAGES_PREFETCH+=(
    dev-vcs/git
    app-admin/syslog-ng
    net-misc/dhcp
    net-analyzer/net-snmp
    net-analyzer/nmap
)
# Other packages to install before reboot
PACKAGES_POST=(
    net-firewall/iptables
    net-firewall/nftables
    net-analyzer/net-snmp
    dev-vcs/git
    sys-process/iotop
    net-analyzer/iftop
    sys-fs/ddrescue
    net-analyzer/tcpdump
    net-analyzer/nmap
    net-misc/netkit-telnetd
    sys-apps/dmidecode
    sys-apps/hdparm
    sys-apps/mlocate
    mail-mta/postfix
    net-dns/bind
    net-misc/dhcp
    sys-apps/watchdog
    net-ftp/tftp-hpa
    net-misc/dhcpcd
    app-misc/mc
    sys-apps/smartmontools
    app-admin/syslog-ng
    virtual/cron
    app-admin/logrotate
    sys-process/lsof
)

NVMEKERNEL=
if [ -b /dev/nvme0n1 ]; then
  IDEV=${IDEV:-/dev/nvme0n1}
  PACKAGES_KRNL+=( sys-apps/nvme-cli )
  NVMEKERNEL=CONFIG_BLK_DEV_NVME=y
fi
[[ -b /dev/vda ]] && [[ ! -b /dev/sda ]] && IDEV=${IDEV:-/dev/vda}

IDEV=${IDEV:-/dev/sda}
IDEVP=${IDEV}
# if disk name ends with number, then partition is sepparated with p
[[ "${IDEV}" =~ [0-9]$ ]] && IDEVP=${IDEV}p

if [ "$HAIHOSTNAME" == "livecd" ]; then
  echo Change hostname before you continue since it will be used for the created host.
  exit 1
fi

set -x -u
GHBASEURL="https://raw.githubusercontent.com/ASoft-se/Gentoo-HAI/refs/heads/master"
# Try to update to a correct system time
touch /var/db/ntp-kod
sntp -S $NTPSERVER &
pid_ntp=$!

[ -d /sys/firmware/efi ] && PLATFORM=efi || PLATFORM=pcbios

find /sys/devices/ -name "idVendor" -exec grep -l "051d" {} + | while read f; do
    echo we have an APC device, probably UPS add apcupsd
    cat "$(dirname "$f")/manufacturer" "$(dirname "$f")/product"
    PACKAGES_POST+=( apcupsd )
done

BATTERYDEV=$(grep -l "Battery" /sys/class/power_supply/*/type)
if [[ -n "${BATTERYDEV}" ]]; then
    PACKAGES_POST+=( sys-power/acpi )
fi

partition_format_mount() {
#Create bios boot, 128MB boot, 128MB EFI, 4GB Swap and the rest root on ${IDEV}
fdisk ${IDEV} << EOF || exit 1
gpt
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
EOF
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
echo y | mkfs.ext2 ${IDEVP}1 || exit 1
mkfs.vfat ${IDEVP}2 || exit 1
echo y | mkfs.ext4 ${IDEVP}4 || exit 1

mount ${IDEVP}4 /mnt/gentoo -o discard,noatime || exit 1
mkdir -p /mnt/gentoo/boot || exit 1
mount ${IDEVP}1 /mnt/gentoo/boot || exit 1
mkdir -p /mnt/gentoo/boot/efi || exit 1
mount ${IDEVP}2 /mnt/gentoo/boot/efi || exit 1
mkdir -p /mnt/gentoo/boot/efi/EFI/BOOT/
}
partition_format_mount

# wait to make sure sntp is done
wait $pid_ntp
[ -f portagehelper.sh ] && cp portagehelper.sh /mnt/gentoo
cd /mnt/gentoo || exit 1
#cleanup in case of previous try...
[ -f "*.tar.{bz2,xz,sqfs}" ] && rm *.tar.{bz2,xz,sqfs}
[ -f portagehelper.sh ] || curl -L --remote-name-all ${GHBASEURL}/portagehelper.sh -O
sha512sum -c <<<"638564dddeac5251cc7681f393a702c8d53b51f09534f48c88de891ae534d294210b23c09601bcb81bc5285c141e30226f9b938be4b441ab7dd575c1b55f9668  portagehelper.sh" || bash
chmod a+x portagehelper.sh
mkdir -p /etc/portage/gnupg; chown -R root:root /etc/portage/gnupg; chmod 700 /etc/portage/gnupg # to not warn, will be changed in chroot
vardb=/mnt/gentoo/var/db
. ./portagehelper.sh || bash
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-stage3-amd64-openrc/
mkdir -p $pathrepo $pathsnapshots
{ { set +x; } 2>/dev/null
  echo "+ ensure_key_and_snap_source" >&2; ensure_key_and_snap_source || bash
  update_snapshot &
  set -x
}

FILE=$(curl -q $DISTBASE --output - | grep -o -E 'stage3-amd64-openrc-\w*\.tar\.xz' | sort -r | head -1)
[ -z "$FILE" ] && cat <<< "${esca}91mNo stage3 found on $DISTBASE${esca}0m" && exit 1
cat <<< "${esca}93mdownload latest stage file $FILE${esca}0m"
curl -L -C - --remote-name-all --parallel \
  $DISTBASE$FILE $DISTBASE$FILE.DIGESTS $DISTBASE$FILE.asc || bash

gpg --homedir /etc/portage/gnupg --output $FILE.DIGESTS.verified --verify $FILE.DIGESTS && rm $FILE.DIGESTS
gpg --homedir /etc/portage/gnupg --verify $FILE.asc || bash
cat <<< "Verifying stage3 SHA512 ..."
# grab SHA512 lines and line after, then filter out line that ends with iso
sha512sum -c <<< "$(grep -A1 SHA512 $FILE.DIGESTS.verified | grep $FILE\$)" || bash
cat <<< "- ${esca}92mAwesome!${esca}0m stage3 verification looks good."
rm $FILE.DIGESTS.verified $FILE.asc
time tar xpf $FILE --xattrs-include='*.*' --numeric-owner && rm $FILE

wait || exit 1
cp -rp /etc/portage/gnupg etc/portage
rm -f etc/portage/gnupg/.getuto.last
( { set +x; } 2>/dev/null; echo "+ mount_current_snapshot" >&2; mount_current_snapshot || bash)
cp /etc/resolv.conf etc
# make sure we are done with root unpack...

echo "# Set to the hostname of this machine
hostname=\"$HAIHOSTNAME\"
" > etc/conf.d/hostname
prepare_chroot_mounts() {
#change fstab to match disk layout
echo -e "
${IDEVP}1		/boot		ext2		noauto,noatime	1 2
${IDEVP}2		/boot/efi		vfat		noauto,noatime	1 2
${IDEVP}4		/		ext4		discard,noatime	0 1
LABEL=swap0		none		swap		sw		0 0

none			/var/tmp	tmpfs		size=6G,nr_inodes=1M 0 0
" >> etc/fstab
sed -i \
  -e '/\/dev\/BOOT.*/d' \
  -e '/\/dev\/ROOT.*/d' \
  -e '/\/dev\/SWAP.*/d' \
  etc/fstab
mount --types proc /proc proc
for p in sys dev; do mount --rbind /$p $p; mount --make-rslave $p; done  || exit 1
for p in run; do mount --bind /$p $p; mount --make-slave $p; done  || exit 1
}
prepare_chroot_mounts

MAKECONF=etc/portage/make.conf
[ ! -f $MAKECONF ] && [ -f etc/make.conf ] && MAKECONF=etc/make.conf

# CPU_FLAGS_X86 handled thru /etc/portage/package.use/00cpuflags inside chroot, see below

#Updating Makefile
echo >> $MAKECONF
echo "# add valid -march= to CFLAGS" >> $MAKECONF
echo "MAKEOPTS=\"-j$(nproc)\"" >> $MAKECONF
echo "EMERGE_DEFAULT_OPTS=\"\${EMERGE_DEFAULT_OPTS} --getbinpkg --jobs-tmpdir-require-free-gb=0\"" >> $MAKECONF
echo "FEATURES=\"parallel-fetch buildpkg parallel-install -ebuild-locks\"" >> $MAKECONF
echo "USE=\"\${USE} -X iproute2 logrotate snmp\"" >> $MAKECONF

grep -q autoinstall /proc/cmdline || nano $MAKECONF

echo "keymap=\"$KEYMAP\"" >> etc/conf.d/keymaps

echo "rc_logger=\"YES\"" >> etc/rc.conf
echo "rc_sys=\"\"" >> etc/rc.conf

cat > etc/conf.d/net << EOF
# https://wiki.gentoo.org/wiki/Netifrc/Brctl_Migration
config_br0="dhcp"
bridge_br0="eth0"
bridge_forward_delay_br0=0
bridge_stp_state_br0=0
dhcp_br0="nodns nontp nonis nosendhost"

#config_br0="192.168.0.251/24"
#routes_br0="default via 192.168.0.254 table default"

config_eth0="null"
rc_net_br0_need="net.eth0"

config_eth1="null"
bridge_br1="eth1"

config_br1="10.100.1.254/24"
bridge_forward_delay_br1=0
bridge_stp_state_br1=0

vlans_eth1="101 120 140"
config_eth1_101="null"
config_eth1_120="10.100.20.254/24"
config_eth1_140="10.100.40.254/24"


tuntap_vpnUA="tap"
#keep same MAC
mac_vpnUA="00:14:0A:01:64:65"
rc_before_vpnUA="openvpn.vpnua"
config_vpnUA="10.1.100.101/24"
routes_vpnUA="10.100.0.0/16 via 10.1.100.1"
EOF
grep -q autoinstall /proc/cmdline || nano etc/conf.d/net

pcimodules=$(lspci -k | grep -e "Kernel driver in use:" -e "Kernel modules:" | sed 's/.*: //' | tr '_,[:upper:]' '-\n[:lower:]' | sort -u)
usbmodules=$(usb-devices | grep -i "Driver=" | sed 's/.*iver=//' | tr '_,[:upper:]' '-\n[:lower:]' | grep -v "(none)" | sort -u | sed '/^hub$/d')

prebuild_setup() {
mount /var/tmp
mount /var/tmp -o remount,size=$(awk '/^(MemTotal|SwapTotal):/ {sum+=$2} END {printf "%.0fM", sum/1024}' /proc/meminfo)

vardb=/var/db
. ./portagehelper.sh || bash
chown -R portage:portage /etc/portage/gnupg; chmod u=rwx,go=rx /etc/portage/gnupg
ensure_snapshot_fstab
getuto &

# fix for new mtab init
ln -snf /proc/self/mounts /etc/mtab

mkdir -p /etc/portage/repos.conf \
  /etc/portage/package.accept_keywords \
  /etc/portage/package.use \
  /etc/portage/package.mask \
  /etc/portage/package.accept_keywords \
  /etc/portage/package.use \
  /etc/udev/rules.d/ \
  /tftproot
grep -qr gentoo-sources /etc/portage/package.accept_keywords/ || echo sys-kernel/gentoo-sources > /etc/portage/package.accept_keywords/kernel &
grep -qr net-dns/bind /etc/portage/package.use/ || echo net-dns/bind dlz caps threads >> /etc/portage/package.use/bind &
echo touch to disable the unpredictable "PredictableNetworkInterfaceNames"
touch /etc/udev/rules.d/80-net-name-slot.rules &
touch /etc/udev/rules.d/80-net-setup-link.rules &
touch /var/db/ntp-kod &
[ -f /etc/portage/package.mask/gentoo.conf ] || cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
ln -fs /usr/share/zoneinfo/$TIMEZONE /etc/localtime

if grep -q apcupsd <<< "${PACKAGES_POST[*]}"; then
    #snmp support in current apcupsd is buggy
    grep -qr sys-power/apcupsd /etc/portage/package.use/ || echo sys-power/apcupsd -snmp >> /etc/portage/package.use/apcupsd &
    # apcupsd requires wall which is included in util-linux iif tty-helpers is set
    grep -qr sys-apps/util-linux /etc/portage/package.use/ || echo sys-apps/util-linux tty-helpers >> /etc/portage/package.use/apcupsd &
fi
echo app-admin/syslog-ng -snmp >> /etc/portage/package.use/syslog-ng &
grep -qr net-firewall/nftables /etc/portage/package.use/ || echo net-firewall/nftables json python xtables >> /etc/portage/package.use/nftables &
grep -qr net-analyzer/net-snmp /etc/portage/package.use/ || echo net-analyzer/net-snmp lm-sensors >> /etc/portage/package.use/net-snmp &
grep -qr sys-kernel/installkernel /etc/portage/package.use/ || echo sys-kernel/installkernel grub >> /etc/portage/package.use/grub &
grep -q nvme-cli <<< "${PACKAGES_KRNL[*]}" && echo sys-apps/nvme-cli > /etc/portage/package.accept_keywords/nvme &
}

initial_emerge() {
wait
time emerge -uvN1 -j8 --keep-going y "${PACKAGES_INIT[@]}" || bash
}
initial_postemerge_setup() {
emerge -fq "${PACKAGES_PREFETCH[@]}" > /dev/null &
chronyd -q -t 60 <<< "
server $NTPSERVER iburst maxsamples 1
makestep 0.1 -1
" 2>&1 | grep clock &

#add new CPU_FLAGS_X86
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpuflags
}

up2date_emerge() {
#start out with being up2date
#we expect that this can fail, but for up2date stage3 almost no builds other than cpuflag updates
time emerge -uvDN1 -j8 --keep-going y @world --exclude gcc glibc --binpkg-respect-use=y
etc-update --automode -5
}

kernel_emerge() {
wait
time emerge -uv -j8 "${PACKAGES_KRNL[@]}" || bash
}

set_kconfig() {
    (
    { set +x; } 2>/dev/null
    # symbol gets everything before the =, and value everything after
    local symbol="${1%%=*}"
    local value="${1#*=}"
    # keep a separate lock to avoid race issues
    exec 9>>.config.lock
    flock -x 9
    # update symbol if it exists, or append it to end
    sed -i -E "/^#? *${symbol}[= ]/{s|.*|${symbol}=${value}|;:a;n;ba};\$a${symbol}=${value}" .config
    flock -u 9
    exec 9>&-
    )
}

get_kernel_config() {
lspci
lsusb
eselect kernel set 1
cd /usr/src/linux
#getting a base kernel config
curl -L ${GHBASEURL}/krn330.conf > .config
(
    { set +x; } 2>/dev/null
    while read -r line; do
        # Strip whitespace
        line="${line##+([[:space:]])}"
        line="${line%%+([[:space:]])}"

        # only lines that are not empty, not comment and has =
        [ -n "$line" ] && [[ "$line" != \#* ]] && [[ "$line" == *=* ]] && echo "+ set_kconfig $line" >&2 && set_kconfig "$line"
done << EOF
# Gentoo Linux
CONFIG_GENTOO_LINUX=y
CONFIG_GENTOO_LINUX_UDEV=y
CONFIG_GENTOO_LINUX_INIT_SCRIPT=y
CONFIG_SQUASHFS=m
CONFIG_SQUASHFS_XZ=y

CONFIG_TRACEPOINTS=y
CONFIG_FTRACE=y
CONFIG_BLK_DEV_IO_TRACE=y
CONFIG_TRACING=y

# Modern USB
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_SIDEBAND=y
CONFIG_USB_OHCI_HCD=m
CONFIG_USBIP_CORE=m
CONFIG_USBIP_VHCI_HCD=m
CONFIG_USBIP_HOST=m
CONFIG_USB_ACM=m
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_SIMPLE=m
CONFIG_USB_SERIAL_CP210X=m
CONFIG_USB_SERIAL_FTDI_SIO=m
CONFIG_USB_SERIAL_OPTION=m

#Mouse modules
CONFIG_INPUT_MOUSEDEV=m
CONFIG_MOUSE_PS2=m
CONFIG_MOUSE_SYNAPTICS_I2C=m
CONFIG_MOUSE_SYNAPTICS_USB=m
CONFIG_HID_RMI=m
CONFIG_RMI4_CORE=m
CONFIG_RMI4_I2C=m
CONFIG_RMI4_SPI=m
CONFIG_RMI4_SMB=m
CONFIG_RMI4_F03=y
CONFIG_RMI4_F03_SERIO=m
CONFIG_RMI4_2D_SENSOR=y
CONFIG_RMI4_F11=y
CONFIG_RMI4_F12=y
CONFIG_RMI4_F1A=y
CONFIG_RMI4_F21=y
CONFIG_RMI4_F30=y
CONFIG_RMI4_F34=y
CONFIG_RMI4_F3A=y
CONFIG_RMI4_F55=y

#fix hotplug (vmware)
CONFIG_HOTPLUG_PCI_SHPC=y
#no use for sound in virtual machine
CONFIG_SOUND=n
#scsi support vmware but also intel sas card
CONFIG_FUSION=y
#CONFIG_FUSION_SPI=y
#CONFIG_FUSION_FC=y
#CONFIG_FUSION_SAS=y
CONFIG_FUSION_CTL=m
#vmware -only- scsi
#CONFIG_VMWARE_PVSCSI=y
#CONFIG_SCSI_BUSLOGIC=y
#CONFIG_SCSI_SYM53C8XX_2=y
#CONFIG_I2C_PIIX4=y
CONFIG_SCSI_DH=y
CONFIG_FSCACHE=y
#vmware ensure network
CONFIG_VMXNET3=m
CONFIG_NET_VENDOR_AMD=y
CONFIG_PCNET32=m
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=m
CONFIG_E1000E=y
CONFIG_IGB=m
CONFIG_IGBVF=m
CONFIG_NLMON=y
CONFIG_R8169=m
#KVM/XEN Virtio
CONFIG_VIRTIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_BLK_SCSI=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_INPUT=y
CONFIG_VIRTIO_MMIO=m
#ups support...
CONFIG_HIDRAW=y
#iotop stuff
CONFIG_TASK_IO_ACCOUNTING=y
CONFIG_TASK_DELAY_ACCT=y
CONFIG_TASKSTATS=y
CONFIG_VM_EVENT_COUNTERS=y
#qemu kvm_stat need
CONFIG_DEBUG_FS=y

CONFIG_HYPERVISOR_GUEST=y
CONFIG_PARAVIRT=y
CONFIG_PARAVIRT_SPINLOCKS=y
CONFIG_KVM_GUEST=y
CONFIG_PARAVIRT_TIME_ACCOUNTING=y
CONFIG_VIRTIO_RTC=y

# optimize kernel compression for speed
CONFIG_X86_NATIVE_CPU=y
# unset GZIP
CONFIG_KERNEL_GZIP=n
CONFIG_KERNEL_LZ4=y
CONFIG_DMI_SYSFS=m
CONFIG_SOFT_WATCHDOG=m
CONFIG_IT87_WDT=m
CONFIG_INTEL_OC_WATCHDOG=m
CONFIG_INTEL_MEI_WDT=m
CONFIG_IPMI_SI=m
CONFIG_IPMI_SSIF=m
CONFIG_IPMI_WATCHDOG=m
CONFIG_IPMI_POWEROFF=m
CONFIG_IPMI_HANDLER=m
CONFIG_TCG_TPM=m
CONFIG_NFS_FS=m
CONFIG_NFSD=m
CONFIG_SMB_SERVER=m
CONFIG_FW_LOADER_COMPRESS=y
CONFIG_FW_LOADER_COMPRESS_XZ=y
CONFIG_EFI_CAPSULE_LOADER=m

# use old vesa, vga= mode
CONFIG_FB_VESA=y
# and make uvesafb a module instead
CONFIG_FB_UVESA=m

# make sure the kernel supports EFI boot
CONFIG_EFI_STUB=y
CONFIG_FB_EFI=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_DRM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FB_SIMPLE=y
CONFIG_FB_FOREIGN_ENDIAN=y
CONFIG_FB_TILEBLITTING=y
# DEFERRED_TAKEOVER hides penguins
#CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y
CONFIG_EFI_BOOTLOADER_CONTROL=m
CONFIG_EFI_RCI2_TABLE=y

# New Netfilter (to get iptables nat working)
CONFIG_NF_TABLES=m
CONFIG_NFT_MASQ=m
CONFIG_NFT_REDIR=m
CONFIG_NFT_NAT=m
CONFIG_NFT_COMPAT=m
CONFIG_NETFILTER_XT_NAT=m
CONFIG_NETFILTER_XT_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV4=y
CONFIG_NFT_CHAIN_ROUTE_IPV4=m
CONFIG_NF_NAT_IPV4=m
CONFIG_NFT_CHAIN_NAT_IPV4=m
CONFIG_NF_NAT_MASQUERADE_IPV4=m
CONFIG_NFT_MASQ_IPV4=m
CONFIG_NFT_REDIR_IPV4=m
CONFIG_IP_NF_NAT=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_CHAIN_ROUTE_IPV6=m
CONFIG_IPV6_SIT=m
CONFIG_NF_CT_NETLINK_HELPER=m
CONFIG_NF_CT_NETLINK_TIMEOUT=m

CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_IPV6_TUNNEL=m
CONFIG_BONDING=m
CONFIG_WIREGUARD=m
CONFIG_OVPN=m
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m
CONFIG_VXLAN=m
CONFIG_TUN=m
CONFIG_VETH=m
CONFIG_VLAN_8021Q=m

CONFIG_NET_SCH_QFQ=m
CONFIG_NET_SCH_CODEL=m
CONFIG_NET_SCH_FQ_CODEL=m

# if we have nvme hardware
${NVMEKERNEL}

# Serial console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_DEPRECATED_OPTIONS=n

# Include some stuff to simplify for iwd
CONFIG_RFKILL=m
CONFIG_ASYMMETRIC_KEY_TYPE=y
CONFIG_ASYMMETRIC_PUBLIC_KEY_SUBTYPE=y
CONFIG_KEY_DH_OPERATIONS=y
CONFIG_PKCS7_MESSAGE_PARSER=y
CONFIG_PKCS8_PRIVATE_KEY_PARSER=y
CONFIG_X509_CERTIFICATE_PARSER=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_CRYPTO_RSA=y
CONFIG_CRYPTO_DES3_EDE_X86_64=y
CONFIG_CRYPTO_SHA1_SSSE3=y
CONFIG_CRYPTO_SHA256_SSSE3=y
CONFIG_CRYPTO_SHA512_SSSE3=y

# XATTR and ACL enable
CONFIG_EXT2_FS_XATTR=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
)

# Cleanup some invalid options
sed -i \
  -e "/^CONFIG_BASE_SMALL=0/d" \
  -e '/^CONFIG_NF_CT_PROTO_GRE/s/=m/=y/' \
  -e '/^CONFIG_NF_CT_PROTO_SCTP/s/=m/=y/' \
  .config

DISK_COUNT=$(readlink -f /sys/block/[sv]d* 2>/dev/null | grep -v "usb" | wc -l)
if [ "$DISK_COUNT" -le 1 ]; then
    echo "Single disk detected. change MD/RAID to modules"
    set_kconfig "CONFIG_BLK_DEV_MD=m"
    set_kconfig "CONFIG_MD_RAID=m"
fi

# Remove old low CPU core count
sed -i "/^CONFIG_NR_CPUS=.*$/d" .config

# v86d is dead so remove its initramfs
sed -i 's#/usr/share/v86d/initramfs##' .config

# Add missing PCI/USB config options
SEARCH_PATHS="/usr/src/linux/drivers/ /usr/src/linux/arch/x86/"
drvstocheck=$(echo -e "$pcimodules\n$usbmodules\n$(lspci -k | grep -e "Kernel driver in use:" -e "Kernel modules:" | sed 's/.*: //' | tr '_,[:upper:]' '-\n[:lower:]' | sort -u)" | sort -u)
for drv in $drvstocheck; do
    set_kconfig_by_module "$drv" &
done
wait
rm .config.lock

echo -e "x\ny\n" | make menuconfig > /dev/null
}
set_kconfig_by_module() {
    (
    { set +x; } 2>/dev/null
    local drv="$1"
    SYMBOL=$(find /usr/src/linux/ -name "Makefile" -exec grep "[[:space:]]*=[[:space:]]*${drv/-/.}\.o" {} \; | sed -En "s/.*(CONFIG_[A-Z0-9_]*).*/\1/p")

    # Search for the DRV_NAME string in .c files
    if [ -z "$SYMBOL" ]; then
        SRC_FILE=$(grep -rlE "(\.name[[:space:]]*=[[:space:]]*\"|#define DRV_NAME[[:space:]]*\"|MODULE_ALIAS.*)${drv/-/.}\"" $SEARCH_PATHS | head -n 1)
        if [ -n "$SRC_FILE" ]; then
            OBJ_NAME=$(basename "$SRC_FILE" .c).o
            DIR_PATH=$(dirname "$SRC_FILE")
            SYMBOL=$(grep -E "obj-\\$\(CONFIG_[A-Z0-9_]+\)[[:space:]]*[:+]=.*[[:space:]]${OBJ_NAME}" "$DIR_PATH/Makefile" | sed -n 's/.*\(CONFIG_[A-Z0-9_]*\).*/\1/p')

            if [ -z "$SYMBOL" ]; then
                VAR_NAME=$(grep -E "[:+]=.*[[:space:]]${OBJ_NAME}" "$DIR_PATH/Makefile" | cut -d'=' -f1 | tr -d ' \t+:'| sed -E 's/-(y|m|objs)$//')
                [ -n "$VAR_NAME" ] && SYMBOL=$(grep -E "obj-\\$\(CONFIG_[A-Z0-9_]+\)[[:space:]]*[:+]=.*[[:space:]]${VAR_NAME}.o" "$DIR_PATH/Makefile" | sed -n 's/.*\(CONFIG_[A-Z0-9_]*\).*/\1/p')
            fi
        fi
        if [ -z "$SYMBOL" ]; then
            echo "Searching for $drv not found"
            continue
        fi
    fi

    [[ "$SYMBOL" =~ "USB" || " $usbmodules " =~ [[:space:]]${drv}[[:space:]] ]] && ASSIGN=m || ASSIGN=y
    wait
    echo "+ set_kconfig ${SYMBOL}=$ASSIGN  # For module $drv" >&2
    set_kconfig "${SYMBOL}=$ASSIGN"
    )
}

setup_grub() {
# Prepare grub config since grub-mkconfig runs as part of make install, will re-run after some further changes
sed -i 's/^#GRUB_DISABLE_LINUX_UUID=[a-z]+/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sed -i 's/^#GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="rootfstype=ext4 net.ifnames=0 panic=30"/' /etc/default/grub
[ ! -d /sys/firmware/efi ] && sed -i 's/panic=30/panic=30 vga=791/' /etc/default/grub
sed -i 's/^#*GRUB_TIMEOUT=[0-9]+/GRUB_TIMEOUT=3/' /etc/default/grub
# Drop graphics in grub, with below 2 changes load_video is never called, at least not in grub 2.14-r4
sed -i 's/^#GRUB_TERMINAL=.*/GRUB_TERMINAL=console/' /etc/default/grub
sed -i 's/^#GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX=text/' /etc/default/grub
echo "# replicate the old GRUB_LINUX_KERNEL_GLOBS" >> /etc/default/grub
echo "sed -i 's|/boot/vmlinuz-\*|/boot/vmlinuz /boot/vmlinuz.old|' /etc/grub.d/10_linux" >> /etc/default/grub
pushd /boot
# create a dummy link
ln -s vmlinuz-1.1 vmlinuz
popd
curl --parallel \
    -L https://boot.ipxe.org/x86_64-efi/ipxe-legacy.efi -o /boot/efi/EFI/BOOT/ipxex64.efi \
    -L https://raw.githubusercontent.com/tianocore/edk2-archive/refs/heads/master/ShellBinPkg/UefiShell/X64/Shell.efi -o /boot/efi/EFI/BOOT/shellx64.efi \
    $( [ -f /etc/grub.d/39_efitools ] || echo "-L ${GHBASEURL}/grub.d/39_efitools -o /etc/grub.d/39_efitools" )
sha512sum -c <<<"cae63738889e626906270c6ad853970340d83044363680db97a70fdc8b6ec7960ba9ea7553afaf79bd8b64a61800ecf782742509e9e84d1c60b1e1e6de9d5346  /etc/grub.d/39_efitools" || bash
chmod a+x /etc/grub.d/39_efitools
grub-install --target=x86_64-efi --efi-directory=/boot/efi ${IDEV}
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable ${IDEV}
grub-install --target=i386-pc ${IDEV}
  if grep -q console= /proc/cmdline; then
    sed -i 's/ panic=30/ panic=30 console=tty0 console=ttyS0,115200/' /etc/default/grub
    sed -i 's/^#GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
    echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0"' >> /etc/default/grub
    # enable serial in inittab
    sed -i 's/^#s0:/s0:/' /etc/inittab
  fi
}

make_kernel() {
# 6000 is rough estimate of how many lines we usually get for a compile --dry-run unfortunatly failed
  time (
    pv -lbtpef -s $(bc <<< "scale=0; ($(grep -c "=[ym]" .config) * 28) / 10") > /dev/null < <(make -j$(($(nproc)*2)) bzImage modules) && \
    pv -lbtpef -s $((6+$(find -name "*.ko" | wc -l))) > /dev/null < <(make -j2 modules_install install)
    ) || bash
rm /boot/vmlinuz.old
ls -lh /boot

  make install
ls -lh /boot; find /boot/efi; efibootmgr
}

postkernel_emerge() {
time emerge -uv -j8 --keep-going y "${PACKAGES_POST[@]}" || bash
}

postbuild_configure() {
cd /etc
etc-update --automode -5
sed -i 's/^#CHROOT=/CHROOT=/' /etc/conf.d/named
emerge --config net-dns/bind
find /chroot/dns
rc-update add named default
#TODO sed fix syslog unix-stream("/chroot/dns/dev/log");
sed -i 's/^# DHCPD_CHROOT=/DHCPD_CHROOT=/' /etc/conf.d/dhcpd
#TODO syslog unix-stream("...dhcp");
dispatch-conf

#todo fix with sed ... but virtual machine dont save clock ;)
#/etc/init.d/hwclock save
sed -i 's/^c1:12345:respawn:\/sbin\/agetty .* tty1 linux$/& --noclear/' /etc/inittab || bash
cd /etc/init.d
ln -s net.lo net.eth0
ln -s net.lo net.br0
rc-update add net.br0 default
rc-update add watchdog boot
rc-update add syslog-ng default
rc-update add *cron* default
sed -i 's#^\#INTFTPD_PATH="/tftproot/"#INTFTPD_PATH="/tftproot/"#' /etc/conf.d/in.tftpd
rc-update add in.tftpd default
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
rc-update add sshd default
rc-update delete netmount

# Start creating fix script
echo # Remove udev rules that make network interface names compleatly unpredictable and unmanagable. > /etc/local.d/remove.net.rules.start
echo setterm -blank 0 >> /etc/local.d/remove.net.rules.start
echo rm -rf /usr/lib/udev/rules.d/80-net-name-slot.rules >> /etc/local.d/remove.net.rules.start
echo rm -rf /usr/lib/udev/rules.d/80-net-setup-link.rules >> /etc/local.d/remove.net.rules.start
# Make it executable, and run also on shutdown
chmod a+x /etc/local.d/remove.net.rules.start
ln -fs /etc/local.d/remove.net.rules.start /etc/local.d/remove.net.rules.stop
rc-update add local default
# run it now and add clean exit (rm will fail if there is no file so always exit with ok)
sh /etc/local.d/remove.net.rules.start
echo exit 0 >> /etc/local.d/remove.net.rules.start

sed -i 's/^smtp.*inet/#&/' /etc/postfix/master.cf
rc-update add postfix default
echo -e "# Use newaliases after change\nroot:           $ROOTEMAIL" >> /etc/mail/aliases
newaliases

# TODO detect if username should be included or not
#sed -i 's/\troot\t/\t/' /etc/crontab
echo -e "*/30  *  * * *\troot\tchronyd -q -t 30 'server $NTPSERVER iburst' > /dev/null" >> /etc/crontab
# some variants of cron needs to have default cron installed
#crontab /etc/crontab

[[ -f /etc/init.d/apcupsd ]] && rc-update add apcupsd default && rc-update add apcupsd.powerfail shutdown
#todo configure snmp and add to startup

#todo... if vmware emerge open-vm-tools?
}

use_git_portage() {
# move to git based portage tree
time emerge -j2 app-eselect/eselect-repository
umount /var/db/repos/gentoo
rm -rf /var/db/snapshots
 # https://wiki.gentoo.org/wiki/Portage_with_Git
eselect repository disable gentoo
eselect repository enable gentoo
#sed -i 's#sync-uri = .*#sync-uri = git://anongit.gentoo.org/repo/gentoo.git#' /etc/portage/repos.conf/eselect-repo.conf
emerge --sync
}

generate_chroot_script() {
  cat << EOF
env-update
source /etc/profile
echo "root:${SET_PASS}" | chpasswd -c BCRYPT
EOF
  declare -p \
    TIMEZONE NTPSERVER GHBASEURL \
    PACKAGES_INIT PACKAGES_PREFETCH PACKAGES_KRNL PACKAGES_POST \
    NVMEKERNEL pcimodules usbmodules \
    IDEV ROOTEMAIL
  declare -f \
    prebuild_setup \
    initial_emerge \
    initial_postemerge_setup \
    up2date_emerge \
    kernel_emerge \
    set_kconfig \
    set_kconfig_by_module \
    get_kernel_config \
    setup_grub \
    make_kernel \
    postkernel_emerge \
    postbuild_configure
  cat << EOF
set -x
prebuild_setup
initial_emerge
initial_postemerge_setup
up2date_emerge
kernel_emerge
get_kernel_config
setup_grub
make_kernel
postkernel_emerge
postbuild_configure
EOF

if (grep -q usegitportage /proc/cmdline); then
    declare -f use_git_portage
    echo "use_git_portage"
fi
}
generate_chroot_script > chrootstart.sh
time chroot . /bin/bash chrootstart.sh
rm chrootstart.sh
# Delete temporary change to avoid insufficient free space, emerge job parallelism reduced
sed -i 's/--jobs-tmpdir-require-free-gb=[0-9]\+ \?//g' $MAKECONF

umount var/tmp/
rm -rf var/tmp/*
rm -rf var/cache/distfiles
cd
umount -R /mnt/gentoo || umount -lR /mnt/gentoo || exit 1
# halt in QEMU guest instead of reboot to messure and autohandle on vm shutdown
grep -q setupdonehalt /proc/cmdline && halt || reboot
