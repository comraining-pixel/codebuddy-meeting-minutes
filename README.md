# 🎙️ Meeting Minutes — CodeBuddy Skill

> 智能纪要提取与结构化存储，支持多源输入与 macOS 日历/提醒事项集成

从会议纪要、邮件、聊天记录、图片、音频/视频等多种输入源中提取结构化纪要，自动归档到数字分身记忆系统，并可选将待办事项插入 macOS 日历和提醒事项。

## ✨ 功能亮点

- 📝 **多源输入** — 支持文本、Markdown、邮件、聊天记录、图片（OCR）、音频/视频（Whisper 转写）
- 🤖 **AI 结构化** — 自动提取参会人、议题、决策、时间节点、待办事项
- 🗂️ **智能归档** — 根据内容自动判断存储位置（meetings / decisions / knowledge / journal）
- 📅 **日历集成** — 可选将时间节点插入 macOS 日历
- 🔔 **提醒集成** — 可选将待办事项插入 Apple 提醒事项
- 🔄 **多级降级** — OCR：Vision Framework → Tesseract → 手动粘贴；音频：local-whisper → whisper CLI → 手动粘贴

## 📥 安装

### 方式一：CodeBuddy skill-install 自动安装（推荐）

在 CodeBuddy 中直接说：

```
从 https://github.com/yannxu/codebuddy-meeting-minutes 安装 skill
```

CodeBuddy 会自动完成发现、安全扫描和安装。

### 方式二：手动 Git Clone 安装

```bash
# 克隆仓库
git clone https://github.com/yannxu/codebuddy-meeting-minutes.git /tmp/codebuddy-meeting-minutes

# 复制 skill 到 CodeBuddy 目录
cp -r /tmp/codebuddy-meeting-minutes/skills/meeting-minutes ~/.codebuddy/skills/meeting-minutes

# 清理临时文件
rm -rf /tmp/codebuddy-meeting-minutes
```

### 方式三：一键脚本安装

```bash
curl -fsSL https://raw.githubusercontent.com/yannxu/codebuddy-meeting-minutes/main/install.sh | bash
```

## 🚀 使用方式

安装完成后，在 CodeBuddy 中使用以下方式触发 Skill：

### 文本输入
```
帮我整理这个双周会的纪要 [粘贴文本]
```

### 图片输入（OCR）
```
帮我识别这张白板照片的内容并整理成纪要 [提供图片路径]
```

### 音频/视频输入（Whisper 转写）
```
帮我整理这段会议录音 [提供音频文件路径]
```

## 📋 输出格式

生成标准化的 Markdown 纪要文件，包含：

- **YAML Front Matter** — 标题、分类、标签、日期、来源、参会人
- **基本信息** — 时间、类型、地点、参会人
- **会议摘要** — 核心议题和结论概述
- **分议题详情** — 按主题分章节，含数据、观点归属
- **待办事项** — 包含负责人和截止日期
- **关键判断** — 重大决策和结论

## 🏗️ 项目结构

```
skills/meeting-minutes/
├── SKILL.md                    # Skill 核心指令文件
├── .gitignore                  # Git 忽略配置
├── references/
│   └── minutes-template.md     # 纪要输出模板参考
└── scripts/
    ├── setup-env.sh            # 环境检测与自动安装
    ├── ocr.py                  # 图片 OCR 文字提取
    ├── add-calendar.sh         # macOS 日历事件写入
    └── add-reminder.sh         # Apple 提醒事项写入
```

## 🔧 环境要求

- **必须**：macOS（部分功能依赖 macOS 原生 API）
- **推荐**：Python 3.9+、Homebrew
- **可选**：
  - [local-whisper](https://github.com/steipete/local-whisper) Skill — 本地音频转写
  - Tesseract OCR — 备用 OCR 引擎
  - ffmpeg — 视频音轨提取

首次使用时，`setup-env.sh` 会自动检测并安装缺失的依赖。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](LICENSE)
