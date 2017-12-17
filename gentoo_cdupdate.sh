#!/bin/sh
[ -f /mnt/cdrom/g-install.sh ] && cp /mnt/cdrom/g-install.sh root/

cat >> /newroot/root/.bashrc << EOF
if [ "\$(hostname)" == "livecd" ] && (tty | grep -q tty1\\$)
then
  setterm -blank 0
  hostname gtestinst
  #IF NOT SET_PASS is set then the password will be "password"
  SET_PASS=\${SET_PASS:-password}
  echo -e "\${SET_PASS}\n\${SET_PASS}\n" | passwd

  ip link set eth0 up && sleep 2
  dhcpcd
  /etc/init.d/sshd start &
  # wait a bit for everything to come up, and oh the (Un)PredictableNetworkInterfaceNames Madness will make sure eth0 above no longer works.
  while : ; do
    # ping does not work in QEMU default network, su use http get instead.
    curl -q raw.github.com > /dev/null && break
    ping -c 1 raw.github.com && break
    sleep 2
  done
  # Try to update to a correct system time
  ntpdate ntp.se &
  [ -f g-install.sh ] || wget https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh? -O g-install.sh
  echo We just downloaded g-install.sh that can be used to make a install...
  echo maybe fix somethings like passwd before continue?
  grep -q autoinstall /proc/cmdline && sh g-install.sh
fi
EOF
