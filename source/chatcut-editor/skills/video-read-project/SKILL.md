# video-read-project

读取项目当前完整状态。Agent 每次执行操作前必须先读取 ChatCutPro API，了解项目处于什么阶段。

## 触发条件
Agent loop 的 READ_PROJECT 阶段自动调用。

## 输入
- `project_id`: 项目 ID。未知时先调用 `GET http://127.0.0.1:7070/api/ext/chatcut-editor/projects`，选择 `created_at` 最新的项目。

## 输出
- 项目名称、创建时间
- 视频元数据（时长、分辨率、fps）
- 已完成的步骤列表
- 当前 timeline 概览（各轨道 clip 数量）
- 当前版本号
- 是否有 transcript
- 已生成的文件列表

## 设计原则
ChatCut 原则 #4：先读项目再动手。永远不要凭空执行操作。

## OpenClacky 运行约束
不要在当前工作目录查找 `project.json` / `timeline.json`。ChatCutPro 项目存放在扩展 API 管理的目录里，必须通过：
- `GET http://127.0.0.1:7070/api/ext/chatcut-editor/project/:id`
- `POST http://127.0.0.1:7070/api/ext/chatcut-editor/command`
