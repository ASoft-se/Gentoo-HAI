#!/bin/bash
echo $0 Got arguments: $*
netscript="-nic user,model=virtio"

DISK=kvm_lxgentootest.qcow2
disktype="
-device virtio-blk-pci,drive=d1
"
disktypeahci="
-device ahci,id=ahci
-device ide-hd,drive=d1,bus=ahci.0
"

USEEFI=""
VNC="-vnc 127.0.0.1:22 -k sv"
VGA=""
memorygb=2
POSITIONAL=()
while (($#)); do
  case $1 in
  -netdev)
# use -netdev argument to create and add that as interface to existing br0 for example: -netdev tapKVMLx0
shift
netdev=$1
echo If you havent already, you should run the below as root
echo   ip tuntap add dev $netdev mode tap user $USER
echo   ip link set dev $netdev up master br0
netscript="
-net nic,macaddr=52:54:00:53:27:00,model=e1000
-net tap,script=no,downscript=no,ifname=$netdev
"
  ;;
  useefi)
    USEEFI=YES
    cp /usr/share/edk2-ovmf/OVMF_VARS.fd kvm_lxgentootest_VARS.fd
    #efibios="-smbios type=0,uefi=on -bios /usr/share/edk2-ovmf/OVMF_CODE.fd"
    efibios="-drive if=pflash,unit=0,format=raw,readonly=on,file=/usr/share/edk2-ovmf/OVMF_CODE.fd \
      -drive if=pflash,unit=1,format=raw,file=kvm_lxgentootest_VARS.fd"
  ;;
  usenvme)
    disktype="-device nvme,drive=d1,id=nvme1,serial=nonoptionalsn001"
  ;;
  auto)
    echo "using -nographic, Ctrl+A, X exits"
    VNC=""
    VGA="-nographic"
  ;;
  -cdrom)
    shift
    POSITIONAL+=("-drive file=$1,if=none,media=cdrom,id=cd1 -device ahci,id=achi0 -device ide-cd,bus=achi0.0,drive=cd1")
  ;;
  -m)
    shift
    echo "Set memory to $1 gb"
    memorygb=$1
  ;;
  *)
    POSITIONAL+=("$1") # save it in an array for later
  ;;
  esac
  shift
done
set -- "${POSITIONAL[@]}" # restore positional parameters

#VGA="-nographic -device sga"
#VGA="-nographic"
#VGA="-curses"
[[ "$USEEFI" != "YES" ]] && [[ "$VGA" == "" ]] && VGA="-vga vmware"

# Create interface however you want to.
# Recommendation to use a local proxy (ex squid) and transparent http redirection to save bandwidth
# ex iptables transparent proxy:  iptables -t nat -A PREROUTING -i br0 -p tcp --dport 80 -j REDIRECT --to-port 3128

# start with -cdrom install-amd64-mod.iso to boot from livecd
# TODO auto handle inc of mac netdev and vnc port

[ ! -f $DISK ] && qemu-img create -f qcow2 $DISK 20G

[[ "$VNC" != "" ]] && (sleep 3; vncviewer :22) &

set -x
jn=$(($(nproc)/2))
qemu-system-x86_64 -enable-kvm -M q35 -m $(($memorygb*1024)) -cpu host -smp $jn,cores=$jn,sockets=1 -name lxgentootest \
-drive id=d1,file=$DISK,format=qcow2,if=none,media=disk,cache=unsafe \
${disktype} \
$netscript \
-device i6300esb -action watchdog=reset \
-usb ${VGA} ${VNC} \
${efibios} \
$*

# Extra lines to add if using multiple disks with ahci
#-drive id=d2,file=kvm_lx2.img,if=none,media=disk,index=3,cache=writeback \
#-device ide-drive,drive=d2,bus=ahci.1 \

#IDE version if ahci is problematic
#-device ide-hd,drive=d1,bus=ide.0 \
