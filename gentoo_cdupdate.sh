setterm -blank 0
cat >> /newroot/root/.bashrc << EOF
if [ "\$(hostname)" == "livecd" ] && (tty | grep -q tty1\\$)
then
  hostname gtestinst
  ip link set eth0 up && sleep 2
  dhcpcd
  # wait a bit for everything to come up, and oh the (Un)PredictableNetworkInterfaceNames Madness will make sure eth0 above no longer works.
  while : ; do
    ping -c 1 raw.github.com && break
    sleep 2
  done
  wget https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh -O g-install.sh
  echo We just downloaded g-install.sh that can be used to make a install...
  echo maybe fix somethings like passwd before continue?
  grep autoinstall /proc/cmdline && sh g-install.sh
fi
EOF
