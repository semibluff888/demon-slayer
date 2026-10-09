# 普通祢豆子蹲防完整重绘

用户指出上一轮修错部位，实际问题在后侧手臂与手腕；本次替换普通形态 `guard_low` 全部六帧，重新连接靠近竹筒的后侧拳头、手腕、前臂和袖口。觉醒形态保留上一版，素材和图集清单哈希均未变化。

通过 CPA / gpt-image-2 使用已授权的普通蹲防参考图重新生成整套图片。所有帧按统一 0.5 倍率提取，不逐帧适配尺寸；保持原落脚点、帧数、fps、分段和时序。包含透明边缘的帧高度较原图约增加 0.9%–1.6%，宽度差异在约 ±1.8% 内；身体比例和头部大小经同尺度预览检查。

- 运行图集：`art/characters/nezuko/guard-low-redraw.png`。
- 离线导入：`tools/import_nezuko_guard_redraw.py`。
- 提示词、原始生成、导入坐标与预览：`output/imagegen/normal-guard-redraw-v3/`。
- 旧局部修补工具会保留已经导入的普通形态完整重绘，不会覆盖回旧拳头补丁。

按用户要求，只检查素材、尺寸、落脚点、未涉及动作与觉醒素材保持不变，并做资源导入；没有运行完整测试，游戏内效果由用户验证。此前 32 项／1760 项测试结果属于上一轮局部修补，不代表此次整套重绘的测试结果。

Color follow-up: match crouch frames 4/5 with small material-aware RGB deltas (coat, skin and orange hair tips). Alpha, frame dimensions, atlas registration and timing remain byte-exact. Baseline, palette record and comparison: `output/imagegen/guard-color-v4/`. Rebuild: `tools/match_nezuko_guard_colors.py`; the full redraw importer applies the same correction. Full tests were not run.
