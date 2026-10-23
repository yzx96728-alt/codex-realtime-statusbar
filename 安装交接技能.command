#!/bin/bash
set -euo pipefail

# No Python, network, configuration changes, or background services.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/skills/handoff"
USER_DIRECTORY="$HOME"
CODEX_DIRECTORY="${CODEX_HOME:-$HOME/.codex}"
REPLACE=false
CUSTOM_USER=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --replace) REPLACE=true; shift ;;
        --user-home) USER_DIRECTORY="$2"; CUSTOM_USER=true; shift 2 ;;
        --codex-home) CODEX_DIRECTORY="$2"; shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done
if $CUSTOM_USER; then
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
    while IFS= read -r -d '' file; do
        if /usr/bin/awk '/^---[[:space:]]*$/ { section++; next } section == 1 && /^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); if ($0 == "handoff") found=1 } END { exit !found }' "$file"; then
            candidate="$(cd "$(dirname "$file")" && pwd -P)"
            found=false
            for existing in "${CANDIDATES[@]+${CANDIDATES[@]}}"; do
                [ "$existing" != "$candidate" ] || found=true
            done
            $found || CANDIDATES+=("$candidate")
        fi
    done < <(/usr/bin/find -L "$root" -type f -name SKILL.md -print0)
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
    if ! $REPLACE; then
        printf '已有技能 / Existing skill: %s\n备份后替换？Replace after backup? [y/N] ' "$DESTINATION"
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
