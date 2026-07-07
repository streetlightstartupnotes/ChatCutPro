# video-batch-process

批量处理多个口播视频。对指定目录下的所有视频文件执行相同的剪辑流水线。

## 触发条件

用户要求"批量处理""处理这个文件夹里所有视频""batch process"时调用。

## 输入

- `input_dir`: 包含视频文件的目录路径
- `pipeline`: 要执行的操作列表（默认完整精剪流水线）
- `output_dir`: 输出目录（可选，默认在 input_dir 下创建 `output/`）
- `platform`: 导出平台（可选）

## 默认流水线

```yaml
pipeline:
  - video-project-init
  - video-transcribe-align
  - video-silence-cut
  - video-filler-cut
  - video-caption-generate
  - video-caption-style (style: bilibili)
  - video-platform-export (ratio: 16:9)
```

## 执行步骤

1. 扫描 input_dir，筛选视频文件（.mp4, .mov, .webm, .avi, .mkv）

2. 对每个视频文件：
   - 创建独立项目（`video-project-init`）
   - 按 pipeline 顺序执行每个 Skill
   - 记录执行结果（成功/失败/耗时）

3. 错误处理：
   - 单个文件失败不影响其他文件
   - 记录失败原因，最后汇总报告

4. 生成批量处理报告：
   ```markdown
   # 批量处理报告

   处理时间：2026-07-06 12:00 - 12:15
   总计：10 个视频

   ## 结果
   - ✅ 成功：8 个
   - ❌ 失败：2 个

   ## 明细
   | 文件 | 原始时长 | 最终时长 | 节省 | 状态 |
   |------|----------|----------|------|------|
   | video1.mp4 | 5:30 | 4:12 | 23% | ✅ |
   | video2.mp4 | 3:20 | 2:45 | 17% | ✅ |
   | video3.mp4 | - | - | - | ❌ 转写失败 |
   ```

## 依赖

- 依赖所有 pipeline 中引用的 Skill 的依赖

## 输出

- 每个视频的处理结果（输出文件在各自项目目录中）
- 批量处理汇总报告
