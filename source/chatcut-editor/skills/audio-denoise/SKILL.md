# audio-denoise

音频降噪：去除背景噪音、电流声、嘶嘶声。

## 触发条件
用户说"降噪""去噪音""clean audio""denoise"时调用。

## 输入
- `audio_path`: 音频/视频路径
- `level`: 降噪强度（light/medium/aggressive，默认 medium）

## 执行
方案 A：noisereduce（轻量）
```python
import noisereduce as nr
import soundfile as sf
data, rate = sf.read(audio_path)
reduced = nr.reduce_noise(y=data, sr=rate)
sf.write(output_path, reduced, rate)
```

方案 B：demucs（重量级，分离人声）
```bash
python -m demucs --two-stems=vocals "<audio_path>"
```

## 输出
- 降噪后的音频文件
- timeline patch（替换 A1 轨的音频源）

## 依赖
- noisereduce（`pip install noisereduce`）或 demucs（`pip install demucs`）

## 设计原则
ChatCut 原则 #9：降噪应在转写之前执行，因为字幕依赖清晰音频。
