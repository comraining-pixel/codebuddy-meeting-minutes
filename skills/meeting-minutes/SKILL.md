---
name: meeting-minutes
description: "Extract structured meeting minutes from multiple input sources (text, images via OCR, audio/video via Whisper). Identifies key points, speaker attributions, decisions, deadlines, and action items. Stores results as Markdown in a digital-twin memory system (journal/experience/knowledge). Optionally inserts todos into macOS Calendar and Reminders. This skill should be used when the user provides meeting notes, email threads, chat logs, images of whiteboards, audio recordings, or video files and wants them summarized, structured, and archived."
description_zh: "多源纪要提取与结构化存储，支持日历待办集成"
description_en: "Multi-source meeting minutes extraction with smart archival"
version: 1.0.0
allowed-tools: Read,Write,Bash,Grep
---

# Meeting Minutes — 智能纪要提取与结构化存储

从会议纪要、邮件、聊天记录、图片、音频/视频等多种输入源中提取结构化纪要，自动归档到用户的数字分身记忆系统，并可选将待办事项插入 macOS 日历和提醒事项。

## 触发场景

当用户的请求符合以下任一条件时，触发本 Skill：

- 提供了会议纪要、邮件正文、聊天记录等文本内容，要求整理/提取要点
- 提供了图片文件（截图、白板照片、拍照笔记），要求识别并整理内容
- 提供了音频或视频文件（录音、会议录制），要求转写并整理
- 提到"纪要"、"会议记录"、"整理要点"、"提取重点"、"归档"等关键词
- 要求将内容存储到记忆系统（journal/experience/knowledge）

## 工作流总览

```
输入 → 环境检测 → 内容提取 → AI 纪要结构化 → 智能存储 → [可选] 待办/日历集成
```

---

## Step 1: 环境检测与依赖准备

每次处理图片或音频输入前，先运行环境检测脚本确认可用能力：

```bash
source ~/.codebuddy/skills/meeting-minutes/scripts/setup-env.sh
```

脚本会输出环境能力变量：
- `HAS_VISION_OCR` — macOS Vision Framework OCR 是否可用
- `HAS_TESSERACT` — tesseract OCR 是否可用
- `HAS_WHISPER` — local-whisper 或 whisper CLI 是否可用
- `HAS_REMINDCTL` — remindctl CLI 是否可用
- `HAS_OSASCRIPT` — osascript 是否可用（macOS 原生）

如果缺少依赖，脚本会**自动安装**（通过 Homebrew/pip），无需用户手动操作。

---

## Step 2: 输入类型识别与内容提取

根据用户提供的输入类型选择对应的提取方式：

### 2a. 纯文本 / Markdown

直接读取用户提供的文本内容。支持以下来源：
- 用户直接粘贴的会议纪要文本
- `.md` / `.txt` 文件
- 邮件正文（直接粘贴或 `.eml` 文件）
- 聊天记录（微信/企微/Slack 等导出文本）

### 2b. 图片文件（OCR 提取）

对图片文件进行 OCR 文字识别。降级策略：

**Level 1 — macOS Vision Framework（首选，中英文识别最优）：**
```bash
python3 ~/.codebuddy/skills/meeting-minutes/scripts/ocr.py <图片路径> [图片路径2 ...]
```

**Level 2 — Tesseract OCR（自动降级）：**
如果 Vision Framework 不可用（非 macOS 或 macOS < 12），`ocr.py` 脚本会自动降级到 tesseract。如果 tesseract 也未安装，`setup-env.sh` 会自动通过 `brew install tesseract tesseract-lang` 安装。

**Level 3 — 手动粘贴（兜底）：**
如果以上方案均不可用，提示用户：
> 当前环境无法自动识别图片文字。请手动将图片中的文字内容粘贴到此对话中，我将帮你整理成结构化纪要。

### 2c. 音频 / 视频文件（语音转文字）

对音频/视频文件进行语音转文字。降级策略：

**Level 1 — local-whisper Skill（首选）：**
```bash
~/.codebuddy/skills/local-whisper/scripts/local-whisper <音频文件> --model turbo --timestamps --language zh
```

对于超过 30 分钟的音频，建议使用 `turbo` 或 `large-v3` 模型以获得更好的效果。使用 `--timestamps` 参数可获取时间戳，便于对应发言人。

**Level 2 — 独立 whisper CLI（自动安装）：**
如果 local-whisper Skill 未安装，`setup-env.sh` 会自动安装 `openai-whisper`：
```bash
whisper <音频文件> --model turbo --language zh --output_format txt
```

**Level 3 — 手动粘贴（兜底）：**
如果以上方案均不可用，提示用户：
> 当前环境无法自动转写音频。请使用其他工具（如飞书转写、讯飞听见）将音频转为文字后粘贴到此对话中。

**音频预处理：** 如果输入是视频文件（.mp4/.mov/.avi/.mkv），先用 ffmpeg 提取音轨：
```bash
ffmpeg -i <视频文件> -vn -acodec pcm_s16le -ar 16000 -ac 1 /tmp/audio_extracted.wav
```
如果 ffmpeg 未安装，`setup-env.sh` 会自动安装。

---

## Step 3: AI 纪要结构化提取

将提取到的原始文本内容进行智能分析和结构化。这是本 Skill 的核心步骤，由 AI 完成。

### 提取要素清单

对原始内容进行全面分析，提取以下要素：

1. **基本信息**：时间、地点、参会人及角色、会议类型、资料来源
2. **会议摘要**：1-2 段话概括核心议题和整体结论
3. **要点与分议题**：按主题分章节，每个章节包含详细内容、数据、进展
4. **观点与发言人对应**：明确标注每个观点/建议的提出者及其角色
5. **关键决策与结论**：标注决策内容和决策人
6. **时间节点与 DDL**：提取所有提到的截止日期、里程碑节点
7. **待办事项**：提取所有待办，包含负责人和截止日期

### 提取规则

- **观点归属必须精确**：每个观点、建议、判断都要标注是谁说的（姓名+角色）
- **数据保留原貌**：原文中的数字、百分比、金额等数据保持原始精度
- **区分事实与观点**：事实性描述和主观判断/建议要区分呈现
- **DDL 必须显式**：所有提到的时间节点单独整理成表格
- **待办必须可执行**：每条待办包含具体事项、负责人、截止日期

### 输出格式

纪要必须严格遵循以下 Markdown 结构。参考完整模板见 `references/minutes-template.md`。

```markdown
---
title: "纪要标题"
category: "meeting"
tags: ["标签1", "标签2"]
date: "YYYY-MM-DD"
source: "会议纪要 | 音频转写 | 图片OCR | 聊天记录 | 邮件"
status: "active"
participants: ["姓名1(角色)", "姓名2(角色)"]
related: []
---

# 纪要标题

## 基本信息

- **会议时间**：YYYY-MM-DD HH:mm
- **会议类型**：周会 / 专题会 / 项目沟通 / 决策会 / ...
- **地点**：线上/会议室名称
- **参会人**：姓名(角色), ...
- **资料来源**：描述输入源
- **处理方式**：描述处理方式，**不保存原始文件**

## 会议摘要

一段话概括核心议题和整体结论。

## 一、章节标题

### 1. 子议题
正文内容，含数据、观点归属、发言人标注...

### 2. 子议题
...

## 二、章节标题
...

## 待办事项

- [ ] 待办描述 @负责人 截止: YYYY-MM-DD
- [ ] 待办描述 @负责人 截止: YYYY-MM-DD

## 关键判断

1. 关键判断/决策内容
2. 关键判断/决策内容
```

### 不同输入场景的适配

**邮件纪要**：将 `category` 设为 `"email"`，基本信息中增加"发件人"、"收件人"、"主题"字段。

**聊天记录**：将 `category` 设为 `"chat"`，按时间线组织对话流，提取穿插其中的决策和待办。

**单人语音备忘**：将 `category` 设为 `"memo"`，简化参会人为"记录人"，重点提取思路和待办。

---

## Step 4: 智能存储归档

### 存储根目录

存储根目录变量 `MEMORY_ROOT`，默认值为 `~/Documents/MB Air/Claw`。

**首次使用时**，确认用户的记忆系统根目录：
> 检测到默认记忆系统路径为 `~/Documents/MB Air/Claw`，请确认是否正确？如果你的记忆系统在其他位置，请提供路径。

### 存储位置决策树

根据纪要内容特征自动判断存储位置：

```
内容是否涉及方法论、通用知识、技术方案？
  → 是 → knowledge/{category}/YYYYMMDD-slug.md
  → 否 → 继续判断

内容是否涉及重大决策、资源分配、方向变更、产品方案？
  → 是 → experience/decisions/slug-YYYYMMDD.md
  → 否 → 继续判断

内容是否为正式会议纪要（有明确参会人、议题）？
  → 是 → experience/meetings/YYYYMMDD-slug.md
  → 否 → 继续判断

内容是否为日常简短沟通/碎片信息/每日汇总？
  → 是 → 追加到 journal/YYYY/MM/YYYY-MM-DD.md
  → 否 → 默认存入 experience/meetings/YYYYMMDD-slug.md
```

### 文件命名规范

- **meetings**: `YYYYMMDD-english-slug.md`（如 `20260325-wechat-pay-biweekly-meeting.md`）
- **decisions**: `slug-YYYYMMDD.md`（如 `insurance-policy-center-product-plan.md`）
- **knowledge**: `slug.md`（如 `ocr-comparison.md`）
- **journal**: 追加到已有的 `YYYY-MM-DD.md` 文件中

### 索引自动更新

纪要文件保存后，自动更新对应目录的 `_index.md` 索引文件：

**experience/meetings/_index.md 格式：**
在对应年月区块下追加新条目：
```markdown
- [纪要标题](文件名.md) - 一句话摘要
```

**experience/decisions/_index.md 格式：**
在文档列表下追加新条目：
```markdown
- [文档标题](文件名.md) - 一句话摘要
```

如果 `_index.md` 中没有对应年月区块，先创建区块再追加条目。

### 目录自动创建

如果目标目录不存在（如新的年月目录），自动创建：
```bash
mkdir -p "$MEMORY_ROOT/experience/meetings"
mkdir -p "$MEMORY_ROOT/journal/YYYY/MM"
```

### 源文件处理

**默认不保存**任何源文件（图片、音频、视频）。在纪要的"基本信息"区注明：
```
- **处理方式**：基于 [OCR提取/音频转写/文本解析] 整理，**不保存原始文件**
```

---

## Step 5: 待办与日历集成

纪要完成并存储后，如果纪要中包含待办事项或关键时间节点，**主动询问用户**：

> 📋 本次纪要包含以下待办事项和关键节点：
>
> **待办事项（{N}项）：**
> 1. [待办描述] @负责人 截止: YYYY-MM-DD
> 2. ...
>
> **关键时间节点（{M}个）：**
> 1. [事项] - YYYY-MM-DD
> 2. ...
>
> 是否需要将它们插入到系统的日历和提醒事项中？
> - 🔔 插入全部待办到 Apple 提醒事项
> - 📅 插入关键节点到 macOS 日历
> - ✅ 两者都插入
> - ⏭️ 跳过，不插入

### 5a. 插入 Apple 提醒事项

使用 `add-reminder.sh` 脚本，降级策略内置于脚本中：

```bash
~/.codebuddy/skills/meeting-minutes/scripts/add-reminder.sh \
  --title "待办描述" \
  --due "YYYY-MM-DD" \
  --list "会议待办" \
  --notes "来源: 纪要标题"
```

**降级链（脚本内部自动处理）：**
1. 首选 `remindctl add` — 最完整的功能
2. 降级到 `osascript` 操作提醒事项 App — macOS 原生
3. 兜底输出结构化纯文本，提示用户手动添加

### 5b. 插入 macOS 日历

使用 `add-calendar.sh` 脚本，降级策略内置于脚本中：

```bash
~/.codebuddy/skills/meeting-minutes/scripts/add-calendar.sh \
  --title "事件标题" \
  --start "YYYY-MM-DD HH:mm" \
  --end "YYYY-MM-DD HH:mm" \
  --notes "来源: 纪要标题" \
  --calendar "会议"
```

**降级链（脚本内部自动处理）：**
1. 首选 `osascript` AppleScript 操作日历 App（含去重检查）— macOS 原生
2. 降级生成标准 `.ics` 日历文件到当前目录，提示用户双击导入

---

## 完整工作流示例

### 示例 1: 处理会议 PPT 导出文本

```
用户: 帮我整理这个双周会的 PPT 内容 [粘贴文本]

Skill 执行:
1. 识别输入类型 → 纯文本
2. AI 提取结构化纪要 → 生成 Markdown
3. 判断存储位置 → experience/meetings/20260325-biweekly-meeting.md
4. 保存纪要，更新 _index.md
5. 询问是否插入待办到日历/提醒事项
```

### 示例 2: 处理白板照片

```
用户: 帮我整理这张白板照片的内容 [提供图片路径]

Skill 执行:
1. 运行 setup-env.sh 检测环境
2. 识别输入类型 → 图片
3. 调用 ocr.py 提取文字（Vision OCR 或 tesseract）
4. AI 提取结构化纪要 → 生成 Markdown
5. 判断存储位置 → 根据内容决定
6. 保存纪要，更新 _index.md
7. 询问是否插入待办
```

### 示例 3: 处理录音文件

```
用户: 帮我整理这段会议录音 [提供音频文件路径]

Skill 执行:
1. 运行 setup-env.sh 检测环境
2. 识别输入类型 → 音频
3. 调用 local-whisper 或 whisper 转写（带时间戳）
4. AI 提取结构化纪要 → 生成 Markdown
5. 判断存储位置 → experience/meetings/
6. 保存纪要，更新 _index.md
7. 询问是否插入待办
```

---

## 注意事项

- **UTF-8 编码**：所有文件读写确保 UTF-8 编码，特别是中文内容
- **YAML Front Matter 转义**：标题中含冒号、引号时，用双引号包裹整个值
- **源文件不保存**：图片、音频、视频等源文件默认不保存，纪要中注明处理方式
- **幂等性**：重复处理同一内容时，检查目标文件是否已存在，避免重复创建
- **_index.md 追加而非覆盖**：更新索引时追加新条目，不修改已有条目
