#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="$MODDIR/config.conf"
CONFIG_FILE="$CONFIG"

. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

if [ "$(get_conf_value "$CONFIG" "is_first_install" "0")" = "1" ] && [ "$(get_conf_value "$CONFIG" "enable_multi_user" "0")" = "1" ]; then
  install_for_secondary_users "$MODDIR" || echo '! 部分次要用户覆盖未能启用，请查看上方错误。'
fi

if [ "$(get_conf_value "$CONFIG" "blur_enabled" "0")" = "1" ]; then
  if apply_blur_overlay "$MODDIR" "$(list_target_users)" "-"; then
    am force-stop com.tencent.mm 2>/dev/null
  fi
fi

if [ "$(get_conf_value "$CONFIG" "is_first_install" "0")" = "1" ]; then
  set_conf_value "$CONFIG" "is_first_install" "0"
fi
