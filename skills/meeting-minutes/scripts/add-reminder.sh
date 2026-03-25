#!/usr/bin/env bash
# =============================================================================
# Meeting Minutes Skill — Apple 提醒事项写入脚本
# =============================================================================
# 用法:
#   add-reminder.sh --title "待办描述" [--due "YYYY-MM-DD"] [--list "列表名"] [--notes "备注"]
#
# 降级策略:
#   Level 1: remindctl CLI (最完整功能)
#   Level 2: osascript 操作提醒事项 App (macOS 原生)
#   Level 3: 输出结构化纯文本 (兜底)
# =============================================================================

set -euo pipefail

# --- 参数解析 ---
TITLE=""
DUE=""
LIST="会议待办"
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)  TITLE="$2";  shift 2 ;;
        --due)    DUE="$2";    shift 2 ;;
        --list)   LIST="$2";   shift 2 ;;
        --notes)  NOTES="$2";  shift 2 ;;
        -h|--help)
            echo "用法: add-reminder.sh --title \"待办描述\" [--due \"YYYY-MM-DD\"] [--list \"列表名\"] [--notes \"备注\"]"
            exit 0
            ;;
        *) echo "❌ 未知参数: $1"; exit 1 ;;
    esac
done

# --- 参数校验 ---
if [[ -z "$TITLE" ]]; then
    echo "❌ 缺少必填参数 --title"
    exit 1
fi

# --- 辅助函数 ---
cmd_exists() { command -v "$1" &>/dev/null; }

try_auto_install_remindctl() {
    if cmd_exists brew; then
        echo "ℹ️  正在自动安装 remindctl..."
        if brew install steipete/tap/remindctl 2>/dev/null; then
            echo "✅ remindctl 安装成功"
            return 0
        fi
    fi
    return 1
}

# --- Level 1: remindctl ---
add_via_remindctl() {
    if ! cmd_exists remindctl; then
        try_auto_install_remindctl || return 1
    fi

    local args=("add" "--title" "$TITLE" "--list" "$LIST")
    if [[ -n "$DUE" ]]; then
        args+=("--due" "$DUE")
    fi

    if remindctl "${args[@]}" 2>/dev/null; then
        echo "✅ 已通过 remindctl 添加提醒: $TITLE"
        return 0
    fi
    return 1
}

# --- Level 2: osascript ---
add_via_osascript() {
    if ! cmd_exists osascript; then
        return 1
    fi

    # 确保提醒事项列表存在
    osascript -e "
        tell application \"Reminders\"
            try
                set targetList to list \"$LIST\"
            on error
                make new list with properties {name:\"$LIST\"}
                set targetList to list \"$LIST\"
            end try
        end tell
    " 2>/dev/null || true

    # 构建 AppleScript
    local script="
        tell application \"Reminders\"
            tell list \"$LIST\"
                set newReminder to make new reminder with properties {name:\"$TITLE\""

    if [[ -n "$NOTES" ]]; then
        script+=", body:\"$NOTES\""
    fi

    script+="}"

    # 设置截止日期
    if [[ -n "$DUE" ]]; then
        # 解析日期（支持 YYYY-MM-DD 和 YYYY-MM-DD HH:mm）
        if [[ "$DUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            script+="
                set due date of newReminder to date \"${DUE} 09:00:00\""
        elif [[ "$DUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
            script+="
                set due date of newReminder to date \"${DUE}:00\""
        fi
    fi

    script+="
            end tell
        end tell
    "

    if osascript -e "$script" 2>/dev/null; then
        echo "✅ 已通过 osascript 添加提醒: $TITLE"
        return 0
    fi
    return 1
}

# --- Level 3: 纯文本输出 ---
output_plain_text() {
    echo ""
    echo "📋 待办事项（请手动添加到提醒事项）"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  标题: $TITLE"
    [[ -n "$DUE" ]] && echo "  截止: $DUE"
    echo "  列表: $LIST"
    [[ -n "$NOTES" ]] && echo "  备注: $NOTES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚠️ 当前环境无法自动添加提醒事项，请手动添加上述待办。"
}

# --- 主流程: 依次尝试降级 ---
if add_via_remindctl; then
    exit 0
fi

echo "⚠️ remindctl 不可用，尝试 osascript 降级..."

if add_via_osascript; then
    exit 0
fi

echo "⚠️ osascript 也不可用，输出纯文本..."
output_plain_text
exit 0
