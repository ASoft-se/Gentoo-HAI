Gentoo-HAI
==========

Headless Auto Install, Perfect for initial gentoo server setup.

Use a livecd and manually download http://goo.gl/5Y2Gj (https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh)
and run it to make the installation..
Example:
```bash
wget goo.gl/5Y2Gj -O install.sh
sh install.sh
```
Please check the script for settings and optimizions that can be done.

There is also scripts to modify gentoo livecds to automate download and running of the installation.
For this to work install-amd64-minimal-*.iso is needed. then run gentoocd_unpack.sh as root to unpack and create install-amd64-mod.iso with gentoo_cdupdate.sh added.
gentoo_cdupdate.sh will run on boot and modify the bash init script that changes hostname and starts the install if selected on boot.

To make testing simple modify and use test_w_qemu.sh to start qemu, when testing new install remove or move the disk image, that will auto create a new disk and run
  sh test_w_qemu.sh -cdrom install-amd64-mod.iso
