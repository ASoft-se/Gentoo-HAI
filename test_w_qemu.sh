netscript=
if [[ "$1" == "-netdev" ]]; then
# use -netdev argument to create and add that as interface to existing br0 for example: -netdev tapKVMLx0
shift
netdev=$1
echo If you havent already, you should run the below as root
echo   ip tuntap add dev $netdev mode tap user $USER
echo   ip link set dev $netdev up master br0
netscript="
-net nic,macaddr=52:54:00:53:27:00,vlan=0,model=e1000
-net tap,script=no,downscript=no,vlan=0,ifname=$netdev
"
shift
fi
# Create interface however you want to.
# Recommendation to use a local proxy (ex squid) and transparent http redirection to save bandwidth
# ex iptables transparent proxy:  iptables -t nat -A PREROUTING -i br0 -p tcp --dport 80 -j REDIRECT --to-port 3128

# start with -cdrom install-amd64-mod.iso to boot from livecd
# TODO auto handle inc of mac netdev and vnc port

DISK=kvm_lxgentootest.img
[ ! -f $DISK ] && qemu-img create -f qcow2 $DISK 20G

(sleep 3; vncviewer :22) &

qemu-system-x86_64 -enable-kvm -M q35 -m 2048 -cpu host -smp 4,cores=4,sockets=1 -name lxgentootest \
-drive id=d1,file=$DISK,format=qcow2,if=none,media=disk,index=1,cache=unsafe \
-device ahci,id=ahci \
-device ide-drive,drive=d1,bus=ahci.0 \
$netscript \
-watchdog i6300esb -watchdog-action reset \
-boot menu=on -usb -vga vmware -vnc 127.0.0.1:22 -k sv $*

# Extra lines to add if using multiple disks with ahci
#-drive id=d2,file=kvm_lx2.img,if=none,media=disk,index=3,cache=writeback \
#-device ide-drive,drive=d2,bus=ahci.1 \

#IDE version if ahci is problematic
#-device ide-hd,drive=d1,bus=ide.0 \
