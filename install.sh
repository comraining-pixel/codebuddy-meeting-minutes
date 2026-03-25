#!/usr/bin/env bash
# =============================================================================
# Meeting Minutes Skill — 一键安装脚本
# =============================================================================
# 用法: curl -fsSL https://raw.githubusercontent.com/yannxu/codebuddy-meeting-minutes/main/install.sh | bash
# =============================================================================

set -euo pipefail

SKILL_NAME="meeting-minutes"
SKILL_DIR="${HOME}/.codebuddy/skills/${SKILL_NAME}"
REPO_URL="https://github.com/yannxu/codebuddy-meeting-minutes.git"
TMP_DIR=$(mktemp -d)

echo "🎙️ Meeting Minutes Skill 安装器"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查 git 是否可用
if ! command -v git &>/dev/null; then
    echo "❌ 未检测到 git，请先安装 git"
    exit 1
fi

# 检查是否已安装
if [[ -d "$SKILL_DIR" ]]; then
    echo "⚠️  检测到已有安装: $SKILL_DIR"
    echo "   将进行覆盖更新..."
fi

# 克隆仓库
echo "📥 正在下载..."
git clone --depth 1 "$REPO_URL" "$TMP_DIR" 2>/dev/null

# 复制 skill 文件
echo "📦 正在安装..."
mkdir -p "$SKILL_DIR"
cp -r "$TMP_DIR/skills/$SKILL_NAME/"* "$SKILL_DIR/"
cp "$TMP_DIR/skills/$SKILL_NAME/.gitignore" "$SKILL_DIR/" 2>/dev/null || true

# 清理
rm -rf "$TMP_DIR"

echo ""
echo "✅ Meeting Minutes Skill 安装成功！"
echo "   安装路径: $SKILL_DIR"
echo ""
echo "📖 使用方式: 在 CodeBuddy 中说「帮我整理这个会议纪要」即可触发"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
