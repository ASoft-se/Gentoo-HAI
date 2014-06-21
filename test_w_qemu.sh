#tunctl -b -u $USER -t tapKVMLx0
#brctl addif br0 tapKVMLx0
#ip link set up tapKVMLx0
# Create interface however you want to.
# Recommendation to use a local proxy (ex squid) and transparent http redirection to save bandwidth
# ex iptables transparent proxy:  iptables -t nat -A PREROUTING -i br0 -p tcp --dport 80 -j REDIRECT --to-port 3128

# start with -cdrom install-amd64-mod.iso to boot from livecd

DISK=kvm_lxgentootest.img
[ ! -f $DISK ] && qemu-img create $DISK 20G
qemu-system-x86_64 -machine accel=kvm -enable-kvm -m 2048 -smp 4,cores=4,sockets=1 -name lxgentootest \
-drive id=d1,file=$DISK,if=none,media=disk,index=1,cache=writeback \
-device ahci,id=ahci \
-device ide-drive,drive=d1,bus=ahci.0 \
-net nic,macaddr=52:54:00:53:27:00,vlan=0,model=e1000 \
-net tap,script=no,downscript=no,vlan=0,ifname=tapKVMLx0 \
-watchdog i6300esb -watchdog-action reset \
-usb -vga vmware -vnc 127.0.0.1:22 -k sv $*

# Extra lines to add if using multiple disks with ahci
#-drive id=d2,file=kvm_lx2.img,if=none,media=disk,index=3,cache=writeback \
#-device ide-drive,drive=d2,bus=ahci.1 \
