# 人物尺寸一致性修正

2026-09-21。检查两名角色的全部 78 组动作，按待机第 0 帧的头部、躯干和四肢比例核对起手、有效段与收招；修正 17 组动作、155 张画帧。

这些异常来自原始动作图的解剖比例标定。蹲姿、屈膝、翻转、衣摆和刀剑的伸展都会改变外接框，外接框高度不能直接代表人物尺寸。每组动作使用一个固定缩放值；地面姿态沿用脚底接触点，腾空姿态沿用骨盆定位，MAX 的起跳／落地继续使用原有混合锚点。

## 调整范围

下表百分比相对于修正前的**人物素材比例**；100% 表示保持原尺寸。缩放在离线导入阶段完成，已写入标定和运行图集。

| 角色 | 动作 | 动画 | 修正后比例 |
| --- | --- | --- | ---: |
| 炭治郎 | 下段轻斩 2A | crouch_light | 90% |
| 炭治郎 | 下段重体术 2D | body_crouch_heavy | 85% |
| 炭治郎 | 空中重体术 j.D | body_air_heavy | 110% |
| 炭治郎 | MAX·碧罗之天 | sun_arc | 86% |
| 炭治郎 | 前滚 | roll_forward | 94% |
| 炭治郎 | 倒地 | knockdown | 94% |
| 炭治郎 | 普通受击（轻／重攻击共用） | hit | 93% |
| 善逸 | 重体术 5D | body_stand_heavy | 86% |
| 善逸 | 下段重体术 2D | body_crouch_heavy | 92% |
| 善逸 | 空中重斩 j.C | air_heavy | 90% |
| 善逸 | 回身斩（轻／重版共用） | iai_return | 93% |
| 善逸 | 霹雳一闪（轻／重版共用） | thunder | 94% |
| 善逸 | 抓取准备 | throw | 90% |
| 善逸 | 前滚 | roll_forward | 90% |
| 善逸 | 后滚 | roll_back | 94% |
| 善逸 | 前投 | throw_forward | 90% |
| 善逸 | 前投受方 | thrown_forward | 92% |

火弧、水流、雷光由独立特效层绘制，保留技能的视觉范围。残影直接使用修正后的同一套人物画帧。招式时序、伤害、攻击／受击判定、位移、镜头倍率和气量规则保持原样。

源文件是 `output/imagegen/anime-v2/calibration.json`。每项 `scale_review` 记录待机参照、原标定值、修正倍率及原因；`standing_height` 是实际导入参数，数值增大意味着缩小素材。同步重建两人的图集、17 份导入记录及资源清单摘要。

## 验证与对照

- 首轮 `tests/run_tests.ps1` 全部通过：编译／场景加载及 12,066 项 Godot 检查。30／60／144 FPS 各推进 1,800 个逻辑帧，状态摘要一致。
- `tests/art_pipeline_tests.py --with-previews`：3 项检查通过，覆盖画帧独立性、图集范围、透明底、来源及动画预览。
- 从原始素材重新导入修正的 155 张画帧，与运行图集逐像素一致。其余 462 张画帧与修正前逐像素一致；动画阶段、帧序及公共画布参数一致，重复运行默认标定不会覆盖本轮修正。
- `tools/capture_character_scale.gd` 使用实际方向／攻击输入，覆盖 1280×720、1920×1080、左右朝向、同角色对照，以及起手、有效段、收招、恢复待机。首轮共 304 张实际 OpenGL 截图，0 项捕获检查失败。受击补充检查另有 40 张截图，覆盖轻／重攻击、两个分辨率及左右朝向，0 项捕获检查失败。
- 受击补充修正：炭治郎普通受击的 4 帧统一缩小 7%，保留原脚底落点和后仰姿势；相对补充修正前，其余 613 张画帧保持逐像素一致。补充运行的表现检查 2,234 项、美术检查 3 项均通过。
- [受击修正前后对照](../artifacts/character-scale/review/tanjiro-hit-compare.jpg)；[受击引擎截图索引](../artifacts/character-scale/engine/captures-hit.json)；[受击素材检查记录](../artifacts/character-scale/hit-validation.json)。
- [动作逐帧与修正前后对照](../artifacts/character-scale/review/index.html)：每行重复待机，所有姿态使用相同视窗与显示倍率。先展开对应动画，再展开其 before-after 对照。
- [引擎截图索引](../artifacts/character-scale/engine/captures.json)；[素材一致性检查记录](../artifacts/character-scale/validation.json)。

手绘画帧的透视、姿势和服装轮廓仍有自然差异，本轮校准针对人物整体比例。

## 离线复现

在项目根目录执行：

```powershell
# 按已保存的校准重建，完全离线
.venv/Scripts/python.exe tools/build_movement_art.py --part animation

# 为全部动作生成带待机参照的逐帧对照
.venv/Scripts/python.exe tools/review_character_scale.py

# 本次修改前的基线存在时，可额外生成前后对照
.venv/Scripts/python.exe tools/review_character_scale.py --baseline artifacts/character-scale/before

# 引擎重导入后运行自动检查
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
./tests/run_tests.ps1
.venv/Scripts/python.exe tests/art_pipeline_tests.py --with-previews

# 实际引擎关键阶段截图；仅复现受击检查时，在命令末尾追加 -- --hit-only
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --log-file artifacts/character-scale/capture.log --script res://tools/capture_character_scale.gd
```

