# video-speaker-diarize

说话人分离：识别视频中"谁在什么时候说话"。

## 触发条件
用户要求"识别说话人""speaker""谁说的""播客分离"时调用。

## 输入
- `audio_path`: 音频文件路径
- `num_speakers`: 预期说话人数（可选，自动检测）

## 执行
```python
from pyannote.audio import Pipeline
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
diarization = pipeline(audio_path)
```

## 输出
- speaker_segments: [{speaker: "SPEAKER_01", start: 0.0, end: 5.2}, ...]
- 各说话人总时长占比

## 依赖
- pyannote.audio（`pip install pyannote-audio`）
- 需要 Hugging Face token

## 设计原则
访谈、播客、会议场景的基础能力。ChatCut 官方支持 speaker identification。
