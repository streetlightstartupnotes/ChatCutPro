# ChatCutPro — 开发交接文档

> 最后更新: 2026-07-07  
> 版本: 0.2.0  
> 状态: 核心管线已跑通，可日常使用

---

## 一、项目概述

ChatCutPro 是一个 OpenClacky 扩展，实现**自然语言驱动的视频剪辑**。用户在 WebUI 中上传口播视频，通过对话指令（如"删停顿""加字幕""加 HyperFrames 动效""导出竖版"）完成全流程自动粗剪。

**核心理念**: Transcript 是视频的语义操作系统。所有剪辑操作转化为 Timeline Patch，可撤销、可回滚、可追溯。

---

## 二、文件结构

```
~/.clacky/ext/local/chatcut-editor/
├── ext.yml                          # 扩展清单（contributes 声明）
├── api/handler.rb                   # 后端 API（962 行，核心逻辑全在这里）
├── panels/editor/view.js            # 主工作区剪辑台（纯 DOM，挂 main.workspace）
├── agents/chatcut-agent/
│   └── system_prompt.md             # Agent system prompt（226 行）
├── skills/                          # 28 个 Skill SKILL.md（目前只有声明，未实际调用）
│   ├── video-silence-cut/
│   ├── video-filler-cut/
│   ├── video-caption-generate/
│   ├── video-transcribe-align/
│   ├── video-platform-export/
│   ├── ... (见 ext.yml 完整列表)
│   └── web-extract-brand-assets/
└── docs/
    ├── AGENT_LOOP_DESIGN.md         # Agent Loop 架构设计
    ├── TIMELINE_PATCH_PROTOCOL.md   # Patch 协议定义
    ├── PROJECT_STATE_SCHEMA.json    # project.json 结构参考
    └── HANDOFF.md                   # 本文档
```

**数据目录** (运行时产生):
```
~/.clacky/chatcut_projects/<project_id>/
├── project.json         # 项目状态 (timeline, patches, versions, media_index)
├── <原始视频>.mp4
├── audio.wav            # 提取的 16kHz mono 音频
├── transcript.json      # 转写结果 (segments + words + timestamps)
├── silence_cut.mp4      # 删停顿后的视频
├── filler_cut.mp4       # 删口癖后的视频
├── captions.srt
├── captions.ass
├── captions_styled.ass
├── versions/            # 版本快照 (暂未物化)
├── generated/           # AI 生成的素材
└── exports/
    ├── export_9x16.mp4  # 竖版导出
    └── export_16x9.mp4  # 横版导出
```

---

## 三、技术栈 & 系统依赖

| 组件 | 版本/说明 | 安装位置 |
|------|----------|---------|
| Ruby | 2.6 (macOS 系统自带) | 必须兼容，不能用 2.7+ 专有方法 |
| FFmpeg | 7.0 ARM64 | `~/bin/ffmpeg` |
| ffprobe | Python wrapper 脚本 | `~/bin/ffprobe`（用 ffmpeg -i 模拟） |
| Python | 3.9.6 | 系统自带 |
| faster-whisper | 1.2.1 | `pip3 install faster-whisper` |
| auto-editor | 29.3.1 | `~/Library/Python/3.9/bin/auto-editor` |

### ⚠️ 关键注意事项

1. **PATH 问题**: Clacky 服务进程的 PATH 不包含 `~/bin` 和 `~/Library/Python/3.9/bin`。所有外部命令调用必须通过 `resolve_cmd(name)` 或 `ffmpeg_bin` / `ffprobe_bin` helper 获取完整路径。
2. **Ruby 2.6 兼容性**: 禁止使用 `Array#tally` (2.7+)、`Enumerable#filter_map` (2.7+)、`Hash#except` (3.0+) 等新版方法。
3. **ffprobe 是 wrapper**: `~/bin/ffprobe` 不是真正的 ffprobe 二进制，而是一个 Python 脚本，用 `ffmpeg -i` 解析输出并模拟 `-print_format json` 输出。分辨率匹配正则为 `,\s+(\d{2,5})x(\d{2,5})[\s,\[]` 避免匹配 hex codec tag。

---

## 四、架构设计

### 4.1 整体分层

```
┌──────── Workspace (view.js) ─────────┐
│ 工作台: 预览/项目状态 → 字幕/音频/时间线 │
│ 原生对话区负责聊天、token、cost 和执行日志 │
│ 纯 DOM，无框架，无 iframe              │
└──────────────┬────────────────────────┘
               │ fetch /api/ext/chatcut-editor/*
               ▼
┌──────── API Handler (handler.rb) ─────┐
│ Sinatra-style routes, 继承 ApiExtension│
│ /env_check, /upload, /command, /patch  │
│ 内嵌 Agent Loop 逻辑                   │
└──────────────┬────────────────────────┘
               │ Shell (Open3.capture3)
               ▼
┌──────── 外部工具 ─────────────────────┐
│ ffmpeg / python3 / auto-editor        │
└───────────────────────────────────────┘
```

### 4.2 API 路由表

| Method | Path | 功能 |
|--------|------|------|
| GET | `/env_check` | 检测 ffmpeg/python/whisper/auto-editor |
| POST | `/auto_install` | 尝试 pip install 缺失依赖 |
| POST | `/upload` | 接收视频文件，创建项目，返回 project_id |
| GET | `/projects` | 列出所有项目 |
| GET | `/project/:id` | 获取项目完整状态 |
| **POST** | **`/command`** | **核心入口：接收自然语言指令，执行 Agent Loop** |
| POST | `/patch` | 直接应用一个 Timeline Patch |
| POST | `/version/save` | 手动保存版本 |
| POST | `/version/rollback` | 回滚到指定版本 |
| GET | `/versions/:project_id` | 获取版本列表 |

### 4.3 Agent Loop (handler.rb 内嵌)

```
POST /command {project_id, command}
    ↓
plan_execution(command, project)   # 自然语言 → step 序列
    ↓
execute_plan(plan, ...)            # 逐步执行
    ↓  每步调用 execute_step(step, ...)
    ↓  步骤: transcribe_align / silence_detect / apply_silence_cut /
    ↓         filler_detect / apply_filler_cut / caption_generate /
    ↓         caption_style / export_portrait / export_landscape /
    ↓         edit_report / rollback / version_info
    ↓
assemble_response(plan, execution, project)  # 组装前端响应
```

**指令映射** (plan_execution 中的正则):

| 用户指令 | 步骤序列 |
|---------|---------|
| 一键精剪 | transcribe → silence → filler → caption → style → save → report |
| 生成字幕 | transcribe* → caption_generate → caption_style |
| 删停顿 | silence_detect → apply_silence_cut |
| 删口癖 | transcribe* → filler_detect → apply_filler_cut |
| 导出竖版 | export_portrait |
| 导出横版 | export_landscape |
| 报告 | edit_report |

*号 = 已完成则跳过

### 4.4 Timeline Patch 协议

所有编辑操作生成结构化 Patch，写入 `project.json["patches"]`。支持的 op:

- `cut_segments` — 删除时间段（静音/口癖）
- `add_clip` — 添加素材到轨道
- `add_caption` — 添加字幕
- `add_motion_graphic` — 添加动效
- `modify_clip` — 修改 clip 属性

每次 patch 自动 version++。详见 `docs/TIMELINE_PATCH_PROTOCOL.md`。

### 4.5 Workspace UI (view.js)

**挂载位置**: 优先 `main.workspace`，`session.banner` 兜底，仅在 `chatcut-agent` 会话中显示。ChatCutPro 只提供剪辑工作台：视频预览、操作台、项目状态、字幕、音频和时间线。聊天、token、cost、执行日志全部使用 OpenClacky 原生对话区，不再自建第二个聊天框。

**视图状态机**:
```
loading → env_setup → upload → editor
                ↑ (安装失败回退)
```

**mount API 调用方式**:
```javascript
Clacky.ext.ui.mount("main.workspace", (ctx) => {
  const root = document.createElement("div");
  renderWorkspace(root);
  return root;
}, { order: 20 });
```

---

## 五、已实现功能 (✅ 已测试通过)

| 功能 | 实现方式 | 测试结果 |
|------|---------|---------|
| 环境检测 | ffmpeg/python/whisper/auto-editor 逐个检查 | ✅ |
| 视频上传 | multipart form 或 file_path JSON | ✅ |
| 转写 (ASR) | faster-whisper base 模型，16kHz wav | ✅ 72段 594词 |
| 删停顿 | ffmpeg silencedetect + auto-editor | ✅ 33处 25.5s |
| 删口癖 | transcript词级匹配 + ffmpeg concat cut | ✅ 3处 1.0s |
| 字幕生成 | transcript → SRT + ASS | ✅ 72条 |
| 字幕样式 | ASS 白字黑描边（Noto Sans SC Bold 52px） | ✅ |
| 竖版导出 | 1080x1920 libx264 + ASS burn-in | ✅ 14MB |
| 横版导出 | 1920x1080 同上 | ✅ |
| 剪辑报告 | 统计时间节省比例 | ✅ 26.5s 19.4% |
| 版本管理 | patch 追加 + version++ | ✅ |
| Panel UI | 环境检测 → 上传 → 工作台 | ✅ 代码结构正确 |

**测试视频**: `~/Movies/6月20日.mp4` (4K 3840×2160, h264, 2:16.84, 411MB)

---

## 六、待开发功能 (TODO)

### 优先级 P0 (核心体验)

| 功能 | 说明 | 工作量估计 |
|------|------|-----------|
| **SSE 进度推送** | 当前 /command 是同步阻塞的，长操作无进度反馈 | 中 |
| **视频预览** | Panel 中嵌入 `<video>` 播放器，支持预览导出结果 | 小 |
| **版本回滚真正物化** | 当前 rollback 只改 current_version 数字，不还原文件 | 中 |
| **错误恢复** | 单步失败后支持"修复后重试"，不需要从头来 | 小 |

### 优先级 P1 (功能扩展)

| 功能 | 说明 |
|------|------|
| 降噪 | 接入 demucs 或 noisereduce，在转写前执行 |
| 说话人分离 | pyannote.audio，支持多人口播区分 |
| 场景检测 | ffmpeg scene filter 或 PySceneDetect |
| 背景音乐生成 | 接入 MusicGen / Stable Audio |
| B-Roll 插入 | AI 生成或从素材库匹配 |
| 批量处理 | 多个视频自动走同一流水线 |
| 一键精剪模板 | 用户保存常用流水线，一键复用 |

### 优先级 P2 (体验优化)

| 功能 | 说明 |
|------|------|
| transcript 交互编辑 | Panel 中直接选中文字删除/修改 |
| 时间线可视化交互 | 拖拽调整 clip 位置 |
| 字幕样式模板 | 预设多种风格（B站/抖音/YouTube） |
| 导出预设管理 | 常用平台参数一键选择 |
| 项目列表管理 | Panel 中查看历史项目 |

---

## 七、Skills 说明

`ext.yml` 中声明了 28 个 skills，但**当前实际剪辑逻辑全部内嵌在 `handler.rb` 中**，skills 目录下的 `SKILL.md` 文件只是设计文档/占位符。

这是一个设计决策：最初规划让 Agent 通过 skill 调用链完成编辑，但由于性能和可靠性考虑，改为 handler.rb 内嵌的同步 Agent Loop。

**未来重构方向**: 将 handler.rb 中的 `do_*` 方法抽离为独立的 Ruby 模块或 Python 脚本，让 skills 真正可被 Agent 调用，实现更灵活的组合。

---

## 八、已知问题 & 坑

### 8.1 技术债

1. **handler.rb 过大** (962 行): 转写、剪辑、导出、报告全在一个文件。建议拆分为 `lib/transcriber.rb`、`lib/cutter.rb`、`lib/exporter.rb` 等模块。

2. **回滚不完整**: `rollback_to_version` 只修改 `current_version` 数字和 `timeline_snapshot`（如果有）。没有物化回滚视频文件。需要增加"从 patch 重新计算 timeline"或"保存每个版本的 timeline 快照"。

3. **转写脚本内联**: `build_transcribe_script` 生成 Python 代码写入临时文件再执行。如果 faster-whisper 模型未下载，首次会阻塞很久（下载 ~150MB base 模型），无进度提示。

4. **cut_with_ffmpeg 的精度**: 使用 `-c copy` 分段+concat，在关键帧边界可能有几帧误差。对口癖这种短片段（0.2~0.5s）可能有影响。改善方案：使用 `-c:v libx264` 重新编码。

5. **Panel 无法浏览器实测**: 当前开发机未配置 Chrome remote debugging，Panel 代码只做了代码走查验证。

### 8.2 兼容性

- macOS only（~/bin 路径、Python 3.9、ARM64 ffmpeg）
- Linux 部署需要调整 `resolve_cmd` 逻辑
- Windows 不支持

### 8.3 ffprobe wrapper 限制

`~/bin/ffprobe` 是用 Python 解析 `ffmpeg -i` stderr 的模拟脚本。已知限制：
- 只解析第一个 video stream 和第一个 audio stream
- 不支持 `-select_streams`、`-show_packets` 等高级参数
- 如果安装了真正的 ffprobe 二进制，可直接替换

---

## 九、开发工作流

### 修改后端 (handler.rb)

```bash
# 编辑文件
vim ~/.clacky/ext/local/chatcut-editor/api/handler.rb

# 验证清单
clacky ext verify

# 测试 (不需要重启服务，hot reload)
curl http://127.0.0.1:7070/api/ext/chatcut-editor/env_check
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/command \
  -H "Content-Type: application/json" \
  -d '{"project_id":"<id>","command":"删停顿"}'
```

### 修改前端 (view.js)

```bash
vim ~/.clacky/ext/local/chatcut-editor/panels/editor/view.js
# 浏览器刷新 WebUI 即可看到变化
```

### 修改 Agent Prompt

```bash
vim ~/.clacky/ext/local/chatcut-editor/agents/chatcut-agent/system_prompt.md
# 新对话立即生效
```

### ext verify 确保无错误

```bash
clacky ext verify
# 49 项全 [OK] 无 [ERR]/[WARN] 才算通过
```

---

## 十、API 调用示例

### 创建项目
```bash
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/upload \
  -H "Content-Type: application/json" \
  -d '{"file_path":"/path/to/video.mp4"}'
# → {"project_id":"574b7e43d5ab18c9","duration":136.84,...}
```

### 执行指令
```bash
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/command \
  -H "Content-Type: application/json" \
  -d '{"project_id":"574b7e43d5ab18c9","command":"一键精剪"}'
# → {"state":"done","message":"...","version":5,...}
```

### 应用 Patch
```bash
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/patch \
  -H "Content-Type: application/json" \
  -d '{
    "project_id":"574b7e43d5ab18c9",
    "patch":{
      "op":"cut_segments",
      "track":"V1",
      "segments":[{"start":5.0,"end":7.5,"reason":"手动删除"}]
    }
  }'
```

---

## 十一、扩展开发约束 (OpenClacky 规范)

1. **ext.yml** 是唯一入口，声明所有 contributes
2. **Panel view.js** 使用 `Clacky.ext.ui.mount(slot, spec, opts)` 挂载
3. **API handler.rb** 继承 `Clacky::ApiExtension`，路由前缀自动为 `/api/ext/<id>/`
4. **热加载**: 修改文件后无需重启服务，下次请求/页面刷新自动生效
5. **Panel 样式**: 使用宿主 CSS 变量 (`--color-text-primary`, `--color-bg-secondary`, `--color-accent-primary` 等) 保持主题一致性
6. **timeout**: handler.rb 中 `timeout 120` 设置请求超时为 120 秒（转写/导出需要较长时间）

---

## 十二、关键代码位置速查

| 功能 | 文件 | 行号(大约) |
|------|------|-----------|
| 路由声明 | handler.rb | 18-215 |
| 环境检测 | handler.rb | 260-310 |
| 项目初始化 | handler.rb | 53-120 |
| Agent Loop (plan) | handler.rb | 495-545 |
| Agent Loop (execute) | handler.rb | 548-600 |
| 转写逻辑 | handler.rb | 575-605 |
| 静音检测 | handler.rb | 610-625 |
| 口癖检测 | handler.rb | 650-680 |
| 字幕生成 | handler.rb | 695-720 |
| 导出 | handler.rb | 735-775 |
| Timeline Patch Engine | handler.rb | 375-475 |
| ffmpeg 切割 | handler.rb | 860-890 |
| Panel 挂载 | view.js | 86-110 |
| 上传逻辑 | view.js | 270-310 |
| 编辑器视图 | view.js | 315-435 |
| 发送指令 | view.js | 440-475 |

---

## 十三、快速启动指南 (给接手的 Agent)

```bash
# 1. 验证扩展状态
clacky ext verify

# 2. 确认环境
curl -s http://127.0.0.1:7070/api/ext/chatcut-editor/env_check | python3 -m json.tool

# 3. 用已有项目测试
curl -s http://127.0.0.1:7070/api/ext/chatcut-editor/projects | python3 -m json.tool

# 4. 创建新项目测试
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/upload \
  -H "Content-Type: application/json" \
  -d '{"file_path":"/Users/ldtx/Movies/6月20日.mp4"}'

# 5. 执行核心指令
curl -X POST http://127.0.0.1:7070/api/ext/chatcut-editor/command \
  -H "Content-Type: application/json" \
  -d '{"project_id":"<上一步返回的id>","command":"删停顿"}'
```

---

## 十四、术语表

| 术语 | 含义 |
|------|------|
| Patch | 结构化的 timeline 修改指令 (JSON) |
| Timeline | 多轨时间线状态 (V1/A1/MG/MUS/CAPTIONS) |
| Transcript | faster-whisper ASR 结果，含逐词时间戳 |
| Segment | 转写中的一句话 (start/end/text) |
| Word | 转写中的一个词 (start/end/word) |
| Filler | 口癖词（嗯/啊/那个/然后/这个等） |
| Silence | 静音段 (>0.5s, <-30dB) |
| Version | timeline 的版本快照，每次 patch 自动 +1 |
| Contribute | OpenClacky 扩展的功能单元类型 (api/panels/skills/agents) |
| Slot | Panel 挂载位置（ChatCutPro 使用 main.workspace；不要再用 session.aside / session.composer 承载剪辑操作） |
