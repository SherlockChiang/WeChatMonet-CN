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
  # Register every staged system overlay before any per-user enable attempt.
  # Otherwise a newly added package fails once for secondary users and needs
  # another reboot even though pm install-existing succeeds later in this run.
  install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
fi

# Keep the mainland-only 9-patch bubble package present in both the module
# metadata tree and Meta-OverlayFS content tree. The package is static, so a
# first install may still require the next boot for PackageManager to scan it.
if is_mainland_wechat_version "$version_code"; then
  if install_mainland_bubble_overlay "$MODDIR" "-"; then
    bubble_users=$(list_target_users)
    if ! enable_chat_bubble_overlay_for_users "$bubble_users"; then
      echo '! 大陆版 Monet 会话气泡已安装，但系统尚未注册新 RRO；请重启一次设备。'
    fi
  else
    echo '! 大陆版 Monet 会话气泡安装失败。'
  fi
else
  # Remove a stale mainland package when the user updates WeChat to the Play
  # build without first rebooting. The normal Play bubble_style flow remains
  # unchanged.
  disable_chat_bubble_overlay_for_users
  remove_static_overlay "$MODDIR" "$CHAT_BUBBLE_OVERLAY_NAME"
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
