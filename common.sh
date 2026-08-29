#!/system/bin/sh

CONFIG_FILE=${CONFIG_FILE:-"${0%/*}/config.conf"}
TARGET_PACKAGE="com.tencent.mm"
SECONDARY_OVERLAY_SPECS="MonetWeChat:monet.com.tencent.mm MonetWeChatMultiSceneCorners:monet.multiscenecorners.com.tencent.mm MonetWeChatSolidTab:monet.solidtab.com.tencent.mm MonetWeChatClassicBubble:monet.classicbubble.com.tencent.mm MonetWeChatBubblePro:monet.bubblepro.com.tencent.mm MonetWeChatBlurTab:monet.blurtab.com.tencent.mm"
LOOKUP_SYSTEM_COLOR_MATCH=""
LOOKUP_SYSTEM_COLOR_VALUE=""
COMPUTE_BLUR_COLOR_MATCH=""
COMPUTE_BLUR_COLOR_VALUE=""

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

install_static_overlay() {
  local moddir="$1" name="$2"
  local source_apk="$moddir/files/${name}.apk"
  local target_dir="$moddir/system/priv-app/$name"
  [ -f "$source_apk" ] || return 1
  mkdir -p "$target_dir" || return 1
  cp -f "$source_apk" "$target_dir/${name}.apk" || return 1
  chmod 0755 "$moddir/system" "$moddir/system/priv-app" "$target_dir" 2>/dev/null || return 1
  chmod 0644 "$target_dir/${name}.apk" 2>/dev/null || return 1
}

remove_static_overlay() {
  rm -rf "$1/system/priv-app/$2"
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

lookup_system_color_once() {
  local resource_name="$1" raw
  raw=$(cmd overlay lookup android "android:color/$resource_name" 2>/dev/null | tr -d '\r' | sed -e 's/[[:space:]]*$//')
  [ -n "$raw" ] || return 1
  raw="${raw#\#}"
  raw="${raw#0x}"
  raw="${raw#0X}"
  if [ ${#raw} -eq 8 ]; then
    echo "${raw#??}"
  elif [ ${#raw} -eq 6 ]; then
    echo "$raw"
  else
    return 1
  fi
}

lookup_system_color() {
  local resource_name raw
  LOOKUP_SYSTEM_COLOR_MATCH=""
  LOOKUP_SYSTEM_COLOR_VALUE=""
  for resource_name in "$@"; do
    raw=$(lookup_system_color_once "$resource_name") || continue
    LOOKUP_SYSTEM_COLOR_MATCH="$resource_name"
    LOOKUP_SYSTEM_COLOR_VALUE="$raw"
    return 0
  done
  return 1
}

apply_opacity_to_rgb() {
  local rgb="$1" opacity_percent="$2" alpha_dec
  alpha_dec=$(((opacity_percent * 255 + 50) / 100))
  printf "0x%02X%s" "$alpha_dec" "$rgb"
}

compute_blur_color() {
  local opacity_percent="$1"
  shift
  lookup_system_color "$@" || return 1
  COMPUTE_BLUR_COLOR_MATCH="$LOOKUP_SYSTEM_COLOR_MATCH"
  COMPUTE_BLUR_COLOR_VALUE=$(apply_opacity_to_rgb "$LOOKUP_SYSTEM_COLOR_VALUE" "$opacity_percent")
}

list_target_users() {
  if [ -d /data/user ]; then
    ls /data/user 2>/dev/null | tr '\n' ' '
  else
    echo "0"
  fi
}

write_blur_values() {
  local values_file="$1" resource_name="$2" opacity="$3" color_value
  shift 3
  compute_blur_color "$opacity" "$@" || return 1
  color_value="${COMPUTE_BLUR_COLOR_VALUE#0x}"
  echo "- 写入 $resource_name: #$color_value (${COMPUTE_BLUR_COLOR_MATCH}, ${opacity}%)"
  echo "    <color name=\"$resource_name\">#$color_value</color>" >> "$values_file"
}

build_monet_overlay() {
  local moddir="$1" log_prefix="$2" output_dir="$3"
  local work_dir="$moddir/Workspace"
  local aapt2_bin="$moddir/files/aapt2"
  local output_apk="$output_dir/MonetWeChatBlurTab.apk"

  [ -x "$aapt2_bin" ] || chmod 0755 "$aapt2_bin" 2>/dev/null
  [ -x "$aapt2_bin" ] || return 1
  rm -rf "$work_dir"
  mkdir -p "$work_dir/res/values" "$work_dir/res/values-night" "$output_dir"

  cat > "$work_dir/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="monet.blurtab.${TARGET_PACKAGE}"
    android:versionCode="1"
    android:versionName="1.0">
    <uses-sdk android:minSdkVersion="31" android:targetSdkVersion="36" />
    <overlay android:targetPackage="${TARGET_PACKAGE}" android:isStatic="true" android:priority="10" />
    <application android:hasCode="false" android:extractNativeLibs="false" />
</manifest>
EOF

  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><resources>' > "$work_dir/res/values/colors.xml"
  write_blur_values \
    "$work_dir/res/values/colors.xml" \
    "df" \
    69 \
    "system_surface_container_light" \
    "system_surface_container_high_light" \
    "system_surface_light" \
    "system_primary_container_light" || return 1
  write_blur_values \
    "$work_dir/res/values/colors.xml" \
    "bb" \
    69 \
    "system_surface_container_light" \
    "system_surface_container_high_light" \
    "system_surface_light" \
    "system_primary_container_light" || return 1
  printf '%s\n' '</resources>' >> "$work_dir/res/values/colors.xml"

  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?><resources>' > "$work_dir/res/values-night/colors.xml"
  # night mode: restore WeChat's stock translucent-black bar so icons stay visible
  # regardless of the in-app dark-mode setting
  write_blur_values \
    "$work_dir/res/values-night/colors.xml" \
    "df" \
    80 \
    "black" || return 1
  write_blur_values \
    "$work_dir/res/values-night/colors.xml" \
    "bb" \
    80 \
    "black" || return 1
  printf '%s\n' '</resources>' >> "$work_dir/res/values-night/colors.xml"

  "$aapt2_bin" compile --dir "$work_dir/res" -o "$work_dir/compiled_res.zip" || return 1
  "$aapt2_bin" link \
    -I /system/framework/framework-res.apk \
    --manifest "$work_dir/AndroidManifest.xml" \
    -o "$output_apk" \
    "$work_dir/compiled_res.zip" || return 1

  rm -rf "$work_dir"
  chmod 0644 "$output_apk"
  [ -n "$log_prefix" ] && echo "$log_prefix 已根据当前 Monet 颜色生成模糊底栏"
  return 0
}

apply_blur_overlay() {
  local moddir="$1" users="$2" log_prefix="$3" attempt=1
  local output_dir="$moddir/system/priv-app/MonetWeChatBlurTab"
  local staged_dir="$moddir/system/priv-app/.MonetWeChatBlurTab-new"

  rm -rf "$staged_dir"
  while [ "$attempt" -le 5 ]; do
    build_monet_overlay "$moddir" "$log_prefix" "$staged_dir" && break
    rm -rf "$staged_dir"
    [ "$attempt" -eq 5 ] && break
    [ -n "$log_prefix" ] && echo "$log_prefix Monet 取色尚未就绪，2 秒后重试（$attempt/5）"
    sleep 2
    attempt=$((attempt + 1))
  done

  if [ "$attempt" -gt 5 ] || [ ! -f "$staged_dir/MonetWeChatBlurTab.apk" ]; then
    rm -rf "$staged_dir"
    [ -n "$log_prefix" ] && echo "$log_prefix 动态生成模糊底栏失败，已保留现有底栏"
    return 1
  fi

  remove_static_overlay "$moddir" "MonetWeChatBlurTab"
  mv "$staged_dir" "$output_dir" || return 1
  return 0
}

disable_blur_overlay() {
  remove_static_overlay "$1" "MonetWeChatBlurTab"
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
