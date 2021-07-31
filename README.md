# Gentoo-HAI

Gentoo - Headless Auto Installer, Perfect for initial Gentoo (server) setup.
(hai also becomes a phun in Japanese)

Use a livecd and manually download http://goo.gl/5Y2Gj (https://raw.github.com/ASoft-se/Gentoo-HAI/master/install.sh)
and run it to make the installation..
##### Example:
```bash
wget goo.gl/5Y2Gj -O install.sh
sh install.sh
```
Please check the script for settings and optimizions that can be done.

* `list_latest.sh`		Grab name of latest iso and stage3
* `get_minimal_cd.sh`		Download and verify latest minimal livecd
* `gentoocd_unpack.sh`		Unpacks and modifies livecd, adding auto run install script on boot/logon
* `gentoo_cd_bashrc_addon`/`gentoo_cdupdate.sh`		Added to modified livecd by gentoocd_unpack, runs on logon

* `install.sh`			Main Installation script
* `test_w_qemu.sh`		Virtual test machine helper, see script for some additional setup instructions and information

Run `sh get_minimal_cd.sh` to download latest `install-amd64-minimal-*.iso`.
Run `sh gentoocd_unpack.sh` (unfortunatly requests root) to unpack iso and create `install-amd64-mod.iso`
It adds script to cd start that runs the install automatically.

Also give `sh gentoo_cdupdate.sh auto` a try if you want to test things out in a vm.

### To make testing simple
  modify and use `test_w_qemu.sh` to start qemu, Disk image is auto created if it does not already exist.
```bash
sh test_w_qemu.sh -cdrom install-amd64-mod.iso
```
When testing disk images will be recrated, so copy them to a safe place if you want to keep them.
