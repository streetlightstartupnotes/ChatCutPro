# 当前功能总结

## 已具备

- 左侧实时剪辑工作区，右侧 OpenClacky 聊天区。
- ChatCutPro 扩展入口、项目上传、项目状态持久化。
- 时间线数据：`MG`、`V2`、`V1`、`A1`、`MUS`、`VO`、`CAPTIONS` 多轨结构。
- 文本剪辑：按转写片段播放、选择、裁剪、撤销最近裁剪。
- 实时字幕编辑：字幕文本可直接编辑，输入后预览立即变化，并通过 `/caption/update` 保存、重写 SRT/ASS/styled ASS、触发重渲染。
- 新手流程：开始、精剪、导出三个主步骤，降低第一次使用时的理解成本。
- 多意图 Agent：能处理精剪、字幕、停顿、口癖、导出等组合指令。
- 场景/高光：场景检测、片段高光抽取、HIGH track 展示，以及按高光裁掉非重点区域。
- B-roll/V2：支持生成本地占位 B-roll 片段，并纳入渲染。
- MG/HyperFrames：支持生成可编辑 HTML 动画包装，并有 alpha MOV fallback 参与合成。
- 音频：降噪/响度处理链、生成 BGM 到 `MUS`、macOS `say` 旁白到 `VO`，并混音输出。
- 导出：支持 9:16/16:9、导出报告、导出 bundle。
- 版本系统：版本列表、diff、rollback、补丁记录、edit decisions。

## 当前真实项目内保留的非媒体资产

- 核心状态：`project.json`、`timeline.json`、`patches.json`、`edit_decisions.json`
- 文本资产：转写、字幕、ASS/SRT、版本记录
- 导出/渲染相关记录：保留文本和 JSON 元数据，排除实际视频/音频产物

## 仍需补齐

- 真正接近剪映的左侧时间线交互：拖拽、修剪手柄、轨道开关、素材库、片段属性面板。
- 逐字级文本剪辑：当前主要是片段级，字幕文本可编辑但不是完整 word-level editor。
- 更强语义高光：当前偏本地启发式，不是完整 LLM/多模态评分。
- 真 B-roll：当前主要是本地生成/占位，不是联网素材或 AI 视频生成工作流。
- 品牌 URL/素材提取：ChatCut 文档里提到的 URL 到品牌素材链路还没有完整落地。
- 专业工程导出：FCPXML/OTIO/XML 等还没有实现。

