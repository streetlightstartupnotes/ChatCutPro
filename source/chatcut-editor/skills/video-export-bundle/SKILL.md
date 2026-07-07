# video-export-bundle

导出完整项目包：视频 + 字幕 + transcript + timeline + 剪辑报告。

## 触发条件
用户说"导出全部""打包""export all""交付"时调用。

## 输入
- `project_id`: 项目 ID
- `platforms`: 目标平台列表（可选，默认所有已导出格式）

## 输出文件
```
export_bundle/
├── final_16x9.mp4          # 横版视频
├── final_9x16.mp4          # 竖版视频
├── captions.srt            # SRT 字幕
├── captions.ass            # ASS 字幕（含样式）
├── transcript.json         # 转写数据
├── transcript.txt          # 纯文本转写
├── timeline.json           # 时间线数据
├── edit_decisions.json     # 编辑决策记录
├── cut_report.md           # 剪辑报告
└── project_meta.json       # 项目元数据
```

## 设计原则
ChatCut 原则 #12：专业工作流必须能导出多种格式。
