# 战斗 UI 与动作比例补充修正

2026-09-23。暂停和练习设置恢复选人菜单的深蓝底、金线和红色选中按钮，详情选项恢复原生 CheckButton。MAX 完整头部按原比例适配书法图行高，单人 152px、双人 104px；按施放时实际屏幕左右半区定位，包含双方挤在同一版边的情况。突进换边后不跳位。移除所有书法图上方的额外标记。

## 素材校准

以下倍率相对于本轮修改前。帧号从 0 开始。

| 角色 | 动作 | 调整 |
| --- | --- | --- |
| 炭治郎 | 前滚／后滚 | 整组 ×0.90／×0.94 |
| 炭治郎 | 站立重体术 | 整组 ×0.95 |
| 善逸 | 站立重体术 | 整组 ×1.08，恢复先前过度缩小的部分；保留低架和屈膝 |
| 炭治郎 | 正投／背投受方 | 第 6–11／5–11 张源画帧 ×1.12 |
| 善逸 | 正投／背投受方 | 第 7–11 张 ×1.14／第 8–11 张 ×1.08 |

原始受投图后半段就存在身体收缩。为避免放大正确的抓取帧，增加显式离线 `drawing_registration`，为 22 张异常源画帧记录固定倍率、参照和原因。运行时仍采用公共身高和固定镜头倍率，不按轮廓动态缩放；腾空保留骨盆定位，落地保留实测接触点。原始 PNG 不修改。标定、导入记录、运行图集及总清单同步更新。

本轮实际修改 8 组动作中的 64 张画帧，其余 553 张画帧逐像素不变。重新导入这 8 组的 90 张画帧，与图集逐像素一致。战斗规则、时序、耗气、投技路径、伤害和判定未改动。

## 检查和复现

[前后对照、四种奥义短片和实机截图](../artifacts/battle-revisions/index.html)；[检查记录](../artifacts/battle-revisions/acceptance.json)。

真实输入驱动两人、左右朝向、1280×720／1920×1080 的起手、有效段、收招、恢复待机及落地第 8–11 帧，共 264 张动作截图，0 项失败。MAX／菜单覆盖 960×540 至 3840×2160 与 1600×1000 留边。手柄焦点使用模拟原生事件验证，未连接实体手柄。

```powershell
.venv/Scripts/python.exe tools/build_movement_art.py --part animation
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
./tests/run_tests.ps1
.venv/Scripts/python.exe tests/art_pipeline_tests.py --with-previews
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --script res://tools/capture_character_scale.gd -- --revisions
# 以下命令追加 -- --video 可录制四种奥义
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --script res://tools/capture_battle_revisions.gd
.venv/Scripts/python.exe tools/build_battle_revision_review.py --encode
```
