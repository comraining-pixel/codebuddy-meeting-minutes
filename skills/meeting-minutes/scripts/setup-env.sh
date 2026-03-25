#!/usr/bin/env bash
# =============================================================================
# Meeting Minutes Skill — 环境检测与自动安装脚本
# =============================================================================
# 用法:
#   source ~/.codebuddy/skills/meeting-minutes/scripts/setup-env.sh
#   source ~/.codebuddy/skills/meeting-minutes/scripts/setup-env.sh --check-only
#   source ~/.codebuddy/skills/meeting-minutes/scripts/setup-env.sh --component ocr
#
# 输出环境能力变量:
#   HAS_VISION_OCR  — macOS Vision Framework OCR 可用 (true/false)
#   HAS_TESSERACT   — tesseract CLI 可用 (true/false)
#   HAS_WHISPER     — whisper (local-whisper 或独立 CLI) 可用 (true/false)
#   HAS_REMINDCTL   — remindctl CLI 可用 (true/false)
#   HAS_OSASCRIPT   — osascript 可用 (true/false)
#   HAS_FFMPEG      — ffmpeg 可用 (true/false)
#   HAS_PYTHON3     — Python 3 可用 (true/false)
#   HAS_HOMEBREW    — Homebrew 可用 (true/false)
#   OCR_METHOD      — 可用的 OCR 方法 (vision/tesseract/none)
#   WHISPER_CMD     — whisper 命令路径或空
#
# 返回值: 0=全部就绪 1=部分降级 2=关键依赖缺失
# =============================================================================

set -euo pipefail

# --- 配置 ---
SKILL_DIR="${HOME}/.codebuddy/skills/meeting-minutes"
VENV_DIR="${SKILL_DIR}/scripts/.venv"
ENV_READY_FILE="${SKILL_DIR}/scripts/.env-ready"
CHECK_ONLY=false
TARGET_COMPONENT=""

# --- 解析参数 ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only) CHECK_ONLY=true; shift ;;
        --component) TARGET_COMPONENT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# --- 初始化能力变量 ---
export HAS_VISION_OCR=false
export HAS_TESSERACT=false
export HAS_WHISPER=false
export HAS_REMINDCTL=false
export HAS_OSASCRIPT=false
export HAS_FFMPEG=false
export HAS_PYTHON3=false
export HAS_HOMEBREW=false
export OCR_METHOD="none"
export WHISPER_CMD=""

# --- 辅助函数 ---
log_info()  { echo "ℹ️  $*"; }
log_ok()    { echo "✅ $*"; }
log_warn()  { echo "⚠️  $*"; }
log_err()   { echo "❌ $*"; }
log_skip()  { echo "⏭️  $*"; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

get_macos_version() {
    if is_macos; then
        sw_vers -productVersion 2>/dev/null | cut -d. -f1
    else
        echo "0"
    fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# --- 检测与安装: Homebrew ---
check_homebrew() {
    if cmd_exists brew; then
        HAS_HOMEBREW=true
        log_ok "Homebrew 已安装"
        return 0
    fi

    if ! is_macos; then
        log_warn "非 macOS 系统，跳过 Homebrew"
        return 1
    fi

    if $CHECK_ONLY; then
        log_warn "Homebrew 未安装 (--check-only 模式，跳过安装)"
        return 1
    fi

    log_info "正在自动安装 Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        log_err "Homebrew 安装失败"
        return 1
    }

    # 配置 PATH（Apple Silicon 和 Intel 路径不同）
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    HAS_HOMEBREW=true
    log_ok "Homebrew 安装成功"
}

# --- 检测与安装: Python 3 ---
check_python3() {
    if cmd_exists python3; then
        HAS_PYTHON3=true
        log_ok "Python 3 已安装 ($(python3 --version 2>&1))"
        return 0
    fi

    if $CHECK_ONLY; then
        log_warn "Python 3 未安装 (--check-only 模式)"
        return 1
    fi

    if $HAS_HOMEBREW; then
        log_info "正在通过 Homebrew 安装 Python 3..."
        brew install python3 && {
            HAS_PYTHON3=true
            log_ok "Python 3 安装成功"
            return 0
        }
    fi

    # macOS 自带 python3 (Xcode CLT)
    if is_macos; then
        log_info "尝试通过 Xcode Command Line Tools 获取 Python 3..."
        xcode-select --install 2>/dev/null || true
        if cmd_exists python3; then
            HAS_PYTHON3=true
            log_ok "Python 3 可用 (Xcode CLT)"
            return 0
        fi
    fi

    log_err "Python 3 安装失败"
    return 1
}

# --- 检测与安装: ffmpeg ---
check_ffmpeg() {
    if cmd_exists ffmpeg; then
        HAS_FFMPEG=true
        log_ok "ffmpeg 已安装"
        return 0
    fi

    if $CHECK_ONLY; then
        log_warn "ffmpeg 未安装 (--check-only 模式)"
        return 1
    fi

    if $HAS_HOMEBREW; then
        log_info "正在通过 Homebrew 安装 ffmpeg..."
        brew install ffmpeg && {
            HAS_FFMPEG=true
            log_ok "ffmpeg 安装成功"
            return 0
        }
    fi

    log_warn "ffmpeg 未安装，视频文件处理将不可用"
    return 1
}

# --- 检测与安装: OCR 能力 ---
check_ocr() {
    # Level 1: macOS Vision Framework
    if is_macos; then
        local macos_ver
        macos_ver=$(get_macos_version)
        if [[ "$macos_ver" -ge 12 ]]; then
            # 检查 pyobjc 是否可用
            if $HAS_PYTHON3; then
                # 检查或创建 venv 并安装 pyobjc
                if [[ -f "${VENV_DIR}/bin/python3" ]] && "${VENV_DIR}/bin/python3" -c "import Vision" 2>/dev/null; then
                    HAS_VISION_OCR=true
                    OCR_METHOD="vision"
                    log_ok "macOS Vision OCR 可用 (pyobjc)"
                    return 0
                fi

                if ! $CHECK_ONLY; then
                    log_info "正在配置 Vision OCR 环境..."
                    # 优先用 uv，否则用 python3 -m venv
                    if cmd_exists uv; then
                        uv venv "${VENV_DIR}" --python python3 2>/dev/null || python3 -m venv "${VENV_DIR}"
                        uv pip install --python "${VENV_DIR}/bin/python3" pyobjc-framework-Vision pyobjc-framework-Quartz 2>/dev/null || \
                            "${VENV_DIR}/bin/pip3" install pyobjc-framework-Vision pyobjc-framework-Quartz
                    else
                        python3 -m venv "${VENV_DIR}"
                        "${VENV_DIR}/bin/pip3" install pyobjc-framework-Vision pyobjc-framework-Quartz
                    fi

                    if "${VENV_DIR}/bin/python3" -c "import Vision" 2>/dev/null; then
                        HAS_VISION_OCR=true
                        OCR_METHOD="vision"
                        log_ok "Vision OCR 环境配置成功"
                        return 0
                    fi
                fi
            fi
        else
            log_warn "macOS 版本 ${macos_ver} 低于 12，Vision Framework 不可用"
        fi
    fi

    # Level 2: Tesseract
    if cmd_exists tesseract; then
        HAS_TESSERACT=true
        OCR_METHOD="tesseract"
        log_ok "Tesseract OCR 可用"
        return 0
    fi

    if ! $CHECK_ONLY && $HAS_HOMEBREW; then
        log_info "正在通过 Homebrew 安装 Tesseract..."
        brew install tesseract tesseract-lang 2>/dev/null && {
            HAS_TESSERACT=true
            OCR_METHOD="tesseract"
            log_ok "Tesseract OCR 安装成功"
            return 0
        }
    fi

    # Level 3: 无 OCR 可用
    OCR_METHOD="none"
    log_warn "无 OCR 引擎可用，图片处理需手动粘贴文字"
    return 1
}

# --- 检测与安装: Whisper ---
check_whisper() {
    # Level 1: local-whisper Skill
    local LW_SCRIPT="${HOME}/.codebuddy/skills/local-whisper/scripts/local-whisper"
    if [[ -x "$LW_SCRIPT" ]] && [[ "$(wc -c < "$LW_SCRIPT" 2>/dev/null)" -gt 100 ]]; then
        HAS_WHISPER=true
        WHISPER_CMD="$LW_SCRIPT"
        log_ok "local-whisper Skill 可用"
        return 0
    fi

    # Level 1b: local-whisper 通过 venv
    local LW_VENV="${HOME}/.codebuddy/skills/local-whisper/.venv/bin/python3"
    if [[ -x "$LW_VENV" ]]; then
        HAS_WHISPER=true
        WHISPER_CMD="$LW_VENV -m whisper"
        log_ok "local-whisper venv 可用"
        return 0
    fi

    # Level 2: 独立 whisper CLI
    if cmd_exists whisper; then
        HAS_WHISPER=true
        WHISPER_CMD="whisper"
        log_ok "whisper CLI 可用"
        return 0
    fi

    # Level 2b: whisper 作为 Python 模块
    if $HAS_PYTHON3 && python3 -c "import whisper" 2>/dev/null; then
        HAS_WHISPER=true
        WHISPER_CMD="python3 -m whisper"
        log_ok "whisper Python 模块可用 (python3 -m whisper)"
        return 0
    fi

    if ! $CHECK_ONLY && $HAS_PYTHON3; then
        log_info "正在安装 openai-whisper..."
        pip3 install openai-whisper 2>/dev/null && {
            if cmd_exists whisper; then
                HAS_WHISPER=true
                WHISPER_CMD="whisper"
                log_ok "whisper 安装成功"
                return 0
            elif python3 -c "import whisper" 2>/dev/null; then
                HAS_WHISPER=true
                WHISPER_CMD="python3 -m whisper"
                log_ok "whisper 安装成功 (python3 -m whisper)"
                return 0
            fi
        }
    fi

    # Level 3: 无 whisper 可用
    log_warn "无语音转文字引擎可用，音频处理需手动粘贴转写文本"
    return 1
}

# --- 检测与安装: remindctl ---
check_remindctl() {
    if cmd_exists remindctl; then
        HAS_REMINDCTL=true
        log_ok "remindctl 已安装"
        return 0
    fi

    if ! $CHECK_ONLY && $HAS_HOMEBREW; then
        log_info "正在安装 remindctl..."
        brew install steipete/tap/remindctl 2>/dev/null && {
            HAS_REMINDCTL=true
            log_ok "remindctl 安装成功"
            return 0
        }
    fi

    log_warn "remindctl 未安装，待办将通过 osascript 降级处理"
    return 1
}

# --- 检测: osascript ---
check_osascript() {
    if cmd_exists osascript; then
        HAS_OSASCRIPT=true
        log_ok "osascript 可用 (macOS 原生)"
        return 0
    fi
    log_warn "osascript 不可用（非 macOS 系统）"
    return 1
}

# =============================================================================
# 主流程
# =============================================================================

echo "🔍 Meeting Minutes Skill — 环境检测"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 如果指定了组件，只检测该组件
if [[ -n "$TARGET_COMPONENT" ]]; then
    case "$TARGET_COMPONENT" in
        ocr)
            check_homebrew || true
            check_python3 || true
            check_ocr || true
            ;;
        whisper)
            check_homebrew || true
            check_python3 || true
            check_ffmpeg || true
            check_whisper || true
            ;;
        reminder)
            check_homebrew || true
            check_remindctl || true
            check_osascript || true
            ;;
        calendar)
            check_osascript || true
            ;;
        *)
            log_err "未知组件: $TARGET_COMPONENT (可选: ocr, whisper, reminder, calendar)"
            ;;
    esac
else
    # 全量检测，按依赖顺序
    check_homebrew || true
    check_python3 || true
    check_ffmpeg || true
    check_osascript || true
    check_ocr || true
    check_whisper || true
    check_remindctl || true
fi

# --- 输出环境摘要 ---
echo ""
echo "📊 环境能力摘要"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Homebrew:    $HAS_HOMEBREW"
echo "  Python 3:    $HAS_PYTHON3"
echo "  ffmpeg:      $HAS_FFMPEG"
echo "  osascript:   $HAS_OSASCRIPT"
echo "  OCR 方法:    $OCR_METHOD"
echo "    Vision:    $HAS_VISION_OCR"
echo "    Tesseract: $HAS_TESSERACT"
echo "  Whisper:     $HAS_WHISPER ($WHISPER_CMD)"
echo "  remindctl:   $HAS_REMINDCTL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# --- 写入环境就绪标记 ---
if ! $CHECK_ONLY; then
    cat > "$ENV_READY_FILE" <<EOF
# Meeting Minutes Skill 环境状态
# 生成时间: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
HAS_HOMEBREW=$HAS_HOMEBREW
HAS_PYTHON3=$HAS_PYTHON3
HAS_FFMPEG=$HAS_FFMPEG
HAS_OSASCRIPT=$HAS_OSASCRIPT
HAS_VISION_OCR=$HAS_VISION_OCR
HAS_TESSERACT=$HAS_TESSERACT
OCR_METHOD=$OCR_METHOD
HAS_WHISPER=$HAS_WHISPER
WHISPER_CMD=$WHISPER_CMD
HAS_REMINDCTL=$HAS_REMINDCTL
EOF
fi

# --- 计算返回值 ---
DEGRADED=false
CRITICAL=false

if [[ "$OCR_METHOD" == "none" ]]; then DEGRADED=true; fi
if [[ "$HAS_WHISPER" == "false" ]]; then DEGRADED=true; fi
if [[ "$HAS_PYTHON3" == "false" ]]; then CRITICAL=true; fi

if $CRITICAL; then
    log_err "关键依赖缺失，部分功能不可用"
    return 2 2>/dev/null || exit 2
elif $DEGRADED; then
    log_warn "部分功能已降级，核心功能可用"
    return 1 2>/dev/null || exit 1
else
    log_ok "全部环境就绪"
    return 0 2>/dev/null || exit 0
fi
