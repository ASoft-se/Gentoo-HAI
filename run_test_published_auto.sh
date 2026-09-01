#!/bin/bash
set -o pipefail
[[ -d pxe ]] || mkdir -p pxe
if [[ ! -f pxe/online_boot.ipxe ]]; then
minimal_latest_json=$(curl -s "https://api.github.com/repos/NiKiZe/Gentoo-iPXE/releases/latest")
tag_name=$(grep '"tag_name":' <<< "$minimal_latest_json" | head -n 1 | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/')
if [[ -z "$tag_name" ]]; then
    echo "Error: tag not found"
    exit 1
fi
ipxe_url=$(grep "${tag_name}.ipxe" <<< "$minimal_latest_json" | grep '"browser_download_url":' | head -n 1 | sed -E 's/.*"browser_download_url":\s*"([^"]+)".*/\1/')

if [[ -z "$ipxe_url" ]]; then
    echo "Error: ${tag_name}.ipxe asset not found in release"
    exit 1
fi

base_url="${ipxe_url%/*}/"
filtered_ipxe=$(curl -sL "$ipxe_url" | grep -E '^(kernel|initrd)' | sed "s| ${tag_name}-| ${base_url}${tag_name}-|g")
cat << EOF > pxe/online_boot.ipxe
#!ipxe
set keymap keymap=us net.ifnames=0 autoinstall
${filtered_ipxe}
initrd ../updates/root/.bashrc /updates/root/.bashrc mkdir=2 mode=644
initrd ../updates/etc/motd /updates/etc/motd mkdir=1 mode=644
imgstat
boot
EOF

fi

# replace if unset oor empty
: "${LOGPFX:=HAI}"
# replace if unset
: "${RUNOPTS="useefi usenvme"}"

rm kvm_lxgentootest.qcow2 || true

cat pxe/online_boot.ipxe
LOG_FILE=run_full.log
META_FILE=run_metadata.txt
ENV_FILE=run_vars.sh
> $META_FILE
> $ENV_FILE
date > $LOG_FILE

FIFO_PIPE=$(mktemp -u)
mkfifo "$FIFO_PIPE"
bash test_w_qemu.sh -bootfile pxe/online_boot.ipxe auto ${RUNOPTS} > "$FIFO_PIPE" 2>&1 &
QEMU_RUN_PID=$!

{
  buffer=""
  NEED_PREFIX=1
  MSGQUEUE=()
  while IFS= read -r -d '' -n 1 char; do
    if [ "$NEED_PREFIX" -eq 1 ]; then
      [ ${#MSGQUEUE[@]} -gt 0 ] && printf "%s\n" "${MSGQUEUE[@]}" >&2 && MSGQUEUE=()
      printf "[%s %02d:%02d] " "${LOGPFX}" $((SECONDS / 60)) $((SECONDS % 60))
      NEED_PREFIX=0
    fi
    printf "%s" "$char"
    if [[ "$char" == $'\n' ]]; then
      NEED_PREFIX=1
    fi
    if [[ "$char" != $'\r' && "$char" != $'\n' ]]; then
      buffer+="$char"
      continue
    fi
    line="$buffer"
    buffer=""

    line=$(sed 's/\x1b\[[0-9;]*[mKHP]//g' <<< "$line")
    case "$line" in
      "Could not boot image:"* | \
      "No more network devices"* | \
      "No bootable device."*)
        echo "❌ FAIL $line"
        exit 1
        ;;
      *" -- Open Source Network Boot Firmware -- https://ipxe.org"*)
        IPXE=$(grep -o "iPXE [0-9.+ a-fg()]*[^ -]" <<< "$line")
        declare -p IPXE >> $ENV_FILE
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x8C\x90 '"$(date) iPXE Version: ${IPXE}")")
        ;;
      "install-"*"-image.squashfs :"*)
        CDVERSION="${line%-image.squashfs*}"
        declare -p CDVERSION >> $ENV_FILE
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x92\xBF '"$(date) CD Version: ${CDVERSION}")")
        ;;
      *"Welcome to Gentoo-HAI Dracut"*)
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x8E\xAF '"$(date) Initial boot OK")")
        ;;
      "+ "[a-z0-9]*"_emerge"*|"+ end_"*)
        CURRENT_TIMER=$(grep -o -E '[a-z0-9_]+' <<< "$line")
        ;;
      real[[:space:]]*)
        ELAPSED=$(grep -o '[0-9][0-9hms.]*' <<< "$line")
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xE2\x8F\xB1\xEF\xB8\x8F '"$(date) ${CURRENT_TIMER} Time: ${ELAPSED}")")
        CURRENT_TIMER=""
        ;;
      *"Snapshot"*"gentoo-"*".sqfs "*)
        SNAPSHOT=$(grep -o 'gentoo-[^[:space:]]*sqfs' <<< "$line")
        declare -p SNAPSHOT >> $ENV_FILE
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x93\xB8 '"$(date) Snapshot Used: ${SNAPSHOT}")")
        ;;
      *"download latest stage file stage3-"*".tar.xz"*)
        STAGE3=$(grep -o 'stage3-[^[:space:]]*xz' <<< "$line")
        declare -p STAGE3 >> $ENV_FILE
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x93\xA6 '"$(date) Stage3 Used: ${STAGE3}")")
        ;;
      *"] "*"sys-kernel/gentoo-sources-"*)
        KERNEL=$(grep -o 'gentoo-sources-[0-9.]*' <<< "$line")
        declare -p KERNEL >> $ENV_FILE
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x90\xA7 '"$(date) Kernel: ${KERNEL}")")
        ;;
      "This is gtestinst (Linux"*)
        MSGQUEUE+=("$(tee -a $META_FILE <<< $'\xF0\x9F\x8E\xAF '"$(date) All good after reboot")")
        pkill -P $QEMU_RUN_PID 2>/dev/null || true
        exit 0
        ;;
    esac
  done
  exit 1
} < "$FIFO_PIPE" | tee -a $LOG_FILE &
JOB_PID=$!

(sleep 45m; kill $JOB_PID 2>/dev/null) &
TIMEOUT_PID=$!
wait $JOB_PID
job_rc=$?

echo
date >> $LOG_FILE
kill $TIMEOUT_PID 2>/dev/null || true
pkill -P $QEMU_RUN_PID 2>/dev/null || true
pkill -P $JOB_PID 2>/dev/null || true
rm -f "$FIFO_PIPE" 2>/dev/null || true
[[ $job_rc -ne 0 ]] && echo "❌ FAIL timeout" || true
[[ -s "$META_FILE" ]] && cat "$META_FILE" || true
exit $job_rc
