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

  # Mainland WeChat has a separate image-backed 9-patch bubble package. Keep
  # it staged before either action-menu branch so secondary users receive the
  # same package as the primary user.
  if is_mainland_wechat_version "$version_code"; then
    install_mainland_bubble_overlay "$MODDIR" "-" || {
      echo '! 大陆版 Monet 会话气泡安装失败。'
      return 1
    }
  else
    # Clean a mainland RRO before applying a Play-only bubble choice. This is
    # relevant when WeChat itself was switched without rebooting first.
    disable_chat_bubble_overlay_for_users
    remove_static_overlay "$MODDIR" "$CHAT_BUBBLE_OVERLAY_NAME"
  fi

  echo '音量+ = 为其他用户启用覆盖'
  echo '音量- = 依次配置气泡和底栏'
  if listen_volume_key; then
    install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
    if is_mainland_wechat_version "$version_code"; then
      bubble_users=$(list_target_users)
      enable_chat_bubble_overlay_for_users "$bubble_users" || \
        echo '! 大陆版 Monet 会话气泡已安装，但当前用户尚未注册新 RRO；请重启一次设备。'
    fi
  else
    if is_mainland_wechat_version "$version_code"; then
      bubble_users=$(list_target_users)
      if enable_chat_bubble_overlay_for_users "$bubble_users"; then
        echo '- 已启用大陆版 Monet 会话气泡。'
      else
        echo '! 大陆版 Monet 会话气泡已安装，但系统尚未注册新 RRO；请重启一次设备。'
      fi
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
