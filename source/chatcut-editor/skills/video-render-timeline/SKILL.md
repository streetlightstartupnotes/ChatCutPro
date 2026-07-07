# video-render-timeline

根据 timeline.json 渲染最终视频。timeline.json 描述了多轨时间线上的所有剪辑决策。

## 触发条件

当 timeline.json 已生成（经过各种编辑操作后），需要输出最终视频时调用。

## 输入

- `project_dir`: 项目目录路径
- `timeline_path`: timeline.json 路径（可选，默认在 project_dir 下）
- `output_format`: 输出格式（默认 "mp4"）
- `quality`: 质量预设（"draft" / "normal" / "high"）

## timeline.json 格式

```json
{
  "version": "1.0",
  "duration": 120.5,
  "resolution": {"width": 1920, "height": 1080},
  "fps": 30,
  "tracks": [
    {
      "id": "V1",
      "type": "video",
      "clips": [
        {"source": "input.mp4", "in": 0.0, "out": 5.2, "timeline_start": 0.0},
        {"source": "input.mp4", "in": 6.0, "out": 12.3, "timeline_start": 5.2}
      ]
    },
    {
      "id": "A1",
      "type": "audio",
      "clips": [...]
    },
    {
      "id": "CAPTIONS",
      "type": "subtitle",
      "source": "captions.ass"
    }
  ]
}
```

## 执行步骤

1. 解析 timeline.json

2. 对视频轨：根据 clips 列表生成 FFmpeg filter_complex：
   ```bash
   ffmpeg -i input.mp4 \
     -filter_complex "[0:v]trim=0:5.2,setpts=PTS-STARTPTS[v0]; \
                      [0:v]trim=6.0:12.3,setpts=PTS-STARTPTS[v1]; \
                      [v0][v1]concat=n=2:v=1:a=0[outv]" \
     -map "[outv]" output.mp4
   ```

3. 如果有字幕轨，叠加 ASS 字幕：
   ```bash
   -vf "ass=captions.ass"
   ```

4. 如果有音频轨独立处理，混合音频

5. 根据 quality 选择编码参数：
   - draft: `-crf 28 -preset ultrafast`
   - normal: `-crf 23 -preset medium`
   - high: `-crf 18 -preset slow`

## 依赖

- FFmpeg

## 输出

- 渲染完成的视频文件
- 报告：渲染耗时、输出文件大小
