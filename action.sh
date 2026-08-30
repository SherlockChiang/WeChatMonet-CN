#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
CONFIG_FILE="$CONFIG"
TARGET_PACKAGE="com.tencent.mm"

. "$MODDIR/common.sh"

show_apply_note() {
  am force-stop "$TARGET_PACKAGE" 2>/dev/null
  echo '- 操作完成；如覆盖没有立即生效，请手动重启设备。'
}

main() {
  version_code=$(dumpsys package "$TARGET_PACKAGE" 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
  if ! is_supported_wechat_version "$version_code"; then
    echo "! 当前微信版本不受支持（versionCode=${version_code:-未知}），未修改覆盖配置。"
    return 1
  fi

  echo '音量+ = 为其他用户启用覆盖'
  echo '音量- = 依次配置气泡和底栏'
  if listen_volume_key; then
    install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
  else
    if is_mainland_wechat_version "$version_code"; then
      echo '- 大陆版 8.0.76/8.0.77 无可移植气泡资源，跳过气泡样式配置。'
    else
      select_bubble_style "$MODDIR" "$CONFIG" || {
        echo '! 气泡切换失败。'
        return 1
      }
    fi
    select_tab_style "$MODDIR" "$CONFIG" || {
      echo '! 底栏切换或刷新失败。'
      return 1
    }
  fi
  if apply_badge_overlay "$MODDIR" "$(list_target_users)" "-"; then
    badge_users=$(list_target_users)
    if ! enable_badge_overlay_for_users "$badge_users"; then
      echo '! Monet 红点覆盖已刷新，但系统尚未注册新 RRO；请重启一次设备。'
    fi
  else
    echo '! Monet 红点刷新失败，已保留现有覆盖。'
  fi
  show_apply_note
}

main
