#!/bin/bash
# Copyleft Christian I. Nilsson
# Please do what you want! Use on your own risk and all that!
#
# This is inteended to be sourced for function use
# or run for snapshot update
#
set -u
DISTMIRROR=${DISTMIRROR:-https://distfiles.gentoo.org}
TRUSTKEY=${TRUSTKEY:-ABD00913019D6354BA1D9A132839FE0D796198B1}
vardb=${vardb:-$PWD/var/db}
pathrepo=${pathrepo:-$vardb/repos/gentoo}
pathsnapshots=${pathsnapshots:-$vardb/snapshots}
cursqfs=gentoo-current.xz.sqfs

ensure_key_and_snap_source() {
  #https://github.com/ASoft-se/Gentoo-HAI/issues/72#issuecomment-2294998781
  shaurl=${DISTMIRROR}/snapshots/squashfs/sha512sum.txt
  [ "${1:-x}" == "nosnap" ] && shaurl=
  curl -L -C - --remote-name-all --parallel-immediate --parallel \
    https://qa-reports.gentoo.org/output/service-keys.gpg \
    $shaurl || return 1

  # gpg import, trust starting with Gentoo L1 signing key
  gpg -q \
    --trusted-key $TRUSTKEY \
    --import service-keys.gpg && rm service-keys.gpg
  #gpg --locate-key infrastructure@gentoo.org

  [ -z "$shaurl" ] && return 0
  # Validate sha512sum
  # WARNING: prepare for this file to change format in future to BSD-like tagged checksum
  expected_checksum_and_file=$(gpg \
    --trusted-key $TRUSTKEY \
    -o- \
    --verify sha512sum.txt | awk '/\<gentoo-[0-9]*\.xz\.sqfs/{l=$0}END{print l}') \
    && rm sha512sum.txt || return 1
  SNAPSHOT=${expected_checksum_and_file//* }
  EXPECTED512=${expected_checksum_and_file// *}
}

get_existing_target() {
  existingtarget=$cursqfs
  [ -f $pathsnapshots/$cursqfs ] && existingtarget=$( basename "$( readlink -f $pathsnapshots/$cursqfs )" )
  echo $existingtarget
}

update_snapshot() {
  [ -z "$SNAPSHOT" ] && return 1
  echo -e "\e[93mSnapshot  $SNAPSHOT ...\nExpecting SHA512 $EXPECTED512 ...\e[0m"
  curl -C - --remote-name-all "${DISTMIRROR}/snapshots/squashfs/$SNAPSHOT" || return 1
  snapshot512=$(sha512sum "$SNAPSHOT" | awk '{print $1}')

  echo -e -n "\e[93mSnapshot  SHA512 $snapshot512\e[0m"
  [ "$snapshot512" == "$EXPECTED512" ] && echo -e " \e[92;1m - OK\e[0m" || {
    echo -e " \e[91;1m - not matching\e[0m"
    return 1
  }

  [ -f "$pathsnapshots/$SNAPSHOT" ] && [ $(realpath "$SNAPSHOT") == $(realpath "$pathsnapshots/$SNAPSHOT") ] || mv "$SNAPSHOT" "$pathsnapshots/$SNAPSHOT"

  existingtarget=$(get_existing_target)
  [ "${existingtarget:-x}" == "$SNAPSHOT" ] && {
    echo -e "\e[92;1m - No update from $existingtarget\e[0m"
    return 0
  }
  echo -e "\e[93;1m - Previous target: $existingtarget new: $SNAPSHOT\e[0m"
  pushd $pathsnapshots > /dev/null
  ln -s -f $SNAPSHOT $cursqfs
  popd > /dev/null
}

ensure_snapshot_fstab() {
  grep $cursqfs /etc/fstab && return 0
  fstabline="$pathsnapshots/$cursqfs\t$pathrepo\tsquashfs\tro,user,loop,nodev,noexec\t0 0"
  echo -e "\e[95;1mDid not find $cursqfs in fstab, trying to add ...\n\e[95;0m$fstabline\e[0m"
  echo -e "$fstabline" >> /etc/fstab
}

snapshot_ismounted() {
  mountpoint -dq $pathrepo
  return
}

mount_current_snapshot() {
  snapshot_ismounted && umount -l $pathrepo
  mount -rt squashfs -o loop,nodev,noexec $pathsnapshots/$cursqfs $pathrepo || return 1
}

clean_old_snapshots() {
  for snap in $pathsnapshots/gentoo-*.xz.sqfs; do
    case $(basename $snap) in
      $cursqfs | $existingtarget)
      ;;
      *)
        rm "$snap"
      ;;
    esac
  done
}

main_portagehelper() {
  mkdir -p $pathrepo
  mkdir -p $pathsnapshots

  existingtarget=$(get_existing_target)
  clean_old_snapshots
  pushd $pathsnapshots > /dev/null
  ensure_key_and_snap_source && update_snapshot || exit 1
  popd > /dev/null
  [ "${existingtarget:-x}" == "$SNAPSHOT" ] && snapshot_ismounted && return 0

  ls --color=always -l --full-time $pathsnapshots
  ensure_snapshot_fstab
  mount_current_snapshot || exit 1
}

return 0 2>/dev/null || main_portagehelper
