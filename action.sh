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
  echo '音量+ = 为其他用户启用覆盖'
  echo '音量- = 依次配置气泡和底栏'
  if listen_volume_key; then
    install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
  else
    version_code=$(dumpsys package "$TARGET_PACKAGE" 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    if [ "$version_code" = "3140" ] || [ "$version_code" = "3141" ] || [ "$version_code" = "3160" ]; then
      echo '- 大陆版无气泡资源，跳过气泡样式配置。'
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
  show_apply_note
}

main
