# video-transcribe-align

视频语音转写 + 逐词时间戳对齐。这是文本剪视频的核心——有了逐词时间戳，删文字就等于删视频片段。

## 触发条件

用户要求"转写""生成字幕""生成文本""transcribe"时调用。

## 输入

- `video_path` 或 `audio_path`: 输入文件路径
- `language`: 语言代码（默认 "zh"，支持 "en", "ja" 等）
- `model_size`: 模型大小（默认 "base"，可选 "small", "medium", "large-v3"）

## 执行步骤

1. 如果输入是视频，先提取音频：
   ```bash
   ffmpeg -y -i "<video_path>" -vn -acodec pcm_s16le -ar 16000 -ac 1 audio.wav
   ```

2. 调用 faster-whisper 进行转写（优先）：
   ```python
   from faster_whisper import WhisperModel
   model = WhisperModel("<model_size>", device="cpu", compute_type="int8")
   segments, info = model.transcribe("audio.wav", word_timestamps=True, language="<language>")
   ```

3. 如果 faster-whisper 不可用，回退到 WhisperX：
   ```python
   import whisperx
   model = whisperx.load_model("<model_size>", "cpu")
   result = model.transcribe(audio, language="<language>")
   # 对齐获取逐词时间戳
   model_a, metadata = whisperx.load_align_model(language_code="<language>", device="cpu")
   aligned = whisperx.align(result["segments"], model_a, metadata, audio, "cpu")
   ```

4. 输出 `transcript.json`：
   ```json
   {
     "language": "zh",
     "duration": 120.5,
     "segments": [
       {"start": 0.0, "end": 3.2, "text": "大家好，今天我们来聊一下..."}
     ],
     "words": [
       {"start": 0.0, "end": 0.3, "word": "大家"},
       {"start": 0.3, "end": 0.5, "word": "好"}
     ]
   }
   ```

## 依赖

- FFmpeg（提取音频）
- Python 3.8+
- faster-whisper（`pip install faster-whisper`）或 WhisperX（`pip install whisperx`）

## 输出

- `transcript.json`: 完整转写结果（含逐词时间戳）
- 返回 segment 数量和总词数
