#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
TARGET_PACKAGE="com.tencent.mm"

. "$MODDIR/common.sh"

OVERLAY_PACKAGES="monet.com.tencent.mm ${CHAT_BUBBLE_OVERLAY_PACKAGE} monet.bubblepro.com.tencent.mm monet.classicbubble.com.tencent.mm monet.multiscenecorners.com.tencent.mm monet.solidtab.com.tencent.mm monet.blurtab.com.tencent.mm ${BADGE_OVERLAY_PACKAGE}"

overlay_installed() {
  pm path "$1" >/dev/null 2>&1
}

set_overlay_state() {
  local user_id="$1" package_name="$2" state="$3"
  overlay_installed "$package_name" || return 0
  cmd overlay "$state" --user "$user_id" "$package_name" >/dev/null 2>&1
}

restore_overlay_state() {
  local user_id="$1" version_code="$2" bubble_style tab_style
  bubble_style=$(get_conf_value "$CONFIG" "bubble_style" "modern")
  tab_style=$(get_conf_value "$CONFIG" "blur_enabled" "0")

  # Clear stale choices first; overlays that are not installed are skipped.
  for package_name in $OVERLAY_PACKAGES; do
    set_overlay_state "$user_id" "$package_name" disable
  done

  # The base overlay is always required. Play's modern bubble is part of that
  # package; mainland builds use the dedicated image-backed RRO below.
  set_overlay_state "$user_id" "monet.com.tencent.mm" enable

  if is_mainland_wechat_version "$version_code"; then
    if [ -f "$MODDIR/system/priv-app/$CHAT_BUBBLE_OVERLAY_NAME/$CHAT_BUBBLE_OVERLAY_NAME.apk" ]; then
      set_overlay_state "$user_id" "$CHAT_BUBBLE_OVERLAY_PACKAGE" enable
    fi
  else
    case "$bubble_style" in
      pro) set_overlay_state "$user_id" "monet.bubblepro.com.tencent.mm" enable ;;
      classic) set_overlay_state "$user_id" "monet.classicbubble.com.tencent.mm" enable ;;
    esac
  fi

  if [ "$(get_conf_value "$CONFIG" "multi_scene_corners_enabled" "0")" = "1" ]; then
    set_overlay_state "$user_id" "monet.multiscenecorners.com.tencent.mm" enable
  fi

  if [ "$tab_style" = "1" ]; then
    set_overlay_state "$user_id" "monet.blurtab.com.tencent.mm" enable
  else
    set_overlay_state "$user_id" "monet.solidtab.com.tencent.mm" enable
  fi

  # Badge/accent resources are independent of the selected bubble/tab style
  # and are enabled whenever the prebuilt package is present.
  set_overlay_state "$user_id" "$BADGE_OVERLAY_PACKAGE" enable
}

disable_overlay_state() {
  local user_id="$1" package_name
  for package_name in $OVERLAY_PACKAGES; do
    set_overlay_state "$user_id" "$package_name" disable
  done
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

version_code=$(dumpsys package "$TARGET_PACKAGE" 2>/dev/null | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
if ! is_supported_wechat_version "$version_code"; then
  echo "! 当前微信版本不受支持（versionCode=${version_code:-未知}），停用旧覆盖配置。"
  for user_id in $(list_target_users); do
    disable_overlay_state "$user_id"
    am force-stop --user "$user_id" "$TARGET_PACKAGE" 2>/dev/null
  done
  exit 0
fi

for user_id in $(list_target_users); do
  restore_overlay_state "$user_id" "$version_code"
  am force-stop --user "$user_id" "$TARGET_PACKAGE" 2>/dev/null
done
