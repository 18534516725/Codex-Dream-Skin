#!/bin/bash

set -euo pipefail
export LC_ALL=C

REPOSITORY="18534516725/Codex-Dream-Skin"
VERSION=""
TARGET_APP=""
PARENT_PID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --target-app) TARGET_APP="${2:-}"; shift 2 ;;
    --parent-pid) PARENT_PID="${2:-}"; shift 2 ;;
    *) printf 'Unknown updater argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

reopen_current_app_on_failure() {
  [ -n "$TARGET_APP" ] && [ "${TARGET_APP#/}" != "$TARGET_APP" ] \
    && [ -d "$TARGET_APP" ] && [ ! -L "$TARGET_APP" ] || return 0
  local current_id
  current_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)"
  [ "$current_id" = "cc.dreamskin.menubar" ] || return 0
  /usr/bin/open "$TARGET_APP" >/dev/null 2>&1 || true
}

fail() {
  reopen_current_app_on_failure
  /usr/bin/osascript - "$*" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display alert "Nexo Codex Skin 更新失败" message (item 1 of argv) buttons {"好"}
end run
APPLESCRIPT
  printf 'Nexo Codex Skin update failed: %s\n' "$*" >&2
  exit 1
}

valid_download_host() {
  case "$1" in
    https://github.com/*|https://objects.githubusercontent.com/*|https://release-assets.githubusercontent.com/*)
      return 0 ;;
    *) return 1 ;;
  esac
}

download() {
  local url="$1"
  local output="$2"
  local effective
  effective="$(/usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --location --max-redirs 5 --connect-timeout 8 --max-time 180 \
    --retry 3 --retry-delay 2 --retry-all-errors --retry-max-time 60 \
    --user-agent 'CodexDreamSkin-AutoUpdate' --output "$output" \
    --write-out '%{url_effective}' "$url")" || fail "无法下载正式更新文件。"
  valid_download_host "$effective" || fail "更新下载跳转到了未获准的服务器。"
  [ -s "$output" ] || fail "下载的更新文件为空。"
}

printf '%s' "$VERSION" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "更新版本号不符合安全规则。"
[ -n "$TARGET_APP" ] && [ "${TARGET_APP#/}" != "$TARGET_APP" ] \
  || fail "目标 App 路径无效。"
[ -d "$TARGET_APP" ] && [ ! -L "$TARGET_APP" ] \
  || fail "当前助手 App 不存在或路径不安全。"
CURRENT_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$CURRENT_ID" = "cc.dreamskin.menubar" ] || fail "当前助手身份无法确认。"
printf '%s' "$PARENT_PID" | /usr/bin/grep -Eq '^[1-9][0-9]*$' || fail "助手进程标识无效。"

ARTIFACT="CodexDreamSkin-v$VERSION.dmg"
CHECKSUM="SHA256SUMS.txt"
BASE_URL="https://github.com/$REPOSITORY/releases/download/v$VERSION"
TMP="$(/usr/bin/mktemp -d /tmp/codex-dream-skin-update.XXXXXX)"
MOUNT="$TMP/mount"
BACKUP="$TARGET_APP.previous-update-$PARENT_PID"

cleanup() {
  if /sbin/mount | /usr/bin/grep -F -q " on $MOUNT "; then
    /usr/bin/hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "$TMP"
}
trap cleanup EXIT
/bin/mkdir -p "$MOUNT"

download "$BASE_URL/$CHECKSUM" "$TMP/$CHECKSUM"
download "$BASE_URL/$ARTIFACT" "$TMP/$ARTIFACT"
[ "$(/usr/bin/stat -f '%z' "$TMP/$ARTIFACT")" -le 67108864 ] || fail "更新安装包超过 64 MiB 安全上限。"

EXPECTED_SHA="$(/usr/bin/awk -v expected="$ARTIFACT" \
  '$1 ~ /^[0-9a-f]{64}$/ && $2 == expected { print $1 }' "$TMP/$CHECKSUM")"
[ -n "$EXPECTED_SHA" ] || fail "更新校验文件格式无效。"
ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$TMP/$ARTIFACT" | /usr/bin/awk '{print $1}')"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "更新安装包 SHA-256 校验失败。"

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$TMP/$ARTIFACT" >/dev/null
SOURCE_APP="$MOUNT/Codex Dream Skin.app"
[ -d "$SOURCE_APP" ] && [ ! -L "$SOURCE_APP" ] || fail "DMG 中缺少助手 App。"
NEW_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$SOURCE_APP/Contents/Info.plist")"
NEW_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$SOURCE_APP/Contents/Info.plist")"
ENGINE_VERSION="$(/usr/bin/tr -d '[:space:]' < "$SOURCE_APP/Contents/Resources/engine/VERSION")"
[ "$NEW_ID" = "cc.dreamskin.menubar" ] || fail "更新 App 身份不匹配。"
[ "$NEW_VERSION" = "$VERSION" ] && [ "$ENGINE_VERSION" = "$VERSION" ] \
  || fail "更新 App 与引擎版本不一致。"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP" || fail "更新 App 完整性校验失败。"
ARCHS="$(/usr/bin/lipo -archs "$SOURCE_APP/Contents/MacOS/CodexDreamSkinMenuBar")"
case " $ARCHS " in *" $(/usr/bin/uname -m) "*) ;; *) fail "更新 App 不支持当前电脑架构。" ;; esac

for _ in $(/usr/bin/jot 120); do
  /bin/kill -0 "$PARENT_PID" 2>/dev/null || break
  /bin/sleep 0.25
done
/bin/kill -0 "$PARENT_PID" 2>/dev/null && fail "旧版助手未能按时退出。"

[ ! -e "$BACKUP" ] || fail "检测到未完成的旧更新备份，已停止覆盖。"
/bin/mv "$TARGET_APP" "$BACKUP"
if ! /usr/bin/ditto "$SOURCE_APP" "$TARGET_APP" \
  || ! /usr/bin/codesign --verify --deep --strict "$TARGET_APP"; then
  /bin/rm -rf "$TARGET_APP"
  /bin/mv "$BACKUP" "$TARGET_APP"
  fail "新版助手写入失败，已经恢复旧版。"
fi
/bin/rm -rf "$BACKUP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
/usr/bin/open "$TARGET_APP"
