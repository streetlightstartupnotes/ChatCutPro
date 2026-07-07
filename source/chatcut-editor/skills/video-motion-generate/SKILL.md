# video-motion-generate

生成可编辑的 HyperFrames Motion Graphics 组件（lower third、title card、图表、logo 动画等）。

## 触发条件
用户说"加 lower third""标题卡""title card""加动效""图表动画"时调用。

## 输入
- `type`: 组件类型（lower_third / title_card / chart / logo_reveal / cta_overlay）
- `props`: 可编辑属性
  - text, name, title, subtitle
  - color, background, font
  - animation (slide_in / fade_in / bounce / typewriter)
  - duration
  - position
- `references`: 参考图/品牌色（可选）

## 执行
1. 根据 type 选择模板
2. 用 props 填充模板
3. 生成预览（HyperFrames HTML，环境可用时渲染 MP4）
4. 输出 timeline patch：add_motion_graphic 到 MG 轨

## 输出
- 可编辑组件定义（JSON props + HyperFrames HTML）
- 预览 HTML / 预览视频
- timeline patch

## 设计原则
ChatCut 原则 #7：生成物保留结构化参数。不输出不可改的 mp4，输出可编辑 props 的组件。
