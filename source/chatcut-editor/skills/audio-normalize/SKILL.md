# audio-normalize

音频标准化：统一音量、消除忽大忽小。

## 触发条件
用户说"统一音量""normalize""音频太小/太大"时调用。

## 输入
- `audio_path`: 音频路径
- `target_lufs`: 目标响度（默认 -16 LUFS）

## 执行
```bash
ffmpeg -i "<input>" -af loudnorm=I=<target_lufs>:TP=-1.5:LRA=11 "<output>"
```

## 输出
- 标准化后的音频文件
- timeline patch
