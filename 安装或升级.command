#!/bin/bash
# Unified local installer. No sudo, TCC changes, network, model or Codex settings.
set -euo pipefail
umask 077
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME='Codex实时状态栏.app'
BUNDLE_ID='local.cc.codex-usage-monitor'
USER_DIRECTORY="$HOME"
DESTINATION=''
EXISTING=''
NO_LAUNCH=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --user-home) USER_DIRECTORY="$2"; shift 2 ;;
        --destination) DESTINATION="$2"; shift 2 ;;
        --existing-app) EXISTING="$2"; shift 2 ;;
        --no-launch) NO_LAUNCH=true; shift ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done
fail() { printf '\n安装失败 / Installation failed: %s\n' "$*" >&2; exit 1; }
ask() { local answer=''; printf '%s [y/N] ' "$1"; IFS= read -r answer || true; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
info() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Contents/Info.plist"; }
validate() {
    [ -d "$1" ] && [ ! -L "$1" ] && [ "$(info "$1" CFBundleIdentifier)" = "$BUNDLE_ID" ] &&
    [ -x "$1/Contents/MacOS/CCUsage" ] && /usr/bin/codesign --verify --deep --strict "$1"
}
case "$USER_DIRECTORY" in /*) ;; *) fail 'User directory must be absolute.' ;; esac
SOURCE_APP="$SOURCE_DIR/$APP_NAME"
[ -f "$SOURCE_DIR/PayloadSHA256.txt" ] || fail '请从完整候选 ZIP 解压后运行。Extract the complete ZIP first.'
# Validate the distributed app, skill, scripts and instructions before executing helpers.
(cd "$SOURCE_DIR" && /usr/bin/shasum -a 256 -c PayloadSHA256.txt) || fail '下载文件校验失败 / Payload checksum mismatch.'
validate "$SOURCE_APP" || fail '应用签名或标识校验失败 / App validation failed.'
VERSION="$(info "$SOURCE_APP" CFBundleShortVersionString)"
HELPER="$SOURCE_APP/Contents/MacOS/CCUsage"
RUNNING="$("$HELPER" --installer-running)" || fail 'Cannot inspect running copies.'
# Offline isolated validation never terminates or launches real user processes.
OFFLINE=false
if $NO_LAUNCH && [ "$USER_DIRECTORY" != "$HOME" ]; then OFFLINE=true; RUNNING=''; fi
# Running copies take priority. No traversal of external disks or session logs.
CANDIDATES=()
add_candidate() {
    local path="$1" old
    [ -d "$path" ] || return 0
    [ "$(info "$path" CFBundleIdentifier 2>/dev/null || true)" = "$BUNDLE_ID" ] || return 0
    for old in "${CANDIDATES[@]+${CANDIDATES[@]}}"; do [ "$old" != "$path" ] || return 0; done
    CANDIDATES+=("$path")
}
if [ -n "$EXISTING" ]; then
    add_candidate "$EXISTING"
    [ "${#CANDIDATES[@]}" -eq 1 ] || fail '指定旧应用无效 / Invalid existing app.'
else
    while IFS= read -r path; do [ -z "$path" ] || add_candidate "$path"; done <<< "$RUNNING"
    if ! $OFFLINE; then add_candidate "/Applications/$APP_NAME"; fi
    add_candidate "$USER_DIRECTORY/Applications/$APP_NAME"
    # Spotlight may be disabled; it is only a discovery aid, never a prerequisite.
    if [ "$USER_DIRECTORY" = "$HOME" ]; then
        while IFS= read -r path; do
            case "$path" in "$SOURCE_DIR"/*|*/build/*|*/dist/*|*/Backups/*) continue ;; esac
            add_candidate "$path"
        done < <(/usr/bin/mdfind -onlyin "$USER_DIRECTORY" "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)
    fi
    if [ "${#CANDIDATES[@]}" -gt 1 ]; then
        printf '发现多份旧应用 / Multiple copies:\n'; printf '  %s\n' "${CANDIDATES[@]}"
        printf '输入要迁移的应用完整路径；留空取消 / Existing app path (empty cancels): '
        IFS= read -r EXISTING || true
        found=false; for path in "${CANDIDATES[@]}"; do [ "$EXISTING" != "$path" ] || found=true; done
        $found || fail '未选择已列出的应用，未更改 / No listed app selected.'
    elif [ "${#CANDIDATES[@]}" -eq 1 ]; then EXISTING="${CANDIDATES[0]}"; fi
fi
if [ -n "$EXISTING" ]; then printf '旧版 / Previous: %s (%s)\n' "$EXISTING" "$(info "$EXISTING" CFBundleShortVersionString)"; fi
if [ -z "$DESTINATION" ]; then
    if [ -w /Applications ]; then DESTINATION="/Applications/$APP_NAME"
    else
        ask '/Applications 不可写。改用 ~/Applications？Use your user Applications folder without administrator access?' || exit 0
        DESTINATION="$USER_DIRECTORY/Applications/$APP_NAME"
    fi
fi
if $OFFLINE; then
    for path in "$DESTINATION" "${EXISTING:-$USER_DIRECTORY/unused}"; do
        case "$path" in "$USER_DIRECTORY"/*) ;; *) fail 'Offline paths must stay inside the isolated user directory.' ;; esac
        case "$path" in */../*|*/./*) fail 'Ambiguous offline path.' ;; esac
    done
fi
case "$DESTINATION" in /*.app) ;; *) fail 'Destination must be an absolute .app path.' ;; esac
[ ! -L "$DESTINATION" ] || fail 'Destination is a symbolic link; inspect manually.'
[ "$DESTINATION" != "$SOURCE_APP" ] || fail 'Cannot replace the unpacked source app.'
if [ -e "$DESTINATION" ] && [ "$DESTINATION" != "$EXISTING" ]; then fail '目标已存在其他副本；请先明确处理 / Destination already occupied.'; fi
printf '安装 %s → %s\n' "$VERSION" "$DESTINATION"
ask '继续安装／升级？Continue installation/upgrade?' || exit 0
LOGIN=keep
printf '登录时启动并隐藏待命；主动退出后不会立即重启。\nStart at login and wait hidden; deliberate Quit is respected.\n'
printf '登录启动：y 启用，n 禁用，回车保留现状 / Login: y enable, n disable, Enter keep: '
answer=''; IFS= read -r answer || true
case "$answer" in y|Y) LOGIN=enable ;; n|N) LOGIN=disable ;; '') ;; *) fail 'Invalid login choice.' ;; esac
PARENT="$(dirname "$DESTINATION")"
mkdir -p "$PARENT"
STAGE="$(mktemp -d "$PARENT/.codex-statusbar-install.XXXXXX")"
LOCK_ROOT="$USER_DIRECTORY/Library/Application Support/CodexRealtimeStatusbar"
mkdir -p "$LOCK_ROOT"
LOCK="$LOCK_ROOT/install.lock"
if ! mkdir "$LOCK"; then rmdir "$STAGE"; fail "已有安装正在进行；若上次异常中断，确认无安装进程后移除锁目录 / Installation lock exists: $LOCK"; fi
BACKUP=''; MOVED=false; INSTALLED=false; COMMITTED=false; LAUNCHED=false
cleanup() {
    result=$?
    if ! $COMMITTED && { $MOVED || $INSTALLED; }; then
        if $LAUNCHED; then "$HELPER" --installer-stop "$DESTINATION" || true; fi
        if [ -d "$DESTINATION" ]; then mv "$DESTINATION" "$STAGE/failed.app" || true; fi
        if $MOVED && [ -d "$STAGE/previous.app" ]; then
            mv "$STAGE/previous.app" "$EXISTING" || printf '自动恢复失败；从 %s 恢复至 %s\n' "$BACKUP" "$EXISTING" >&2
        fi
        printf '升级未完成，旧版已尝试恢复。Backup: %s\n' "$BACKUP" >&2
    fi
    if $COMMITTED && [ -d "$STAGE/previous.app" ]; then rm -rf "$STAGE/previous.app"; fi
    # Only remove this installer's own staging tree. Preserve recovery material on rollback failure.
    if [ -d "$STAGE/previous.app" ]; then printf '保留恢复目录 / Recovery directory: %s\n' "$STAGE" >&2
    else rm -rf "$STAGE"; fi
    rmdir "$LOCK" || true
    if [ "$result" -ne 0 ]; then printf '原配置和其他技能未被删除。可从上面的备份复制回原路径。\nOriginal settings retained; restore the app backup to its original path if needed.\n' >&2; fi
    if [ -t 0 ] && ! $NO_LAUNCH; then printf '按回车关闭 / Press Return to close…'; IFS= read -r _ || true; fi
    return "$result"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGE/new.app"
validate "$STAGE/new.app" || fail 'Staged app validation failed.'
[ "$(info "$STAGE/new.app" CFBundleShortVersionString)" = "$VERSION" ] || fail 'Staged version mismatch.'
if [ -n "$EXISTING" ]; then
    BACKUP_ROOT="$USER_DIRECTORY/Library/Application Support/CodexRealtimeStatusbar/Backups"
    mkdir -p "$BACKUP_ROOT"; chmod 700 "$BACKUP_ROOT"
    BACKUP="$(mktemp -d "$BACKUP_ROOT/upgrade-$(date +%Y%m%d-%H%M%S).XXXXXX")/previous.app"
    # Native graceful termination. Another running copy causes a stop before replacement.
    $OFFLINE || "$HELPER" --installer-stop "$EXISTING" || fail '请先正常退出其他副本 / Quit was refused or another copy is running.'
    /usr/bin/ditto "$EXISTING" "$BACKUP"
    # Compare copies before removing the original from its path.
    /usr/bin/diff -qr "$EXISTING" "$BACKUP" >/dev/null || fail 'Backup integrity check failed.'
    printf '备份 / Backup: %s\n' "$BACKUP"
    mv "$EXISTING" "$STAGE/previous.app"; MOVED=true
else
    [ -z "$RUNNING" ] || fail 'Another app copy is running; no installation performed.'
fi
mv "$STAGE/new.app" "$DESTINATION"; INSTALLED=true
validate "$DESTINATION" || fail 'Installed signature validation failed.'
[ "$(info "$DESTINATION" CFBundleShortVersionString)" = "$VERSION" ] || fail 'Installed version mismatch.'
# Skill cancellation/duplicates are reported independently and never silently overridden.
SKILL_ARGS=()
if [ "$USER_DIRECTORY" != "$HOME" ]; then SKILL_ARGS=(--user-home "$USER_DIRECTORY"); fi
if ! /bin/bash "$SOURCE_DIR/安装交接技能.command" "${SKILL_ARGS[@]+${SKILL_ARGS[@]}}"; then
    printf '小窗验证通过；技能更新未完成，请按上方位置处理后重试技能入口。\nApp verified; skill update paused/failed. Review paths above and retry the skill installer.\n' >&2
fi
if ! $NO_LAUNCH; then
    OPEN_ARGS=(); case "$LOGIN" in enable) OPEN_ARGS=(--args --enable-login) ;; disable) OPEN_ARGS=(--args --disable-login) ;; esac
    /usr/bin/open -g "$DESTINATION" "${OPEN_ARGS[@]+${OPEN_ARGS[@]}}" || fail 'Launch failed.'
    LAUNCHED=true
    sleep 1
    "$HELPER" --installer-running | /usr/bin/grep -Fx "$DESTINATION" >/dev/null || fail 'App did not remain running; old app will be restored.'
    STATUS="$("$DESTINATION/Contents/MacOS/CCUsage" --installation-status)" || fail 'Basic status check failed.'
    printf '%s\n' "$STATUS"
    printf '若 accessibility_trusted 为 false：系统设置 → 隐私与安全性 → 辅助功能，添加上面最终路径并亲自授权。\nIf false, authorize this final app in System Settings → Privacy & Security → Accessibility.\n'
    if [[ "$STATUS" == *'"accessibility_trusted":false'* ]] && ask '现在打开辅助功能设置？Open Accessibility settings now?'; then
        /usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || true
    fi
    printf 'Ad-hoc 更新可能需重新授权；不自动删除旧权限。登录项状态以系统设置为准。\nAd-hoc upgrades may need renewed consent. Login items remain subject to System Settings.\n'
else
    printf '未启动：跳过登录项变更和实时权限检查 / No launch: login and live permission checks skipped.\n'
fi
COMMITTED=true
printf '应用安装验证完成 / App installation verified: %s (%s)\n' "$DESTINATION" "$VERSION"
