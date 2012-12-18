cat >> /newroot/root/.bashrc << EOF
if [ "\$(hostname)" == "livecd" ] && (tty | grep -q tty1\\$)
then
  hostname gtestinst
  ip link set eth0 up && sleep 2
  dhcpcd
  wget https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh -O g-install.sh
  echo We just downloaded g-install.sh that can be used to make a install...
  echo maybe fix somethings like passwd before continue?
  grep autoinstall /proc/cmdline && sh g-install.sh
fi
EOF
