# video-caption-style

为字幕应用平台风格样式。支持 B站、小红书、TikTok、YouTube 等预设风格。

## 触发条件

用户要求"B站风格字幕""小红书字幕""加样式""style captions"时调用。

## 输入

- `caption_path`: 字幕文件路径（SRT/ASS）
- `style`: 预设风格名称
- `custom_style`: 自定义样式参数（可选）

## 预设风格

### bilibili（B站风）
- 字体：思源黑体 Bold
- 字号：52px
- 颜色：白色 + 黑色描边 3px
- 位置：底部居中，距底 80px
- 逐词高亮：当前词变黄色

### xiaohongshu（小红书风）
- 字体：站酷快乐体 / 可爱手写体
- 字号：56px
- 颜色：白色 + 粉色阴影
- 位置：居中偏上
- 背景：半透明圆角色块
- 逐词动画：弹出效果

### tiktok（TikTok / 抖音风）
- 字体：Impact / 黑体 Ultra Bold
- 字号：64px
- 颜色：白色 + 强描边 4px
- 位置：正中央
- 逐词高亮：3 词一组，当前组放大

### youtube（YouTube 风）
- 字体：Roboto / Noto Sans
- 字号：44px
- 颜色：白色 + 半透明黑底
- 位置：底部
- 标准 CC 样式

### karaoke（卡拉 OK 风）
- 逐词填充动画
- 已读词变色，未读词灰色
- 用 ASS `\kf` 标签实现

## 执行步骤

1. 读取字幕文件，解析为结构化数据

2. 根据所选 style 生成 ASS 样式定义：
   ```
   [V4+ Styles]
   Style: Default,<font>,<size>,<color>,<bold>,<border>,<shadow>,<alignment>,<margin>
   ```

3. 如果需要逐词高亮，用 `words` 时间戳生成 ASS `\k` 标签：
   ```
   {\k30}大家{\k20}好
   ```

4. 输出 `.ass` 文件

5. 可选：直接烧录到视频：
   ```bash
   ffmpeg -i "<video_path>" -vf "ass=<ass_path>" -c:v libx264 -crf 23 "<output_path>"
   ```

## 依赖

- FFmpeg + libass（烧录字幕）
- ASS 格式知识

## 输出

- 样式化的 ASS 字幕文件
- 可选：烧录字幕后的视频文件
