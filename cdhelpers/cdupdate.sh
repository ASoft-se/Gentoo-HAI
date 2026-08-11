
# we should be in newroot ${NEW_ROOT} and other nice things are unavailable
echo "  Running cdupdate.sh in $(pwd)"
echo "  Started as: $0 args: $*"

scriptpath=$(dirname $0)
echo " found scriptpath: ${scriptpath}"

echo " Update bashrc with gentoo_cd_bashrc_addon contents ..."
cat ${scriptpath}/gentoo_cd_bashrc_addon >> root/.bashrc
[ ! -f ${scriptpath}/g-install.sh ] || cp -v ${scriptpath}/g-install.sh root
[ ! -f ${scriptpath}/portagehelper.sh ] || cp -v ${scriptpath}/portagehelper.sh root
