#!/usr/bin/env sh
TARGET_NAME="WCNSS_qcom_cfg.ini"

ui_print "- Searching for $TARGET_NAME on device..."

array=$(find /system /vendor -xdev -type f -name "$TARGET_NAME" 2>/dev/null || true)
array=$(printf '%s\n' "$array" | sed '/^[[:space:]]*$/d' | sort -u)

if [ -z "$array" ]; then
  ui_print "! No $TARGET_NAME found on this device."
  ui_print "! This module only work on Qcom devices"
  return 0
else
  ui_print "- Reboot to apply."
fi