# 可读版历史修改记录

完整原始历史在 `sessions/` 下的两份 JSONL 中；这里是按工程视角整理的可读版。

## 1. 需求梳理

- 阅读用户提供的 ChatCut 研究讨论文档。
- 明确目标：复刻 ChatCut，并把左侧做成实时可操作剪辑区。
- 明确约束：暂时不做快捷键。
- 明确体验方向：界面接近完成，但用户感觉“用不明白”，所以功能和流程要更小白、更真实可操作。

## 2. OpenClacky 宿主布局调整

- 修改 OpenClacky 宿主页面布局，让 ChatCutPro 扩展占据左侧主区域。
- 保留右侧原生聊天区，使“剪辑操作 + Agent 对话”同时存在。
- 隐藏/压缩不必要的侧边干扰，让工作重心放到剪辑区。
- 加入可调整聊天区域宽度的布局能力。

相关文件：

- `host_openclacky_layout/app.js`
- `host_openclacky_layout/app.css`

## 3. ChatCutPro 扩展基础

- 建立/完善本地扩展 `chatcut-editor`。
- 配置扩展 manifest、panel、agent prompt。
- 接入 Ruby API handler 和前端 `view.js`。

相关文件：

- `source/chatcut-editor/ext.yml`
- `source/chatcut-editor/api/handler.rb`
- `source/chatcut-editor/panels/editor/view.js`
- `source/chatcut-editor/agents/chatcut-agent/system_prompt.md`

## 4. 项目与时间线系统

- 支持上传视频并创建项目目录。
- 写入并维护 `project.json`、`timeline.json`、`patches.json`、`edit_decisions.json`。
- 建立多轨时间线结构：主视频、音频、字幕、音乐、旁白、B-roll、MG 包装。

## 5. 文本剪辑

- 支持读取转写片段。
- 支持片段播放、选择、裁剪。
- 支持撤销最近一次裁剪。
- 支持口癖、停顿、精剪等 Agent 指令映射到剪辑决策。

## 6. 实时字幕编辑

- 前端增加可编辑字幕文本区域。
- 用户编辑字幕后，界面预览立即更新。
- 保存逻辑通过 `/caption/update` 写回后端。
- 后端同步更新 `CAPTIONS` track、SRT、ASS、styled ASS。
- 字幕变更会触发时间线重渲染。

## 7. 高光/场景能力

- 增加场景检测能力。
- 增加高光片段提取和 HIGH track。
- 支持“找高光”后裁掉非高光片段。
- 修复过裁剪后渲染音视频完整性问题。

## 8. 多轨渲染

- 建立从裁剪到字幕、B-roll、MG、音频混合的渲染链。
- 支持 V2 B-roll 合成。
- 支持 MG HyperFrames HTML/fallback alpha MOV 合成。
- 支持 BGM、旁白和主音频混音。

## 9. 导出与版本

- 支持 9:16、16:9 导出。
- 生成导出报告和 export bundle。
- 增加版本列表、版本 diff、rollback。
- 对 diff/rollback 做过临时项目验证。

## 10. 验证记录

曾通过的验证包括：

- `ruby -c /Users/ldtx/.clacky/ext/local/chatcut-editor/api/handler.rb`
- `node --check /Users/ldtx/.clacky/ext/local/chatcut-editor/panels/editor/view.js`
- `clacky ext verify`
- 字幕编辑 API 测试：SRT/ASS 更新、渲染有音视频。
- 版本 diff/rollback 测试。
- 高光剪辑测试。
- MG fallback MOV 合成测试。
- B-roll V2 合成测试。

## 11. 当前未完成/风险

- 左侧时间线还不是完整剪映式交互。
- 字幕是实时可编辑，但完整逐字级编辑还没有完成。
- 高光和 B-roll 还没有达到完整 ChatCut 级智能。
- 专业工程导出还没做。
- 本轻量包不包含媒体文件，不能单独重渲染当前真实视频。

