# video-silence-cut

自动检测并删除视频中的停顿/静音段，压缩节奏。让口播视频更紧凑。

## 触发条件

用户要求"删停顿""删静音""压缩节奏""tighten pacing""remove silence"时调用。

## 输入

- `video_path`: 输入视频路径
- `min_silence_duration`: 最小静音时长阈值（默认 0.5 秒）
- `noise_threshold`: 噪音阈值（默认 -30dB）
- `padding`: 保留的前后缓冲（默认 0.1 秒）

## 执行步骤

### 方案 A：使用 Auto-Editor（推荐）

```bash
auto-editor "<video_path>" --no-open --margin 0.1s --output "<output_path>"
```

Auto-Editor 自动分析音频响度，删除低于阈值的片段。

### 方案 B：FFmpeg fallback

1. 检测静音段：
   ```bash
   ffmpeg -i "<video_path>" -af silencedetect=noise=<noise_threshold>:d=<min_silence_duration> -f null -
   ```

2. 解析 `silence_start` / `silence_end` 时间点

3. 计算需要保留的非静音片段

4. 逐段切割并拼接：
   ```bash
   # 切割每个保留片段
   ffmpeg -y -i "<video_path>" -ss <start> -to <end> -c copy seg_N.mp4
   # 拼接
   ffmpeg -y -f concat -safe 0 -i segments.txt -c copy "<output_path>"
   ```

## 依赖

- Auto-Editor（`pip install auto-editor`）— 推荐
- FFmpeg（fallback）

## 输出

- 输出视频文件（删停顿后）
- 报告：删除了多少处停顿，节省了多少秒
