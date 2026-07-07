# video-scene-detect

场景切换检测：找出视频中画面发生跳变的时间点。

## 触发条件
用户要求"检测场景""scene detect""找转场"时调用。

## 输入
- `video_path`: 视频路径
- `threshold`: 灵敏度阈值（默认 0.3）

## 执行
```bash
ffmpeg -i "<video_path>" -filter:v "select='gt(scene,<threshold>)',showinfo" -f null - 2>&1
```
或使用 PySceneDetect：
```python
from scenedetect import detect, ContentDetector
scenes = detect(video_path, ContentDetector(threshold=threshold))
```

## 输出
- scenes: [{start: 0.0, end: 12.5}, {start: 12.5, end: 28.3}, ...]
- 场景数量

## 依赖
- FFmpeg 或 PySceneDetect（`pip install scenedetect[opencv]`）
