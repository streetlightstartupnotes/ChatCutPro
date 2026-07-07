# video-master-prompt

按固定视频结构模板（Master Prompt）自动生成 first cut。

## 触发条件
用户说"按模板剪""客户案例""产品教程""播客切片"时调用。

## 内置模板

### customer_testimonial（客户案例）
结构：intro → pain_point → solution → result → CTA

### product_demo（产品教程）
结构：hook → problem → steps → recap → CTA

### podcast_shorts（播客切片）
结构：hook → strongest_point → context → punchline

### ugc_ad（UGC 广告）
结构：pain → demo → proof → offer

### course_summary（课程精华）
结构：overview → key_points → examples → takeaway

## 执行
1. 读取 transcript
2. 用 LLM 按 template 结构分析内容
3. 找出每个结构段对应的时间范围
4. 生成 timeline patch（reorder + cut）
5. 自动加 title card 和 lower third

## 输出
- 按模板结构重组的 timeline
- 每段对应的 transcript 片段
- 建议的标题/字幕

## 设计原则
ChatCut 原则 #11：按场景封装 Master Prompt。重复视频格式产品化。
