# audio-voiceover-generate

文本转配音（TTS），生成旁白直接放到时间线。

## 触发条件
用户说"配音""voiceover""朗读""生成语音"时调用。

## 输入
- `text`: 要朗读的文本
- `voice`: 声音选择（可选）
- `language`: 语言（默认 zh）
- `timeline_start`: 在时间线上的起始位置

## 执行
1. 调用 TTS API（OpenAI TTS / Edge TTS / 其他）
2. 生成音频文件
3. 输出 timeline patch：add_clip 到 VO 轨

## 输出
- 生成的配音文件
- timeline patch

## 依赖
- edge-tts（`pip install edge-tts`）— 免费方案
- 或 OpenAI TTS API — 高质量方案
