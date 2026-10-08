# 祢豆子觉醒动作修订 v8

本轮只替换 12 组动作、90 帧：前后行走、前后冲刺、四种空中攻击、爆血飞踢、升空踢、回旋踢、血鬼术·爆血。用户已认可的待机、MAX 及其他 31 组动作共 258 帧保持像素、尺寸和偏移一致。

## 造型与位置

- 实际将已认可的待机和 v7 MAX 图片作为 CPA 生图附件。保留角色既有造型，以 MAX 的躯干、腿长及头身比例重绘本轮动作。
- 前后走动按 354～357 图集像素校准站立高度；腰部横坐标固定为 449，脚底为 569。六帧循环包含接触、过渡及换脚姿势，按游戏移动速度调整为 20 FPS。世界移动速度不变。
- 冲刺和技能以 59.5 图集像素的头骨长度为共同标尺，并在同尺度全身对照中复核。俯身、抬腿造成的轮廓高度变化保留，不按外接框强行拉伸。
- 空中四种攻击固定腰部基准为 (449, 322)，避免屈膝或伸腿改变整个角色的位置。
- 腰部坐标直接逐帧标定，不再依赖绿色衣片自动定位，也不继承 v7 的错误横向偏移。
- 源图有三帧脚部靠近边缘，采用本轮完整的对应踢腿姿势替换。来源、SHA-256、索引及原因均保存在 `motion-calibration.json` 的 `source_override`。
- 攻击时序、判定、跳跃轨迹和既有 1.15 倍形态规则不变。已认可 MAX 全部画帧与位置均保留。

## 可追溯素材

采用 cpa-imagegen + 原装 imagegen CLI，服务为已授权的 `cpa2.8201128.xyz`，模型 `gpt-image-2`，高质量。15 次请求完成（14 个初始分图请求和 1 次步态修订），未进行不确定结果的自动重试。

- `references/`：实际传入的待机、MAX 与步态骨架附件。
- `prompts/`、`generation-jobs.json`、`cycle-refinement.json`：生成提示词与请求清单。
- `records/`：请求状态；`raw/`：原始图源和无缩放拼接图。
- `selected.json`：步态采用 v2 修订。
- `motion-calibration.json`：绑定源图 SHA-256 的逐帧标尺与位置。
- `imports/`：最终缩放、偏移及来源；`baseline/`：本轮开始时的完整 v7 图集。
- `review/fixed-ruler.html`：同尺度全动作对照，禁止逐格适配轮廓。
- `acceptance.json`：最终验收、实机预览、图集和发布包哈希。

头骨量测有约 3 个源像素的人工作业误差；以全身同尺度图及实机画面共同判断，不把标尺数字当作美术一致性的唯一证据。

## 离线重建与验证

```powershell
.venv/Scripts/python.exe tools/build_nezuko_awakening_v8.py
.venv/Scripts/python.exe tools/review_awakening_motion.py --source-dir output/imagegen/awakening-v8
$awakeningEngine = & ./tools/find-godot.ps1
& $awakeningEngine --headless --path . --editor --import --quit
& ./tests/run_tests.ps1
& $awakeningEngine --path . --audio-driver Dummy --script res://tools/capture_awakening.gd -- --character=nezuko --output=res://artifacts/awakening-v8 --gallery --max-review --motion-review
```

最终构建不能使用 `--partial`。未提供完整标定或源图哈希变化会停止导入。以上重建无需重新调用 CPA。
