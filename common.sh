#!/system/bin/sh

CONFIG_FILE=${CONFIG_FILE:-"${0%/*}/config.conf"}
TARGET_PACKAGE="com.tencent.mm"
BADGE_OVERLAY_NAME="MonetWeChatBadge"
BADGE_OVERLAY_PACKAGE="monet.badge.${TARGET_PACKAGE}"
SECONDARY_OVERLAY_SPECS="MonetWeChat:monet.com.tencent.mm MonetWeChatMultiSceneCorners:monet.multiscenecorners.com.tencent.mm MonetWeChatSolidTab:monet.solidtab.com.tencent.mm MonetWeChatClassicBubble:monet.classicbubble.com.tencent.mm MonetWeChatBubblePro:monet.bubblepro.com.tencent.mm MonetWeChatBlurTab:monet.blurtab.com.tencent.mm ${BADGE_OVERLAY_NAME}:${BADGE_OVERLAY_PACKAGE}"

# Keep version gates in one place so the installer and action menu cannot drift.
is_play_wechat_version() {
  case "$1" in
    3084|3085) return 0 ;;
    *) return 1 ;;
  esac
}

is_mainland_wechat_version() {
  case "$1" in
    3140|3141|3160) return 0 ;;
    *) return 1 ;;
  esac
}

is_supported_wechat_version() {
  is_play_wechat_version "$1" || is_mainland_wechat_version "$1"
}

listen_volume_key() {
  while :; do
    local key_event
    key_event=$(getevent -qlc 1 2>/dev/null)
    case "$key_event" in
      *KEY_VOLUMEUP*DOWN*) return 0 ;;
      *KEY_VOLUMEDOWN*DOWN*) return 1 ;;
    esac
  done
}

select_bubble_style() {
  local moddir="$1" config="$2"
  remove_static_overlay "$moddir" "MonetWeChatBubblePro"
  remove_static_overlay "$moddir" "MonetWeChatBubbleProBlur"
  remove_static_overlay "$moddir" "MonetWeChatClassicBubble"
  echo '- 请选择气泡样式'
  echo '  音量+ = 圆角气泡'
  echo '  音量- = 经典气泡'
  if listen_volume_key; then
    echo '- 请选择圆角气泡样式'
    echo '  音量+ = 现代圆角'
    echo '  音量- = Pro 圆角'
    if listen_volume_key; then
      set_conf_value "$config" "bubble_style" "modern"
      echo '- 已选择: 现代圆角气泡。'
    else
      install_static_overlay "$moddir" "MonetWeChatBubblePro" || return 1
      set_conf_value "$config" "bubble_style" "pro"
      echo '- 已选择: Pro 圆角气泡。'
    fi
  else
    install_static_overlay "$moddir" "MonetWeChatClassicBubble" || return 1
    set_conf_value "$config" "bubble_style" "classic"
    echo '- 已选择: 经典气泡。'
  fi
}

get_conf_value() {
  local file="$1" key="$2" default="$3" value
  [ ! -f "$file" ] && echo "$default" && return 0
  value=$(grep -E "^${key}=" "$file" | head -n1 | cut -d'=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  [ -n "$value" ] && echo "$value" || echo "$default"
}

set_conf_value() {
  local file="$1" key="$2" value="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -q -E "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    echo "${key}=\"${value}\"" >> "$file"
  fi
}

get_overlay_content_dir() {
  local moddir="$1" module_id root candidate mount_root
  module_id="${MODID:-${moddir##*/}}"
  [ -n "$module_id" ] || return 1

  # Meta-OverlayFS exposes the actual /system lowerdir separately from the
  # module metadata tree. Action/service scripts do not always inherit the
  # exported MODULE_CONTENT_DIR, so keep known mount points as fallbacks.
  for root in "${MODULE_CONTENT_DIR:-}" \
      "/data/adb/modules/meta-overlayfs/mnt" \
      "/data/adb/metamodule/mnt"; do
    [ -n "$root" ] || continue
    case "$root" in
      */"$module_id")
        candidate="$root"
        mount_root="${root%/$module_id}"
        ;;
      *)
        candidate="$root/$module_id"
        mount_root="$root"
        ;;
    esac
    [ "$candidate" = "$moddir" ] && continue
    [ -d "$candidate" ] || continue
    if command -v mountpoint >/dev/null 2>&1; then
      mountpoint -q "$mount_root" 2>/dev/null || continue
    fi
    echo "$candidate"
    return 0
  done
  return 1
}

install_overlay_apk() {
  local source_apk="$1" target_moddir="$2" name="$3"
  local target_dir="$target_moddir/system/priv-app/$name"
  [ -f "$source_apk" ] || return 1
  mkdir -p "$target_dir" || return 1
  # Avoid replacing an identical APK after PackageManager has scanned it at
  # boot; this keeps the registered path/inode stable while still repairing a
  # missing or stale Meta-OverlayFS copy.
  if [ ! -f "$target_dir/${name}.apk" ] || ! cmp -s "$source_apk" "$target_dir/${name}.apk" 2>/dev/null; then
    cp -f "$source_apk" "$target_dir/${name}.apk" || return 1
  fi
  chmod 0755 "$target_moddir/system" "$target_moddir/system/priv-app" "$target_dir" 2>/dev/null || return 1
  chmod 0644 "$target_dir/${name}.apk" 2>/dev/null || return 1
  if command -v chcon >/dev/null 2>&1; then
    chcon --reference="$target_moddir/system/priv-app" "$target_dir" "$target_dir/${name}.apk" 2>/dev/null || true
  fi
  return 0
}

install_static_overlay() {
  local moddir="$1" name="$2" content_dir
  local source_apk="$moddir/files/${name}.apk"
  install_overlay_apk "$source_apk" "$moddir" "$name" || return 1

  # Keep metadata for ordinary installs and mirror the selected APK into the
  # content tree used by Meta-OverlayFS when it is present.
  content_dir=$(get_overlay_content_dir "$moddir" 2>/dev/null) || content_dir=""
  if [ -n "$content_dir" ]; then
    install_overlay_apk "$source_apk" "$content_dir" "$name" || {
      echo "! Meta-OverlayFS 同步 $name 失败。"
      return 1
    }
  fi
  return 0
}

remove_static_overlay() {
  local moddir="$1" name="$2" content_dir
  rm -rf "$moddir/system/priv-app/$name"
  content_dir=$(get_overlay_content_dir "$moddir" 2>/dev/null) || content_dir=""
  [ -n "$content_dir" ] && rm -rf "$content_dir/system/priv-app/$name"
}

reconcile_overlay_content() {
  local moddir="$1" content_dir name source_apk
  # During a Meta-OverlayFS update, the metadata directory can temporarily
  # contain only module.prop and an update/remove marker while the old image
  # is still mounted. Never interpret that transient state as an empty module.
  [ -d "$moddir/system" ] || return 0
  [ ! -e "$moddir/update" ] || return 0
  [ ! -e "$moddir/remove" ] || return 0
  content_dir=$(get_overlay_content_dir "$moddir" 2>/dev/null) || return 0

  # cp -af used by older meta-overlayfs versions never removes files from a
  # previous module revision. Reconcile every known overlay directory so a
  # removed optional feature cannot remain mounted and override current state.
  for name in MonetWeChat MonetWeChatMultiSceneCorners MonetWeChatSolidTab \
      MonetWeChatClassicBubble MonetWeChatBubblePro MonetWeChatBubbleProBlur \
      MonetWeChatBlurTab "$BADGE_OVERLAY_NAME"; do
    source_apk="$moddir/system/priv-app/$name/$name.apk"
    if [ -f "$source_apk" ]; then
      install_overlay_apk "$source_apk" "$content_dir" "$name" || return 1
    else
      rm -rf "$content_dir/system/priv-app/$name"
    fi
  done
  return 0
}

install_for_secondary_users() {
  local moddir="$1" user_id spec overlay_name package_name failure_count=0 result
  for user_id in $(ls /data/user/ 2>/dev/null); do
    [ "$user_id" = "0" ] && continue
    for spec in $SECONDARY_OVERLAY_SPECS; do
      overlay_name=${spec%%:*}
      package_name=${spec#*:}
      [ -f "$moddir/system/priv-app/$overlay_name/$overlay_name.apk" ] || continue
      result=$(pm install-existing --user "$user_id" "$package_name" 2>&1)
      if [ $? -ne 0 ]; then
        echo "! 用户 $user_id 启用 $package_name 失败：$result"
        failure_count=$((failure_count + 1))
      fi
    done
    am force-stop --user "$user_id" "$TARGET_PACKAGE" 2>/dev/null
  done
  [ "$failure_count" -eq 0 ] || return 1
  return 0
}

list_target_users() {
  if [ -d /data/user ]; then
    ls /data/user 2>/dev/null | tr '\n' ' '
  else
    echo "0"
  fi
}

apply_blur_overlay() {
  local moddir="$1" log_prefix="$3"
  # This APK is built and v3-signed on the host.  Runtime aapt2 output is not
  # installable on Android 14/15 because PackageManager requires a signature.
  install_static_overlay "$moddir" "MonetWeChatBlurTab" || {
    [ -n "$log_prefix" ] && echo "$log_prefix 预签名模糊底栏安装失败"
    return 1
  }
  [ -n "$log_prefix" ] && echo "$log_prefix 已安装预签名 Monet 模糊底栏"
  if [ "$(get_conf_value "$moddir/config.conf" "enable_multi_user" "0")" = "1" ]; then
    install_for_secondary_users "$moddir" || return 1
  fi
  return 0
}

disable_blur_overlay() {
  remove_static_overlay "$1" "MonetWeChatBlurTab"
}

apply_badge_overlay() {
  local moddir="$1" log_prefix="$3"
  # The badge overlay is also prebuilt and v3-signed.  Its `ac` and `Red_100`
  # slots reference Android's light/dark system_primary colors, so the red
  # accent follows the current Monet palette after a configuration change.
  install_static_overlay "$moddir" "$BADGE_OVERLAY_NAME" || {
    [ -n "$log_prefix" ] && echo "$log_prefix 预签名 Monet 红点覆盖安装失败"
    return 1
  }
  [ -n "$log_prefix" ] && echo "$log_prefix 已安装预签名 Monet 红点覆盖（ac/Red_100）"
  if [ "$(get_conf_value "$moddir/config.conf" "enable_multi_user" "0")" = "1" ]; then
    install_for_secondary_users "$moddir" || {
      [ -n "$log_prefix" ] && echo "$log_prefix Monet 红点覆盖已安装，但部分次要用户尚未启用"
    }
  fi
  return 0
}

disable_badge_overlay() {
  remove_static_overlay "$1" "$BADGE_OVERLAY_NAME"
}

enable_badge_overlay_for_users() {
  local user_list="${1:-$(list_target_users)}" user_id failure=0
  for user_id in $user_list; do
    [ -n "$user_id" ] || continue
    cmd overlay enable --user "$user_id" "$BADGE_OVERLAY_PACKAGE" >/dev/null 2>&1 || failure=1
  done
  [ "$failure" -eq 0 ]
}

select_bubble_style_legacy_removed() {
  local moddir="$1" config="$2"
  echo '- 请选择气泡分类'
  echo '  音量+ = 圆角气泡'
  echo '  音量- = 经典气泡（带尾巴）'
  if listen_volume_key; then
    echo '- 请选择圆角气泡系列'
    echo '  音量+ = 现代圆角'
    echo '  音量- = 纯色圆角 Pro'
    if listen_volume_key; then
      set_conf_value "$config" "bubble_style" "modern"
      echo '- 已选择：现代圆角气泡。'
    else
      if listen_volume_key; then
        install_static_overlay "$moddir" "MonetWeChatBubblePro" || return 1
        set_conf_value "$config" "bubble_style" "pro"
        echo '- 已选择：纯色圆角 Pro 气泡。'
      else
        install_static_overlay "$moddir" "MonetWeChatBubblePro" || return 1
        set_conf_value "$config" "bubble_style" "pro"
        echo '- 已选择：纯色圆角 Pro 气泡。'
      fi
    fi
  else
    install_static_overlay "$moddir" "MonetWeChatClassicBubble" || return 1
    set_conf_value "$config" "bubble_style" "classic"
    echo '- 已选择：经典气泡。'
  fi
}

select_tab_style() {
  local moddir="$1" config="$2" users
  users=$(list_target_users)
  echo '- 请选择底栏样式'
  echo '  音量+ = 纯色底栏'
  echo '  音量- = 模糊底栏'
  if listen_volume_key; then
    disable_blur_overlay "$moddir" "$users"
    remove_static_overlay "$moddir" "MonetWeChatSolidTab"
    install_static_overlay "$moddir" "MonetWeChatSolidTab" || return 1
    set_conf_value "$config" "blur_enabled" "0"
    echo '- 已选择：纯色底栏。'
  else
    remove_static_overlay "$moddir" "MonetWeChatSolidTab"
    apply_blur_overlay "$moddir" "$users" "-" || return 1
    set_conf_value "$config" "blur_enabled" "1"
    echo '- 已选择：Monet 模糊底栏。'
  fi
}
