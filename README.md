Gentoo-HAI
==========

Headless Auto Install, Perfect for initial gentoo server setup.
(hai also becomes a phun in Japanese)

Use a livecd and manually download http://goo.gl/5Y2Gj (https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh)
and run it to make the installation..
Example:
```bash
wget goo.gl/5Y2Gj -O install.sh
sh install.sh
```
Please check the script for settings and optimizions that can be done.

Helper scripts to modify gentoo livecds to automate download and running of the installation.
For this to work the iso install-amd64-minimal-*.iso is needed.
run gentoocd_unpack.sh (as root unfortunatly) to unpack and create install-amd64-mod.iso. (gentoo_cdupdate.sh is added and runs on livecd boot).
On the modified livecd gentoo_cdupdate.sh will run on boot and modify the bash init script that changes hostname and starts the install if selected on boot.

To make testing simple modify and use test_w_qemu.sh to start qemu, Disk image is auto created if it does not allready exist.
  sh test_w_qemu.sh -cdrom install-amd64-mod.iso
when testing new install remove or move the old disk image.


TL;DR What are the purpuse of the files?
  get_minimal_cd.sh		Downloads the latest minimal livecd.
  gentoocd_unpack.sh		Unpacks and modifies livecd, adding auto run install script on boot/logon.
  gentoo_cdupdate.sh		Added to modified livecd by gentoocd_unpack, runs on logon.

  install.sh			Main Installation script.
  test_w_qemu.sh		Virtual test machine helper, see script for some additional setup instructions and information
