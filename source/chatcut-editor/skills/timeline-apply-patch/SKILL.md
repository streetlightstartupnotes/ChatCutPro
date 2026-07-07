# timeline-apply-patch

将一个结构化 patch 应用到项目 timeline。所有编辑操作的最终执行层。

## 触发条件
任何需要修改 timeline 的操作最终都通过此 Skill 落地。

## 输入
- `project_id`: 项目 ID
- `patch`: 结构化 patch 对象，支持以下 op 类型：
  - `cut_segments`: 删除指定时间段
  - `add_clip`: 添加素材到轨道
  - `add_caption`: 添加字幕
  - `add_motion_graphic`: 添加动效组件
  - `modify_clip`: 修改 clip 属性
  - `reorder_clips`: 重排 clip 顺序
  - `speed_change`: 变速

## 执行
1. 验证 patch 格式
2. 应用 patch 到 timeline
3. 自动保存版本
4. 更新 edit_decisions

## 输出
- 应用结果（成功/失败）
- 新版本号
- 更新后的 timeline 概览

## 设计原则
ChatCut 原则 #6：Agent 输出 patch，不直接破坏原素材。
