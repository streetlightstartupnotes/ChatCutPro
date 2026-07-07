# video-project-init

初始化视频剪辑项目。扫描输入的视频/音频/图片文件，提取元数据（时长、分辨率、帧率、编码），生成 project.json。

## 触发条件

用户提供视频文件路径或上传视频后，需要初始化项目时调用。

## 输入

- `video_path`: 视频文件的绝对路径（必填）
- `project_name`: 项目名称（可选，默认用文件名）

## 执行步骤

1. 创建项目目录 `~/.clacky/chatcut_projects/<project_id>/`
2. 用 `ffprobe` 提取视频元数据：
   ```bash
   ffprobe -v quiet -print_format json -show_format -show_streams "<video_path>"
   ```
3. 解析出 duration、width、height、fps、codec、audio_channels 等
4. 生成 `project.json`：
   ```json
   {
     "id": "<uuid>",
     "name": "<project_name>",
     "video_file": "<filename>",
     "video_path": "<absolute_path>",
     "duration": 120.5,
     "resolution": "1920x1080",
     "fps": 30,
     "codec": "h264",
     "audio_channels": 2,
     "created_at": "2026-07-06T12:00:00+08:00"
   }
   ```
5. 返回项目 ID 和基本信息

## 依赖

- FFmpeg / ffprobe（必须已安装）

## 输出

返回 project_id 和视频元数据摘要。
