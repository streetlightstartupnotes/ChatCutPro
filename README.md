# ChatCutPro — AI 视频剪辑助手

> 左侧实时剪辑区 + 右侧自然语言剪辑 Agent，复刻并超越 ChatCut 体验。

## 这是什么

ChatCutPro 是一个基于 OpenClacky 扩展的视频剪辑产品原型。它的核心思路是：

- **左侧**：可实时操作的时间线、字幕、转写、属性与导出面板
- **右侧**：自然语言 Agent，接受精剪、字幕、高光、B-roll、导出等组合指令

目标用户是短视频创作者和自媒体主理人，希望用“剪映式直接操作 + AI Agent 批量处理”的双模式完成剪辑。

## 效果图

从实际项目截图中可以看到：

- 左侧字幕/Transcript 面板支持逐句选择、跳转和编辑
- 右侧上方为播放器，下方为时间线多轨视图（MG / V1 / V2 / A1 / CAPTIONS）
- 右侧边栏显示项目状态、版本、Tokens、Cost 等元数据
- 顶部工具栏覆盖：上传视频、生成字幕、场景检测、删停顿、删口癖、自动精剪、B-roll、HyperFrames、导出视频、导出音频、导出帧

当前真实项目「6月20日」已跑通完整链路，从上传到导出报告均可操作。

## 已完成

### 产品与交互
- 左侧实时剪辑工作区 + 右侧 OpenClacky 聊天区的双栏布局
- ChatCutPro 扩展入口、项目上传、项目状态持久化
- 新手三步流程：开始 → 精剪 → 导出
- 多意图 Agent 对话：能处理精剪、字幕、停顿、口癖、高光、导出等组合指令

### 时间线引擎
- 多轨结构：`MG`、`V2`、`V1`、`A1`、`MUS`、`VO`、`CAPTIONS`
- 文本剪辑：按转写片段播放、选择、裁剪、撤销最近裁剪
- 实时字幕编辑：直接编辑字幕文本，预览立即变化，保存后重写 SRT/ASS/styled ASS 并触发重渲染
- 版本系统：版本列表、diff、rollback、补丁记录、edit decisions

### 智能能力
- 场景检测 / 片段高光抽取 / HIGH track 展示
- 智能粗剪：去停顿、去口癖、去重复、保留高光
- B-roll / V2：生成本地占位 B-roll 并纳入渲染
- MG / HyperFrames：生成可编辑 HTML 动画包装，alpha MOV fallback 合成
- 音频链：降噪 / 响度处理、生成 BGM 到 `MUS`、macOS `say` 旁白到 `VO`，并混音输出

### 导出
- 支持 9:16 / 16:9 导出
- 导出报告、导出 bundle
- 项目打包和元数据保留（排除实际媒体文件）

### 真实项目资产
- 当前项目 ID：`574b7e43d5ab18c9`
- 项目名：「6月20日」
- 保留：`project.json`、`timeline.json`、`patches.json`、`edit_decisions.json`、字幕、转写、ASS/SRT、版本记录

## 未完成

### 剪辑交互
- 左侧还未达到剪映级时间线交互：拖拽排序、trim 手柄、轨道开关、素材库、片段属性面板
- 逐字级文本编辑器：当前主要是片段级，字幕文本可编辑但不是完整 word-level editor

### 智能能力
- 语义高光：当前偏本地启发式，不是完整 LLM / 多模态评分
- 真 B-roll：当前主要是本地生成/占位，不是联网素材库或 AI 视频生成工作流
- 品牌 URL / 素材提取：ChatCut 文档中提到的 URL 到品牌素材链路尚未完整落地
- 智能改稿：自然语言“更短、更有冲突、更像口播”等改写能力还在规划

### 专业输出
- FCPXML / OTIO / XML 等专业工程交接格式尚未实现
- 长视频分段渲染、渲染队列、取消重试、增量更新仍在后续阶段

## 技术栈

- 前端：OpenClacky 宿主布局扩展 + 自定义编辑器面板
- 后端：`source/chatcut-editor/api/handler.rb` 负责项目、时间线、补丁、版本、导出管理
- Agent：`source/chatcut-editor/agents/chatcut-agent/system_prompt.md` 负责自然语言到剪辑操作的映射
- 媒体处理：ffmpeg 多轨合成、音频降噪、字幕渲染、HyperFrames 动效

## 快速验证

```bash
ruby -c /Users/ldtx/.clacky/ext/local/chatcut-editor/api/handler.rb
node --check /Users/ldtx/.clacky/ext/local/chatcut-editor/panels/editor/view.js
cd /Users/ldtx/.clacky/ext/local/chatcut-editor && clacky ext verify
```

完整链路建议创建临时项目跑一遍：上传 → 转写/模拟转写 → 改字幕 → 裁剪 → 渲染 → 导出 → 删除临时项目。

## License

MIT
