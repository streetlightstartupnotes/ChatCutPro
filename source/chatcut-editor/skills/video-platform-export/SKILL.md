# video-platform-export

将视频导出为不同平台所需的尺寸和格式。

## 触发条件

用户要求"导出竖版""导出横版""导出方形""export for TikTok""适配小红书"时调用。

## 输入

- `video_path`: 输入视频路径
- `ratio`: 目标比例（"16:9" / "9:16" / "1:1"）
- `platform`: 目标平台名（可选，用于自动选择 ratio + 参数）
- `burn_captions`: 是否烧录字幕（默认 true）
- `caption_path`: 字幕文件路径

## 平台预设

| 平台 | 比例 | 分辨率 | 备注 |
|------|------|--------|------|
| YouTube | 16:9 | 1920x1080 | 标准横版 |
| B站 | 16:9 | 1920x1080 | 同 YouTube |
| TikTok / 抖音 | 9:16 | 1080x1920 | 竖版全屏 |
| 小红书 | 9:16 或 3:4 | 1080x1920 / 1080x1440 | 竖版为主 |
| Instagram Reels | 9:16 | 1080x1920 | 竖版 |
| Instagram Feed | 1:1 | 1080x1080 | 方形 |
| 微信视频号 | 9:16 | 1080x1920 | 竖版 |

## 执行步骤

1. 根据 ratio 确定目标分辨率

2. 计算缩放和填充策略：
   - 横转竖：裁切左右 或 加上下黑边 + 放大主体
   - 竖转横：加左右黑边 或 背景模糊填充
   - 任意 → 方形：居中裁切 或 pad

3. FFmpeg 命令：
   ```bash
   # 缩放 + 填充
   ffmpeg -i "<input>" \
     -vf "scale=<w>:<h>:force_original_aspect_ratio=decrease,pad=<w>:<h>:(ow-iw)/2:(oh-ih)/2:black" \
     -c:v libx264 -crf 23 -c:a aac "<output>"
   ```

4. 如果 burn_captions=true 且有字幕文件：
   ```bash
   -vf "scale=...,subtitles='<caption_path>'"
   ```

5. 输出到项目目录：`export_16x9.mp4` / `export_9x16.mp4` / `export_1x1.mp4`

## 依赖

- FFmpeg

## 输出

- 导出的视频文件
- 报告：输出分辨率、文件大小
