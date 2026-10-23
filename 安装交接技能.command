#!/bin/bash
set -euo pipefail
umask 077

# No Python, network, configuration changes, or background services.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/skills/handoff"
USER_DIRECTORY="$HOME"
CODEX_DIRECTORY="${CODEX_HOME:-$HOME/.codex}"
REPLACE=false
CUSTOM_USER=false
CUSTOM_CODEX=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --replace) REPLACE=true; shift ;;
        --user-home) USER_DIRECTORY="$2"; CUSTOM_USER=true; shift 2 ;;
        --codex-home) CODEX_DIRECTORY="$2"; CUSTOM_CODEX=true; shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done
if $CUSTOM_USER && ! $CUSTOM_CODEX; then
    # Isolated installs/tests must not inspect or modify the real user's skills.
    CODEX_DIRECTORY="$USER_DIRECTORY/.codex"
fi
case "$USER_DIRECTORY" in /*) ;; *) printf 'User directory must be absolute.\n' >&2; exit 1 ;; esac
for relative in SKILL.md agents/openai.yaml references/handoff.md; do
    [ -f "$SOURCE/$relative" ] || { printf 'Missing skill file: %s\n' "$relative" >&2; exit 1; }
done

ROOTS=("$USER_DIRECTORY/.agents/skills" "$USER_DIRECTORY/.codex/skills" "$CODEX_DIRECTORY/skills")
CANDIDATES=()
for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    SCAN_LIST="$(mktemp "${TMPDIR:-/tmp}/handoff-scan.XXXXXX")"
    if ! /usr/bin/find -L "$root" -type f -name SKILL.md -print0 > "$SCAN_LIST"; then
        rm -f "$SCAN_LIST"
        printf '无法完整检查技能目录，停止更新 / Could not fully inspect skill directory: %s\n' "$root" >&2
        exit 1
    fi
    while IFS= read -r -d '' file; do
        if /usr/bin/awk '/^---[[:space:]]*$/ { section++; next } section == 1 && /^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); if ($0 == "handoff") found=1 } END { exit !found }' "$file"; then
            candidate="$(cd "$(dirname "$file")" && pwd -P)"
            found=false
            for existing in "${CANDIDATES[@]+${CANDIDATES[@]}}"; do
                [ "$existing" != "$candidate" ] || found=true
            done
            $found || CANDIDATES+=("$candidate")
        fi
    done < "$SCAN_LIST"
    rm -f "$SCAN_LIST"
done
if [ "${#CANDIDATES[@]}" -gt 1 ]; then
    printf '发现多份同名技能，请先选择保留哪一份。Multiple handoff skills found; no changes made:\n' >&2
    printf '  %s\n' "${CANDIDATES[@]}" >&2
    exit 1
fi
DESTINATION="$USER_DIRECTORY/.agents/skills/handoff"
if [ "${#CANDIDATES[@]}" -eq 1 ]; then DESTINATION="${CANDIDATES[0]}"; fi
if [ -e "$DESTINATION" ] || [ -L "$DESTINATION" ]; then
    if [ ! -f "$DESTINATION/SKILL.md" ] || [ -L "$DESTINATION" ]; then
        printf 'Destination is not a regular skill folder; inspect it manually: %s\n' "$DESTINATION" >&2; exit 1
    fi
    identical=true
    for relative in SKILL.md agents/openai.yaml references/handoff.md; do
        cmp -s "$SOURCE/$relative" "$DESTINATION/$relative" || identical=false
    done
    if $identical; then
        printf '必要文件完全相同，保留附加文件并跳过 / Required files identical; extra files retained, skipped: %s\n' "$DESTINATION"
        exit 0
    fi
    if ! $REPLACE; then
        printf '已有技能 / Existing skill: %s\n必要文件不同，可能有自定义修改；技能未声明版本。备份后替换？Files differ; may contain customizations (no declared skill version). Replace after backup? [y/N] ' "$DESTINATION"
        answer=''
        IFS= read -r answer || true
        case "$answer" in y|Y|yes|YES) ;; *) printf '已取消，未更改。Cancelled; no changes made.\n'; exit 0 ;; esac
    fi
fi

mkdir -p "$(dirname "$DESTINATION")"
STAGING="$(mktemp -d "$(dirname "$DESTINATION")/.handoff-install.XXXXXX")"
BACKUP=''
COMMITTED=false
cleanup() {
    result=$?
    if ! $COMMITTED && [ -n "$BACKUP" ] && [ ! -e "$DESTINATION" ]; then mv "$BACKUP" "$DESTINATION"; fi
    if [ -d "$STAGING" ]; then rm -rf "$STAGING"; fi
    return "$result"
}
trap cleanup EXIT
mkdir -p "$STAGING/agents" "$STAGING/references"
cp "$SOURCE/SKILL.md" "$STAGING/SKILL.md"
cp "$SOURCE/agents/openai.yaml" "$STAGING/agents/openai.yaml"
cp "$SOURCE/references/handoff.md" "$STAGING/references/handoff.md"
for relative in SKILL.md agents/openai.yaml references/handoff.md; do
    cmp -s "$SOURCE/$relative" "$STAGING/$relative" || { printf 'Skill staging mismatch\n' >&2; exit 1; }
done
if [ -d "$DESTINATION" ]; then
    mkdir -p "$USER_DIRECTORY/.codex-handoff-backups"
    BACKUP_PARENT="$(mktemp -d "$USER_DIRECTORY/.codex-handoff-backups/handoff-$(date +%Y%m%d-%H%M%S).XXXXXX")"
    BACKUP="$BACKUP_PARENT/handoff"
    mv "$DESTINATION" "$BACKUP"
fi
mv "$STAGING" "$DESTINATION"
COMMITTED=true
printf '安装完成 / Installed: %s\n' "$DESTINATION"
if [ -n "$BACKUP" ]; then printf '旧版备份 / Previous skill backup: %s\n' "$BACKUP"; fi
printf '在 Codex 输入 $handoff 使用；若未出现，请重启 Codex。\nType $handoff in Codex; restart Codex if it is not discovered.\n'
