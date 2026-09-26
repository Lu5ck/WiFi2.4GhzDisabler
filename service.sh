#!/system/bin/sh
# service.sh
# Runs at "late_start service" - after /system is mounted and (on plain
# Magisk) after boot has actually completed.
MODDIR=${MODDIR:-$(cd "$(dirname "$0")" && pwd)}
MANIFEST="$MODDIR/mount_list"
SUSFS_BIN="/data/adb/ksu/bin/ksu_susfs"

[ -s "$MANIFEST" ] || exit 0
[ -f "$MODDIR/mode.sh" ] && . "$MODDIR/mode.sh"
mode=${mode:-0}

if [ -z "$KSU" ] && [ -z "$APATCH" ]; then
  until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
  done
fi

bind_plain() {
  # SRC=$1 DEST=$2
  mount --bind "$2" "$1"
}

bind_susfs_try_umount() {
  mount --bind "$2" "$1"
  "$SUSFS_BIN" add_try_umount "$1" 1
}

bind_susfs_kstat() {
  # fake the stat() metadata (size/inode/mtime) back to the original
  # file's values *before* mounting over it, then bind + mark try_umount
  "$SUSFS_BIN" add_sus_kstat "$1"
  mount --bind "$2" "$1"
  "$SUSFS_BIN" update_sus_kstat "$1"
  "$SUSFS_BIN" add_try_umount "$1" 1
  "$SUSFS_BIN" add_try_umount "$1" > /dev/null 2>&1 # legacy susfs arg form
}

susfs_open_redirect() {
  # no mount() call at all - the kernel redirects open() of SRC straight
  # to DEST, so there is never a /proc/mounts entry to find in the first
  # place. uid_scheme "2" = effective for non-su processes only.
  "$SUSFS_BIN" add_open_redirect "$1" "$2" 2 2>/dev/null \
    || "$SUSFS_BIN" add_open_redirect "$1" "$2"
}

ksud_kernel_umount() {
  mount --bind "$2" "$1"
  /data/adb/ksud kernel umount add "$1" --flags 2 > /dev/null 2>&1
}

while IFS=':' read -r SRC DEST; do
  [ -f "$SRC" ] || continue
  [ -f "$DEST" ] || continue

  case "$mode" in
    1)  bind_susfs_try_umount "$SRC" "$DEST" ;;
    2)  bind_susfs_kstat "$SRC" "$DEST" ;;
    5)  susfs_open_redirect "$SRC" "$DEST" ;;
    10) ksud_kernel_umount "$SRC" "$DEST" ;;
    3|4) bind_plain "$SRC" "$DEST" ;;    # manager already hides this itself
    *)  bind_plain "$SRC" "$DEST" ;;     # no hiding available - visible bind
  esac

  if [ $? -eq 0 ]; then
    echo "bindwcnss: service.sh - mode $mode applied $DEST -> $SRC" >> /dev/kmsg
  else
    echo "bindwcnss: service.sh - FAILED (mode $mode) $DEST -> $SRC" >> /dev/kmsg
  fi
done < "$MANIFEST"

# EOF