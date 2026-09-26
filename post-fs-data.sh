#!/system/bin/sh
# post-fs-data.sh
# Runs early on every boot. $MODDIR is auto-exported by Magisk/KernelSU/APatch.
MODDIR=${MODDIR:-$(cd "$(dirname "$0")" && pwd)}

TARGET_NAME="WCNSS_qcom_cfg.ini"
MANIFEST="$MODDIR/mount_list"
SUSFS_BIN="/data/adb/ksu/bin/ksu_susfs"
: > "$MANIFEST"

# ---- build the patched copies -------------------------------------------
array=$(find /system /vendor -xdev -type f -name "$TARGET_NAME" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u)

if [ -z "$array" ]; then
  echo "bindwcnss: post-fs-data.sh - no $TARGET_NAME found on this device" >> /dev/kmsg
  echo "mode=0" > "$MODDIR/mode.sh"
  exit 0
fi

printf '%s\n' "$array" | while IFS= read -r SRC; do
  [ -f "$SRC" ] || continue

  case "$SRC" in
    /vendor/*) DEST="$MODDIR/system$SRC" ;;
    *)         DEST="$MODDIR$SRC" ;;
  esac

  mkdir -p "$(dirname "$DEST")"
  cp -af "$SRC" "$DEST"

  if grep -qE '^BandCapability=' "$DEST"; then
    sed -i -E 's/^BandCapability=.*/BandCapability=2/' "$DEST"
  else
    sed -i '1i BandCapability=2' "$DEST"
  fi

  ORIG_CTX=$(stat -c '%C' "$SRC" 2>/dev/null || true)
  [ -n "$ORIG_CTX" ] && [ "$ORIG_CTX" != "?" ] && chcon "$ORIG_CTX" "$DEST" 2>/dev/null || true
  ORIG_PERM=$(stat -c '%a' "$SRC" 2>/dev/null || true)
  chmod "${ORIG_PERM:-644}" "$DEST" 2>/dev/null || true
  chown --reference="$SRC" "$DEST" 2>/dev/null || true

  echo "$SRC:$DEST" >> "$MANIFEST"
done

# ---- decide how to hide the bind mount -----------------------------------
# mode=0   plain bind, no hiding
# mode=1   KSU + susfs try_umount           -> mount disappears on umount attempts
# mode=2   KSU + susfs sus_kstat+try_umount -> also fakes stat() metadata
# mode=3   KSU without magic-mount (built-in try_umount on newer KSU)
# mode=4   APatch with kernel-level bind-mount hiding
# mode=5   KSU + susfs open_redirect        -> no mount entry exists at all
# mode=10  KSU with ksud built-in per-path kernel umount (no susfs needed)
mode=0

if [ "$KSU" = "true" ] && [ -f "$SUSFS_BIN" ]; then
  features=$("$SUSFS_BIN" show enabled_features 2>/dev/null)
  echo "$features" | grep -q "CONFIG_KSU_SUSFS_OPEN_REDIRECT" && mode=5
  echo "$features" | grep -q "CONFIG_KSU_SUSFS_TRY_UMOUNT" && mode=1
  echo "$features" | grep -q "CONFIG_KSU_SUSFS_SUS_KSTAT" && mode=2
fi

if [ "$mode" -eq 0 ] && [ "$KSU" = "true" ] && /data/adb/ksud kernel 2>&1 | grep -q "umount"; then
  mode=10
fi

if [ "$mode" -eq 0 ] && [ "$KSU" = "true" ] && [ ! "$KSU_MAGIC_MOUNT" = "true" ] \
   && [ "${KSU_VER_CODE:-0}" -ge 22098 ] 2>/dev/null; then
  mode=3
fi

if [ "$mode" -eq 0 ] && [ "$APATCH" = "true" ] && [ "$APATCH_BIND_MOUNT" = "true" ]; then
  mode=4
fi

echo "mode=$mode" > "$MODDIR/mode.sh"
echo "bindwcnss: post-fs-data.sh - selected mode $mode" >> /dev/kmsg

# EOF