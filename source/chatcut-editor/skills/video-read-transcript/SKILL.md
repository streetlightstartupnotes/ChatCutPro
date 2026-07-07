# video-read-transcript

读取当前项目的转写文本和时间戳数据。

## 触发条件
需要基于转写内容做决策时调用（如口癖检测、高光提取等）。

## 输入
- `project_id`: 项目 ID

## 输出
- 转写全文
- segments 列表（句子级别 + 时间戳）
- words 列表（词级别 + 时间戳）
- 语言
- 说话人信息（如有）

## 设计原则
ChatCut 原则 #3：Transcript 是视频的语义操作系统。
