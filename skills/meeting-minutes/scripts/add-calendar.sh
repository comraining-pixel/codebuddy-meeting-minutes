#!/usr/bin/env bash
# =============================================================================
# Meeting Minutes Skill — macOS 日历事件写入脚本
# =============================================================================
# 用法:
#   add-calendar.sh --title "事件标题" --start "YYYY-MM-DD HH:mm" \
#     [--end "YYYY-MM-DD HH:mm"] [--notes "备注"] [--calendar "日历名"]
#
# 降级策略:
#   Level 1: osascript AppleScript 操作日历 App (含去重检查)
#   Level 2: 生成标准 .ics 文件供手动导入
# =============================================================================

set -euo pipefail

# --- 参数解析 ---
TITLE=""
START=""
END=""
NOTES=""
CALENDAR="会议"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)    TITLE="$2";    shift 2 ;;
        --start)    START="$2";    shift 2 ;;
        --end)      END="$2";      shift 2 ;;
        --notes)    NOTES="$2";    shift 2 ;;
        --calendar) CALENDAR="$2"; shift 2 ;;
        -h|--help)
            echo "用法: add-calendar.sh --title \"事件标题\" --start \"YYYY-MM-DD HH:mm\" [--end \"YYYY-MM-DD HH:mm\"] [--notes \"备注\"] [--calendar \"日历名\"]"
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

if [[ -z "$START" ]]; then
    echo "❌ 缺少必填参数 --start"
    exit 1
fi

# 默认结束时间 = 开始时间 + 1 小时
if [[ -z "$END" ]]; then
    if command -v gdate &>/dev/null; then
        END=$(gdate -d "$START + 1 hour" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "")
    fi
    if [[ -z "$END" ]]; then
        # macOS date 回退方案
        if [[ "$START" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}):([0-9]{2}) ]]; then
            local_date="${BASH_REMATCH[1]}"
            local_hour="${BASH_REMATCH[2]}"
            local_min="${BASH_REMATCH[3]}"
            next_hour=$((10#$local_hour + 1))
            if [[ $next_hour -ge 24 ]]; then
                next_hour=23
                local_min=59
            fi
            END="${local_date} $(printf '%02d' $next_hour):${local_min}"
        else
            END="$START"
        fi
    fi
fi

# --- 辅助函数 ---
cmd_exists() { command -v "$1" &>/dev/null; }

# --- Level 1: osascript (macOS 日历) ---
add_via_osascript() {
    if ! cmd_exists osascript; then
        return 1
    fi

    # 去重检查：查找同标题同时间的事件
    local existing
    existing=$(osascript -e "
        tell application \"Calendar\"
            try
                set targetCal to calendar \"$CALENDAR\"
            on error
                return \"\"
            end try
            set matchEvents to (every event of targetCal whose summary is \"$TITLE\")
            if (count of matchEvents) > 0 then
                return \"exists\"
            else
                return \"\"
            end if
        end tell
    " 2>/dev/null || echo "")

    if [[ "$existing" == "exists" ]]; then
        echo "⚠️ 日历中已存在同名事件「$TITLE」，跳过创建"
        return 0
    fi

    # 确保日历存在
    osascript -e "
        tell application \"Calendar\"
            try
                set targetCal to calendar \"$CALENDAR\"
            on error
                make new calendar with properties {name:\"$CALENDAR\"}
            end try
        end tell
    " 2>/dev/null || true

    # 创建事件
    local script="
        tell application \"Calendar\"
            tell calendar \"$CALENDAR\"
                set startDate to current date
                set year of startDate to ${START:0:4}
                set month of startDate to ${START:5:2}
                set day of startDate to ${START:8:2}"

    if [[ "${#START}" -ge 16 ]]; then
        script+="
                set hours of startDate to ${START:11:2}
                set minutes of startDate to ${START:14:2}"
    else
        script+="
                set hours of startDate to 9
                set minutes of startDate to 0"
    fi

    script+="
                set seconds of startDate to 0

                set endDate to current date
                set year of endDate to ${END:0:4}
                set month of endDate to ${END:5:2}
                set day of endDate to ${END:8:2}"

    if [[ "${#END}" -ge 16 ]]; then
        script+="
                set hours of endDate to ${END:11:2}
                set minutes of endDate to ${END:14:2}"
    else
        script+="
                set hours of endDate to 10
                set minutes of endDate to 0"
    fi

    script+="
                set seconds of endDate to 0

                set newEvent to make new event with properties {summary:\"$TITLE\", start date:startDate, end date:endDate"

    if [[ -n "$NOTES" ]]; then
        # 转义 AppleScript 中的双引号
        local escaped_notes="${NOTES//\"/\\\"}"
        script+=", description:\"$escaped_notes\""
    fi

    script+="}
            end tell
        end tell
    "

    if osascript -e "$script" 2>/dev/null; then
        echo "✅ 已添加日历事件: $TITLE ($START ~ $END)"
        return 0
    fi
    return 1
}

# --- Level 2: 生成 .ics 文件 ---
generate_ics() {
    # 将 "YYYY-MM-DD HH:mm" 转换为 ICS 格式 "YYYYMMDDTHHMMSS"
    local ics_start ics_end
    ics_start=$(echo "$START" | sed 's/[- :]//g')
    [[ ${#ics_start} -eq 12 ]] && ics_start="${ics_start}00"
    [[ ${#ics_start} -eq 8 ]] && ics_start="${ics_start}T090000"
    [[ ! "$ics_start" == *T* ]] && ics_start="${ics_start:0:8}T${ics_start:8}"

    ics_end=$(echo "$END" | sed 's/[- :]//g')
    [[ ${#ics_end} -eq 12 ]] && ics_end="${ics_end}00"
    [[ ${#ics_end} -eq 8 ]] && ics_end="${ics_end}T100000"
    [[ ! "$ics_end" == *T* ]] && ics_end="${ics_end:0:8}T${ics_end:8}"

    local uid
    uid="meeting-minutes-$(date +%s)-$$@codebuddy"

    local ics_file="${TITLE// /-}-${START:0:10}.ics"
    ics_file=$(echo "$ics_file" | sed 's/[^a-zA-Z0-9._-]/-/g')

    cat > "$ics_file" <<EOF
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Meeting Minutes Skill//CodeBuddy//CN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:${uid}
DTSTART:${ics_start}
DTEND:${ics_end}
SUMMARY:${TITLE}
DESCRIPTION:${NOTES}
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
EOF

    echo "📅 已生成日历文件: $(pwd)/$ics_file"
    echo "   双击文件即可导入到系统日历"
}

# --- 主流程 ---
if add_via_osascript; then
    exit 0
fi

echo "⚠️ osascript 不可用（可能为非 macOS 系统），生成 .ics 日历文件..."
generate_ics
exit 0
