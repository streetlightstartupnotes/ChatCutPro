# video-read-timeline

读取当前 timeline 的完整结构。

## 触发条件
需要了解时间线当前状态时调用。

## 输入
- `project_id`: 项目 ID

## 输出
- timeline duration / effective_duration
- 各轨道列表（MG/V1/A1/MUS/VO/CAPTIONS）
- 每个轨道的 clips 及其属性
- cut_regions（已标记删除的区域）
- 当前版本号

## 设计原则
ChatCut 原则 #2：真实时间线优先。Timeline 是唯一真相源。
