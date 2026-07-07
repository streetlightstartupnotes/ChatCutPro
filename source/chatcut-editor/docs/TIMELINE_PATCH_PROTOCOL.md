# Timeline Patch 协议

## 概述

ChatCut 的核心设计：Agent 输出 patch，不直接破坏原素材。
每个编辑操作都是一个结构化 patch，可撤销、可复审、可回滚。

## Patch 类型

### 1. cut_segments — 切割/删除片段
```json
{
  "op": "cut_segments",
  "track": "V1",
  "segments": [
    {"start": 0.0, "end": 0.8, "reason": "leading dead air"},
    {"start": 12.9, "end": 14.7, "reason": "filler word: 嗯"}
  ],
  "created_by": "video-silence-cut",
  "timestamp": "2026-07-06T12:00:00Z"
}
```

### 2. add_clip — 添加素材到轨道
```json
{
  "op": "add_clip",
  "track": "MUS",
  "clip": {
    "source": "generated/music_bed_001.mp3",
    "in": 0.0,
    "out": 30.0,
    "timeline_start": 0.0,
    "properties": {
      "volume": -6,
      "duck_to": "A1",
      "duck_amount": -12
    }
  },
  "created_by": "audio-music-generate",
  "timestamp": "2026-07-06T12:01:00Z"
}
```

### 3. add_caption — 添加字幕
```json
{
  "op": "add_caption",
  "track": "CAPTIONS",
  "captions": [
    {"start": 0.0, "end": 3.2, "text": "大家好", "style": "bilibili"}
  ],
  "style_config": {
    "font": "思源黑体 Bold",
    "size": 52,
    "color": "#FFFFFF",
    "outline": 3,
    "position": "bottom_center"
  },
  "created_by": "video-caption-generate",
  "timestamp": "2026-07-06T12:02:00Z"
}
```

### 4. add_motion_graphic — 添加动效组件
```json
{
  "op": "add_motion_graphic",
  "track": "MG",
  "component": {
    "template": "lower_third",
    "start": 1.2,
    "duration": 4.5,
    "props": {
      "name": "杨一帆",
      "title": "ClackyAI 市场负责人",
      "style": "blue_gradient",
      "animation": "slide_in_left"
    },
    "editable": true
  },
  "created_by": "video-motion-generate",
  "timestamp": "2026-07-06T12:03:00Z"
}
```

### 5. modify_clip — 修改已有 clip 属性
```json
{
  "op": "modify_clip",
  "track": "A1",
  "clip_id": "clip_001",
  "changes": {
    "volume": -3,
    "fade_in": 0.5,
    "fade_out": 0.5
  },
  "created_by": "audio-denoise",
  "timestamp": "2026-07-06T12:04:00Z"
}
```

### 6. reorder_clips — 重新排列 clip
```json
{
  "op": "reorder_clips",
  "track": "V1",
  "new_order": ["clip_003", "clip_001", "clip_005", "clip_002"],
  "created_by": "video-highlight-extract",
  "timestamp": "2026-07-06T12:05:00Z"
}
```

### 7. speed_change — 变速
```json
{
  "op": "speed_change",
  "track": "V1",
  "clip_id": "clip_002",
  "speed": 1.5,
  "maintain_pitch": true,
  "created_by": "video-silence-cut",
  "timestamp": "2026-07-06T12:06:00Z"
}
```

## Version 管理

每次 apply_patch 都自动创建 version snapshot：

```json
{
  "version_id": 3,
  "label": "删停顿 + 删口癖",
  "patches_applied": ["patch_001", "patch_002", "patch_003"],
  "created_at": "2026-07-06T12:06:00Z",
  "timeline_snapshot_path": "versions/v3_timeline.json"
}
```

支持：
- `save_version(label)` — 手动保存
- `rollback(version_id)` — 回滚到任意版本
- `diff_versions(v1, v2)` — 对比两个版本的差异

## 执行原则

1. **所有编辑操作必须生成 patch**，不允许直接修改文件
2. **patch 是追加式的**，timeline 由初始状态 + 所有 patch 计算得出
3. **每个 patch 记录 created_by**，可追溯哪个 Skill 产生
4. **rollback 不删除 patch**，而是标记 reverted
5. **render 时才物化**，编辑阶段只操作 patch 和 timeline.json
