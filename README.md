# Gentoo-HAI

Gentoo - Headless Auto Installer, Perfect for initial Gentoo (server) setup.
(hai also becomes a phun in Japanese)

Use a livecd and manually download https://tinyurl.com/gto-hai (https://raw.githubusercontent.com/ASoft-se/Gentoo-HAI/master/install.sh)
and run it to make the installation..
##### Example:
```bash
wget tinyurl.com/gto-hai -O install.sh
sh install.sh
```
Please check the script for settings and optimizions that can be done.

* `list_latest.sh`		Grab name of latest iso and stage3
* `get_minimal_cd.sh`		Download and verify latest minimal livecd
* `gentoocd_unpack.sh`		Unpacks and creates .ipxe script for testing
* cdhelpers / `gentoo_cd_bashrc_addon` and `cdupdate.sh`		Added to modified livecd by gentoocd_unpack, runs on logon (genkernel cds)
* `updates/root/.bashrc`		Injected and runs at login (Dracut) replaces `gentoo_cd_bashrc_addon`

* `install.sh`			Main Installation script
* `test_w_qemu.sh`		Virtual test machine helper, see script for some additional setup instructions and information

Run `./gentoocd_unpack.sh` to unpack parts of iso (follow will tell what to do if no .iso is found)
It adds script to cd start that runs the install automatically.

### To make testing simple
For testing, give `rm kvm_lxgentootest.qcow2; time sh test_w_qemu.sh auto useefi usenvme` a try.
When testing disk images will be recrated, so copy them to a safe place if you want to keep them.
