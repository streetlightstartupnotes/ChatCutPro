# ChatCut 剪辑助手 — Agent Loop 设计

## 一、架构总览

```
┌─────────── Workspace (view.js) ───────┐
│  剪辑工作台：视频播放器 + 项目状态      │
│  下方：字幕 + 音频 + 多轨时间线         │
│  对话/token/cost 使用 OpenClacky 原生区 │
└──────────────────┬────────────────────┘
                   │ fetch /api/ext/chatcut-editor/*
                   ▼
┌─────────── API Handler (handler.rb) ──┐
│  /env_check    → 环境依赖状态          │
│  /upload       → 视频上传 + 项目初始化   │
│  /command      → 转发给 Agent loop     │
│  /project/:id  → 项目状态查询          │
│  /stream/:id   → SSE 进度推送          │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌─────────── Agent (chatcut-agent) ─────┐
│  接收 NL 指令                          │
│  → 拆解为 Skill 调用序列               │
│  → 逐步执行，每步报告进度              │
│  → 错误时给出恢复建议                  │
└──────────────────┬────────────────────┘
                   │ invoke skills
                   ▼
┌─────────── Skills (10个) ─────────────┐
│  每个 Skill = 一个原子操作              │
│  通过 shell 调用 ffmpeg/python 脚本     │
│  输入输出都是文件（视频/JSON/SRT）       │
└───────────────────────────────────────┘
```

## 二、Agent Loop 状态机

```
[IDLE] ──用户发指令──→ [PLANNING]
  ↑                        │
  │                        ▼ 分解为 skill 序列
  │                  [EXECUTING]
  │                    │  ├─ skill_1 → [PROGRESS] → done
  │                    │  ├─ skill_2 → [PROGRESS] → done
  │                    │  └─ skill_N → [PROGRESS] → done
  │                        │
  │                        ▼
  └──────────────── [COMPLETE / ERROR]
```

### 状态定义

| 状态 | 含义 | Panel 展示 |
|------|------|-----------|
| IDLE | 等待输入 | 输入框可用 |
| PLANNING | Agent 分析指令，决定调用哪些 Skill | "正在分析..." |
| EXECUTING | 按序执行 Skills | 进度条 + 当前步骤 |
| PROGRESS | 单个 Skill 执行中 | "转写中 (2/5)..." |
| COMPLETE | 全部完成 | 展示结果摘要 |
| ERROR | 某步失败 | 错误信息 + 恢复建议 |

### 指令 → Skill 映射规则

Agent 根据以下规则决定调用序列：

| 用户说 | 展开为 |
|--------|--------|
| "生成字幕" | transcribe_align → caption_generate |
| "删停顿" | silence_cut |
| "删口癖" | transcribe_align(如果没有) → filler_cut |
| "一键精剪" | transcribe_align → silence_cut → filler_cut → caption_generate → caption_style |
| "导出竖版" | platform_export(9:16) |
| "导出横版" | platform_export(16:9) |
| "全流程" | 全部 10 个 skill |

### 依赖链

```
project_init ← (上传时自动完成)
transcribe_align ← (filler_cut, caption_generate 的前置)
silence_cut ← (独立，不依赖转写)
filler_cut ← transcribe_align
caption_generate ← transcribe_align
caption_style ← caption_generate
render_timeline ← (任何剪辑操作完成后)
platform_export ← (可在任何阶段执行)
edit_report ← (最后执行)
```

## 三、错误恢复策略

| 错误类型 | Agent 行为 |
|----------|-----------|
| 依赖缺失（如 ffmpeg 不存在） | 停止执行，告诉用户安装命令，标记哪些操作被阻塞 |
| ASR 失败（模型下载失败等） | 建议换小模型或检查网络 |
| 视频文件损坏 | 告知用户，不做后续操作 |
| 单步 Skill 超时 | 重试一次，仍失败则跳过并报告 |
| 磁盘空间不足 | 提前检测，警告用户 |

## 四、环境初始化流程（首次使用）

```
Panel 打开 → GET /env_check → 返回依赖状态
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              ffmpeg: ❌    python: ✅   faster-whisper: ❌
                    │                      │
                    ▼                      ▼
         展示安装引导 UI          展示 pip install 命令
         (brew/手动下载)
```

用户完成安装后点"重新检测"，通过后才解锁剪辑功能。
