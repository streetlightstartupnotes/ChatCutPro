# video-broll-generate

生成或搜索 B-roll 素材并插入时间线。

## 触发条件
用户说"加 B-roll""插入画面""补镜头""illustrate"时调用。

## 输入
- `prompt`: B-roll 描述
- `timeline_start`: 插入位置
- `duration`: 持续时间
- `source`: 生成方式（ai_generate / stock_search / screenshot）

## 执行
1. 根据 source 获取素材：
   - ai_generate: 调用图像/视频生成 API
   - stock_search: 搜索免费素材库（Pexels/Pixabay）
   - screenshot: 截取屏幕/网页
2. 下载/生成素材到 generated/ 目录
3. 输出 timeline patch：add_clip 到 V2 轨

## 输出
- B-roll 文件
- timeline patch
