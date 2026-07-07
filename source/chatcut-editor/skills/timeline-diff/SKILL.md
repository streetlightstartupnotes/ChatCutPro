# timeline-diff

对比两个版本的 timeline 差异。

## 触发条件
用户说"对比""diff""和上次有什么区别"时调用。

## 输入
- `project_id`: 项目 ID
- `version_a`: 版本 A（默认 current-1）
- `version_b`: 版本 B（默认 current）

## 输出
- 新增的 clips
- 删除的 segments
- 修改的属性
- 时长变化

## 设计原则
ChatCut 原则 #12：专业工作流必须支持版本对比。
