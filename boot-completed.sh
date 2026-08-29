#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
TARGET_PACKAGE="com.tencent.mm"

. "$MODDIR/common.sh"

OVERLAY_PACKAGES="monet.com.tencent.mm monet.bubblepro.com.tencent.mm monet.classicbubble.com.tencent.mm monet.multiscenecorners.com.tencent.mm monet.solidtab.com.tencent.mm monet.blurtab.com.tencent.mm"

overlay_installed() {
  pm path "$1" >/dev/null 2>&1
}

set_overlay_state() {
  local user_id="$1" package_name="$2" state="$3"
  overlay_installed "$package_name" || return 0
  cmd overlay "$state" --user "$user_id" "$package_name" >/dev/null 2>&1
}

restore_overlay_state() {
  local user_id="$1" bubble_style tab_style
  bubble_style=$(get_conf_value "$CONFIG" "bubble_style" "modern")
  tab_style=$(get_conf_value "$CONFIG" "blur_enabled" "0")

  # Clear stale choices first; overlays that are not installed are skipped.
  for package_name in $OVERLAY_PACKAGES; do
    set_overlay_state "$user_id" "$package_name" disable
  done

  # The base overlay is always required. It also represents the modern bubble.
  set_overlay_state "$user_id" "monet.com.tencent.mm" enable

  case "$bubble_style" in
    pro) set_overlay_state "$user_id" "monet.bubblepro.com.tencent.mm" enable ;;
    classic) set_overlay_state "$user_id" "monet.classicbubble.com.tencent.mm" enable ;;
  esac

  if [ "$(get_conf_value "$CONFIG" "multi_scene_corners_enabled" "0")" = "1" ]; then
    set_overlay_state "$user_id" "monet.multiscenecorners.com.tencent.mm" enable
  fi

  if [ "$tab_style" = "1" ]; then
    set_overlay_state "$user_id" "monet.blurtab.com.tencent.mm" enable
  else
    set_overlay_state "$user_id" "monet.solidtab.com.tencent.mm" enable
  fi
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

for user_id in $(list_target_users); do
  restore_overlay_state "$user_id"
  am force-stop --user "$user_id" "$TARGET_PACKAGE" 2>/dev/null
done
