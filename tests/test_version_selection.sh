#!/system/bin/sh
set -eu
. "$1/common.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

is_play_wechat_version 3182
! is_mainland_wechat_version 3182
is_mainland_wechat_version 3200
! is_play_wechat_version 3200
uses_image_bubble_overlay 3182
uses_image_bubble_overlay 3200
! uses_image_bubble_overlay 3084
! is_supported_wechat_version 9999

mkdir -p "$fixture/files" "$fixture/system/priv-app/MonetWeChat" "$fixture/system/priv-app/MonetWeChatBadge"
printf legacy > "$fixture/files/MonetWeChat.apk"
printf old-base > "$fixture/system/priv-app/MonetWeChat/MonetWeChat.apk"
printf old-badge > "$fixture/system/priv-app/MonetWeChatBadge/MonetWeChatBadge.apk"
WECHAT_VERSION_CODE=3200
! overlay_source_apk "$fixture" MonetWeChat
WECHAT_VERSION_CODE=3182
! overlay_source_apk "$fixture" MonetWeChat
WECHAT_VERSION_CODE=3160
[ "$(overlay_source_apk "$fixture" MonetWeChat)" = "$fixture/files/MonetWeChat.apk" ]

WECHAT_VERSION_CODE=3200
printf cn-base > "$fixture/files/MonetWeChat-3200.apk"
# Missing one selected package must not partially replace the base package.
! refresh_versioned_overlays "$fixture"
[ "$(cat "$fixture/system/priv-app/MonetWeChat/MonetWeChat.apk")" = old-base ]
printf cn-badge > "$fixture/files/MonetWeChatBadge-3200.apk"
refresh_versioned_overlays "$fixture"
cmp "$fixture/files/MonetWeChat-3200.apk" "$fixture/system/priv-app/MonetWeChat/MonetWeChat.apk"
cmp "$fixture/files/MonetWeChatBadge-3200.apk" "$fixture/system/priv-app/MonetWeChatBadge/MonetWeChatBadge.apk"
echo 'Channel selection, fallback refusal and complete selected-package refresh passed.'
