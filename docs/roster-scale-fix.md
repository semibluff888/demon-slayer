# 新角色体型一致性修复

原导入器把动作图的行高当作站立身高，没有修正生成原图中的体型差异，因此蹲防、蹲攻会偏大，受投落地会偏小。

保持待机姿势和运行时绘制倍率不变，已复核两人全部 84 组、684 帧动作，按头肩、躯干和肢体比例校准。猗窝座蹲防缩小约 27%，蹲攻、空中动作、翻滚和技能分别修正；两人的受投横躺末段单独放大。祢豆子的蹲姿过渡、蹲攻、跳跃攻击、技能与落败动作也已调整。蹲低、蜷缩和腾空仍保留原有姿态。

## 校准与复现

- `output/imagegen/roster-v1/scale-calibration.json` 记录每组动作的基础比例、逐帧绘制修正和原图 SHA256。缺少校准、原图换版或帧数不符会报错，禁止再以网格高度估算身高。
- `calibration.json` 将受投原图的骨盆位置与显示偏移分开。缩放不再改变骨盆离根节点的 34 世界单位偏移；末四帧仍贴地。
- `imports/` 保存每帧有效比例、裁切、根节点和最终边界。修正在离线构建时写入图集。
- 原图、菜单立绘、伤害、判定框和战斗时序不变。

```powershell
.\.venv\Scripts\python.exe -X utf8 tools/build_roster_art.py --part animation
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
.\tests\run_tests.ps1
```

## 检查证据

[修复前后逐帧对照](../artifacts/scale-fix/index.html)覆盖全部动作，直接从实际打包图集取帧，使用同一显示倍率和锚点，并保留待机标尺。不会给每张姿势单独适配显示大小。

[引擎检查](../artifacts/scale-fix/engine/index.html)提供 252 张渲染截图和两段连续输入录像。静态检查中 P2 保持待机，P1 展示动作起始、中段和末帧。录像通过真实输入执行蹲防、移动、跳跃、翻滚、12 普通技、轻重必杀、奥义、MAX、前后受投与恢复。尺寸录像为静音、20 FPS，战斗逻辑为 60 Hz。

新增像素检查测量高风险姿态的头部、横躺体长和落地位置，并检查校准覆盖、原图哈希及骨盆偏移。在保留的旧图集上，两位角色均触发回归失败；修复图集的 7 项资产测试通过。完整现有套件通过，30／60／144 FPS 战斗状态一致。

```powershell
# 前后对照需要 artifacts/scale-fix/before/<角色ID>/ 中的旧 atlas.json 与 PNG。
.\.venv\Scripts\python.exe -X utf8 tools/review_roster_scale.py
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --script res://tools/capture_roster_scale.gd
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --script res://tools/capture_roster_scale.gd -- --video
.\.venv\Scripts\python.exe -X utf8 tools/build_scale_review.py --encode
```
