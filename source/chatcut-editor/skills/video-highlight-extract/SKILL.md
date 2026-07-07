# video-highlight-extract

从长视频中自动提取高光片段，切成短视频。

## 触发条件
用户说"找高光""切精华""提取亮点""highlight""切片"时调用。

## 输入
- `transcript_path`: 转写文件路径
- `count`: 要提取的片段数（默认 3-5）
- `max_duration`: 每个片段最大时长（默认 60s）
- `criteria`: 筛选标准（engagement / information_density / emotion）

## 执行
1. 读取 transcript
2. 用 LLM 分析哪些段落最有价值（观点密度、情感强度、信息量）
3. 输出 highlight 列表（start/end/reason/score）
4. 为每个 highlight 生成独立的 timeline patch

## 输出
- highlights: [{start, end, reason, score, text_preview}]
- 每个 highlight 的 timeline patch
- 建议的标题/封面文案

## 设计原则
ChatCut 原则 #5：复杂请求拆成多工具链。高光提取是"长视频切短视频"的核心。
