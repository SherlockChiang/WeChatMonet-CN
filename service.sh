#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
CONFIG_FILE="$CONFIG"

. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

version_code=$(dumpsys package com.tencent.mm 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
if ! is_supported_wechat_version "$version_code"; then
  echo "! 当前微信版本不受支持（versionCode=${version_code:-未知}），跳过覆盖启用。"
  exit 0
fi

if [ "$(get_conf_value "$CONFIG" "is_first_install" "0")" = "1" ] && [ "$(get_conf_value "$CONFIG" "enable_multi_user" "0")" = "1" ]; then
  install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
fi

if [ "$(get_conf_value "$CONFIG" "blur_enabled" "0")" = "1" ]; then
  if apply_blur_overlay "$MODDIR" "$(list_target_users)" "-"; then
    am force-stop com.tencent.mm 2>/dev/null
  fi
fi

# The prebuilt badge RRO references system_primary light/dark colors. Re-copy
# it into the Meta-OverlayFS content tree on every boot, but never generate an
# unsigned APK at runtime.
if apply_badge_overlay "$MODDIR" "$(list_target_users)" "-"; then
  badge_users=$(list_target_users)
  if ! enable_badge_overlay_for_users "$badge_users"; then
    echo '! Monet 红点覆盖已安装，但系统尚未注册新 RRO；请重启一次设备。'
  fi
  for user_id in $badge_users; do
    am force-stop --user "$user_id" com.tencent.mm 2>/dev/null
  done
fi

# Meta-OverlayFS keeps a separate mounted content tree. Reconcile it after
# optional/static selection and dynamic overlays to remove stale APKs.
if ! reconcile_overlay_content "$MODDIR"; then
  echo '! Meta-OverlayFS overlay 内容同步失败，请查看模块日志。'
fi

if [ "$(get_conf_value "$CONFIG" "is_first_install" "0")" = "1" ]; then
  set_conf_value "$CONFIG" "is_first_install" "0"
fi
