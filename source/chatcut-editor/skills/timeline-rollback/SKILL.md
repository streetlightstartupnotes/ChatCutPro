# timeline-rollback

回滚 timeline 到指定版本。

## 触发条件
用户说"回滚""撤销""undo"时调用。

## 输入
- `project_id`: 项目 ID
- `target_version`: 目标版本号（可选，默认回滚到上一版本）

## 执行
1. 查找目标版本的 timeline snapshot
2. 恢复 timeline 状态
3. 标记后续 patches 为 reverted
4. 更新 current_version

## 输出
- 回滚结果
- 当前版本信息

## 设计原则
ChatCut 原则 #8：自动化 first cut，人做 final decision。支持回滚是让用户保持控制权的关键。
