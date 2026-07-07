# video-filler-cut

删除口癖词（嗯、啊、就是、然后、um、uh 等），让表达更流畅。

## 触发条件

用户要求"删口癖""删废话""去掉嗯啊""remove fillers"时调用。

## 输入

- `video_path`: 输入视频路径
- `transcript_path`: transcript.json 路径（如果已有转写结果）
- `language`: 语言（默认 "zh"）
- `custom_fillers`: 用户自定义的口癖词列表（可选）

## 执行步骤

1. 如果没有 transcript，先调用 `video-transcribe-align` 获取逐词时间戳

2. 匹配口癖词表：
   - **中文默认词表：** 嗯、啊、呃、额、那个、就是、然后、对吧、这个、反正、所以说、怎么说呢
   - **英文默认词表：** um, uh, er, ah, like, you know, basically, actually, literally, I mean

3. 在 `transcript.words` 中标记所有匹配的口癖词及其时间范围

4. 计算需要保留的片段（去除口癖词时间段）

5. 用 FFmpeg 切割并拼接：
   ```bash
   # 对每个保留片段切割
   ffmpeg -y -i "<video_path>" -ss <start> -to <end> -c copy seg_N.mp4
   # 拼接所有保留片段
   ffmpeg -y -f concat -safe 0 -i segments.txt -c copy "<output_path>"
   ```

## 依赖

- FFmpeg
- 需要先有转写结果（依赖 `video-transcribe-align`）

## 输出

- 输出视频文件（删口癖后）
- 报告：删除了哪些口癖词、各出现几次、节省了多少秒
- 高频口癖词排行
