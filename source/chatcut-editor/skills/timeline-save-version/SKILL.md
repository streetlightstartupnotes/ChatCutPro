# timeline-save-version

手动保存当前 timeline 为一个命名版本。

## 触发条件
用户说"保存版本""save"或 Agent 在关键操作后自动调用。

## 输入
- `project_id`: 项目 ID
- `label`: 版本标签（如"删停顿后"、"精剪完成"）

## 执行
1. 保存 timeline 完整 snapshot
2. 递增版本号
3. 记录 label 和时间戳

## 输出
- 新版本号
- 版本列表
