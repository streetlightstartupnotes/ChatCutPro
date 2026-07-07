# video-caption-generate

从转写结果生成字幕文件（SRT / VTT / ASS 格式）。

## 触发条件

用户要求"生成字幕""加字幕""export subtitles""generate captions"时调用。

## 输入

- `transcript_path`: transcript.json 路径
- `format`: 输出格式（默认 "srt"，可选 "vtt", "ass"）
- `max_chars_per_line`: 每行最大字符数（默认 20 中文 / 42 英文）
- `max_lines`: 最大行数（默认 2）

## 执行步骤

1. 读取 `transcript.json`

2. 根据逐词时间戳，按以下规则分行：
   - 单行不超过 `max_chars_per_line` 个字符
   - 如果 segment 过长，按标点符号或词间空隙切分
   - 保证每条字幕时长在 1~5 秒之间

3. 生成对应格式：

   **SRT:**
   ```
   1
   00:00:00,000 --> 00:00:03,200
   大家好，今天我们来聊一下
   ```

   **VTT:**
   ```
   WEBVTT

   00:00.000 --> 00:03.200
   大家好，今天我们来聊一下
   ```

   **ASS:**
   ```
   [Script Info]
   Title: ChatCut Captions
   ScriptType: v4.00+
   PlayResX: 1920
   PlayResY: 1080

   [V4+ Styles]
   Style: Default,思源黑体,48,&H00FFFFFF,...

   [Events]
   Dialogue: 0,0:00:00.00,0:00:03.20,Default,,0,0,0,,大家好，今天我们来聊一下
   ```

## 依赖

- 需要先有转写结果（依赖 `video-transcribe-align`）

## 输出

- 字幕文件（captions.srt / captions.vtt / captions.ass）
- 返回字幕条数
