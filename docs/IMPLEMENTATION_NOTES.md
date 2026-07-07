# 实现说明

## 后端

主要文件：

```text
source/chatcut-editor/api/handler.rb
```

职责：

- 项目创建、上传、状态读取。
- 时间线、补丁、版本、导出管理。
- 字幕更新和 SRT/ASS/styled ASS 写回。
- ffmpeg 渲染、多轨合成、音频处理。
- Agent 指令到剪辑操作的落地。

## 前端

主要文件：

```text
source/chatcut-editor/panels/editor/view.js
```

职责：

- 左侧剪辑工作区 UI。
- 项目/转写/字幕/时间线/导出状态展示。
- 字幕 textarea 实时编辑与保存。
- 调用后端 API。
- 展示版本、diff、rollback、导出等结果。

## Agent

主要文件：

```text
source/chatcut-editor/agents/chatcut-agent/system_prompt.md
```

职责：

- 将自然语言剪辑需求转成可执行操作。
- 多意图解析：精剪、字幕、停顿、口癖、高光、导出等。

## 当前测试入口

建议每次继续开发后至少跑：

```bash
ruby -c /Users/ldtx/.clacky/ext/local/chatcut-editor/api/handler.rb
node --check /Users/ldtx/.clacky/ext/local/chatcut-editor/panels/editor/view.js
cd /Users/ldtx/.clacky/ext/local/chatcut-editor && clacky ext verify
```

涉及真实渲染时，还应创建临时项目跑一条完整链路：上传、转写/模拟转写、改字幕、裁剪、渲染、导出，然后删除临时项目。

