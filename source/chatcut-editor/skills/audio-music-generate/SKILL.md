# audio-music-generate

生成背景音乐，自动 duck 到人声下面。

## 触发条件
用户说"加背景音乐""配乐""bgm""music bed"时调用。

## 输入
- `prompt`: 音乐风格描述（如"轻松的电子音乐""紧张的鼓点"）
- `duration`: 时长（默认匹配视频时长）
- `duck_to`: 需要避让的轨道（默认 "A1"，即人声）
- `duck_amount`: 避让量（默认 -12dB）

## 执行
1. 调用音乐生成 API（MusicGen / Suno / 其他）
2. 生成指定时长的音乐
3. 自动生成 ducking 参数
4. 输出 timeline patch：add_clip 到 MUS 轨

## 输出
- 生成的音乐文件
- timeline patch（add_clip to MUS track with duck properties）

## 设计原则
ChatCut 的音乐直接落到 timeline，并且自动 duck 到人声下面。
