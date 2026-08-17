# this will be put in place by Dracut
echo -n "Cmdline: "
cat /proc/cmdline

if [ "$(hostname)" == "livecd" ] && (tty | grep -q -e tty1\$ -e ttyS0\$)
then
  # NetworkManager should pick up and apply this change
  echo hostname=gtestinst > /etc/conf.d/hostname
  setterm -blank 0 2>/dev/null
  #IF NOT SET_PASS is set then the password will be "password"
  SET_PASS=${SET_PASS:-password}
  echo "root:${SET_PASS}" | chpasswd -c BCRYPT

  /etc/init.d/sshd -q start &
  # ensure everything is up or wait, the (Un)PredictableNetworkInterfaceNames Madness ...
  while : ; do
    # ping does not work in QEMU default network, su use http get instead.
    curl -s raw.githubusercontent.com > /dev/null && break
    ping -c 1 raw.githubusercontent.com && break
    sleep 2
    ip a
  done
  COLORFGBG=";0" ip --color -br a
  # Try to update to a correct system time
  chronyd -q 'server ntp.se iburst' &
  if [ ! -f g-install.sh ]; then
    wget https://raw.githubusercontent.com/ASoft-se/Gentoo-HAI/master/install.sh? -O g-install.sh
    echo We just downloaded g-install.sh that can be used to make a install...
  fi
  wait
  grep -q autoinstall /proc/cmdline && sh g-install.sh
fi
