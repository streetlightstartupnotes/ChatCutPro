# web-extract-brand-assets

从品牌网站 URL 自动提取 logo、图片、品牌色、核心卖点。

## 触发条件
用户说"从网站生成""提取品牌素材""URL to promo"时调用。

## 输入
- `url`: 品牌网站 URL
- `extract`: 要提取的内容类型（logo / images / colors / copy / all）

## 执行
1. 浏览网页（使用 browser tool）
2. 提取：
   - Logo: 找 `<img>` 含 logo 关键词、favicon、og:image
   - Images: 主要产品图/hero 图
   - Colors: 提取 CSS 中的主色/辅色
   - Copy: 提取 h1/h2/hero text/产品描述
3. 下载素材到 generated/ 目录
4. 生成品牌概览 JSON

## 输出
```json
{
  "brand_name": "...",
  "logos": ["path/to/logo.png"],
  "images": ["path/to/hero.jpg"],
  "colors": {"primary": "#4a6cf7", "secondary": "#22aa44"},
  "copy": {"headline": "...", "subheadline": "...", "features": [...]}
}
```

## 设计原则
ChatCut 原则 #10：从网站理解品牌并组装 promo video。
这是 ChatCut 的差异化能力之一。
