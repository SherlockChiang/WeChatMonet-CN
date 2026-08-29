#!/system/bin/sh

CONFIG="$MODPATH/config.conf"
CONFIG_FILE="$CONFIG"
OLD_CONFIG="/data/adb/modules/WeChat_Monet_Global/config.conf"

. "$MODPATH/common.sh"

echo_banner() {
  echo "
       __  ___                 __
      /  |/  /___  ____  ___  / /_
     / /|_/ / __ \/ __ \/ _ \/ __/
    /_/  /_/\____/_/ /_/\___/\__/
"
}

backup_config() {
  [ -f "$OLD_CONFIG" ] && cp -f "$OLD_CONFIG" "$CONFIG"
}

check_support() {
  local sdk_ver
  sdk_ver=$(getprop ro.build.version.sdk)
  echo '- 正在检查 Android 版本...'
  [ "$sdk_ver" -ge 34 ] || abort '! 需要 Android 14 或更高版本。'
}

WECHAT_CN="0"

check_wechat_version() {
  local version_code
  version_code=$(dumpsys package com.tencent.mm 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)

  if [ "$version_code" = "3084" ] || [ "$version_code" = "3085" ]; then
    echo "- 已确认微信版本：Play 版 8.0.72 (${version_code})"
  elif [ "$version_code" = "3140" ] || [ "$version_code" = "3141" ] || [ "$version_code" = "3160" ]; then
    WECHAT_CN="1"
    echo "- 已确认微信版本：大陆版 (${version_code})"
  else
    abort "! 仅支持微信大陆版 8.0.76/8.0.77 (3140/3141/3160) / Play 版 8.0.72 (3084/3085)，检测到 versionCode=${version_code:-未知}。"
  fi
}

safe_init_dir() {
  local dir="$1"
  [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "/data" ] || return 1
  mkdir -p "$dir" || return 1
  find "$dir" -mindepth 1 -delete 2>/dev/null
}

disable_tinker_dir() {
  local dir="$1"
  chattr -i "$dir" 2>/dev/null
  safe_init_dir "$dir"
  chmod 000 "$dir"
}

disable_all_tinker() {
  local user_dir user_id
  for user_dir in /data/user/*; do
    [ -d "$user_dir" ] || continue
    user_id=$(basename "$user_dir")
    disable_tinker_dir "/data/user/$user_id/com.tencent.mm/tinker"
    disable_tinker_dir "/data/user/$user_id/com.tencent.mm/tinker_temp"
    disable_tinker_dir "/data/user/$user_id/com.tencent.mm/tinker_server"
  done
}

choose_tinker_cleanup() {
  echo '- 是否清除并禁用微信热更新缓存？'
  echo ' 音量+ = 清除缓存并禁用热更新'
  echo ' 音量- = 保留热更新缓存 (不推荐)'

  if listen_volume_key; then
    disable_all_tinker
    set_conf_value "$CONFIG" "tinker_cleanup_enabled" "1"
    echo '- 已清除并禁用微信热更新缓存。'
  else
    echo '- 再次确认：是否「保留」热更新缓存？'
    echo ' 音量+ = 确认保留缓存 (不推荐)'
    echo ' 音量- = 清除缓存并禁用热更新'

    if listen_volume_key; then
      set_conf_value "$CONFIG" "tinker_cleanup_enabled" "0"
      echo '- 已保留微信热更新缓存。'
    else
      disable_all_tinker
      set_conf_value "$CONFIG" "tinker_cleanup_enabled" "1"
      echo '- 已清除并禁用微信热更新缓存。'
    fi
  fi
}

choose_multi_user() {
  if [ -n "$(ls /data/user/ 2>/dev/null | awk 'NR>1')" ]; then
    echo '- 检测到多用户环境。'
    echo '  音量+ = 为所有用户安装'
    echo '  音量- = 仅当前用户'
    if listen_volume_key; then
      set_conf_value "$CONFIG" "enable_multi_user" "1"
      echo '- 已选择：所有用户'
    else
      set_conf_value "$CONFIG" "enable_multi_user" "0"
      echo '- 已选择：仅当前用户'
    fi
  fi
}

install_base_overlay() {
  echo '- 正在安装微信 Monet 基础覆盖...'
  sleep 0.3
  install_static_overlay "$MODPATH" "MonetWeChat" || abort '! Monet 基础覆盖安装失败。'
}

choose_multi_scene_corners() {
  remove_static_overlay "$MODPATH" "MonetWeChatMultiSceneCorners"
  echo '- 是否启用多场景圆角优化？'
  echo '  输入栏, 消息引用, 支付键盘'
  echo '  音量+ = 启用'
  echo '  音量- = 不启用'
  if listen_volume_key; then
    install_static_overlay "$MODPATH" "MonetWeChatMultiSceneCorners" || abort '! 多场景圆角优化安装失败。'
    set_conf_value "$CONFIG" "multi_scene_corners_enabled" "1"
    echo '- 已启用多场景圆角优化。'
  else
    set_conf_value "$CONFIG" "multi_scene_corners_enabled" "0"
    echo '- 未启用多场景圆角优化。'
  fi
}

choose_bubble_style() {
  select_bubble_style "$MODPATH" "$CONFIG" || abort '! 气泡安装失败。'
  sleep 0.3
}

choose_tab_style() {
  select_tab_style "$MODPATH" "$CONFIG" || abort '! Monet 模糊底栏生成失败。'
}

finish_install() {
  set_conf_value "$CONFIG" "is_first_install" "1"
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/action.sh" 0 0 0755
  set_perm "$MODPATH/boot-completed.sh" 0 0 0755
  set_perm "$MODPATH/common.sh" 0 0 0755
  set_perm "$MODPATH/customize.sh" 0 0 0755
  set_perm "$MODPATH/service.sh" 0 0 0755
  echo '- 安装完成。'
  echo '! 如果覆盖没有生效，请关闭微信的模块卸载或热更新功能。'
}

main() {
  echo_banner
  backup_config
  check_support
  check_wechat_version
  choose_multi_user
  choose_tinker_cleanup
  install_base_overlay
  choose_multi_scene_corners
  if [ "$WECHAT_CN" = "1" ]; then
    echo '- 大陆版 8.0.76 气泡资源结构与 Play 版不同，跳过气泡样式安装。'
    remove_static_overlay "$MODPATH" "MonetWeChatBubblePro"
    remove_static_overlay "$MODPATH" "MonetWeChatClassicBubble"
  else
    choose_bubble_style
  fi
  choose_tab_style
  finish_install
}

main
