# 祢豆子觉醒动态比例修订 v7

本轮以已经认可的游戏内 v6 待机为唯一造型基准。6 帧待机从基线图集逐像素复制；38 组动态动作、300 帧重新生成并注册，包含未持续觉醒时使用的 MAX。图集仍为 43 组、348 帧，回合演出的 42 帧继续沿用现有正常形态规则。觉醒头像、普通形态、猗窝座及其他角色资产保留。

## 比例与表情

旧流程按每帧完整轮廓适配尺寸，长发、踢腿和蹲身会改变人体在游戏中的比例。v7 使用经过人工检查的头骨长度作统一标尺，以腰带定位横向身体根部，并保留原动作的底部接触位置。源图按比例整体缩放，不单独拉伸宽高，也不按人物边界重新填满格子。

目标头骨长度约 59.5 图集像素，不包含角、松散头发或张嘴产生的下颌延伸。人工量测存在约 3 个源像素的不确定性，因此数值检查之外必须查看同尺度全身对照与实机动作。不能用每格自动缩放的缩略图证明体态一致。

初版动态生成后，再以待机作为唯一图片附件重新制作 12 组地面动作，以及 MAX 和受投动作，避免旧动作参考把短肢、大头体态带入新图。攻击和技能在发力阶段使用张嘴、露牙或咬牙表情，准备、收招和移动阶段保留克制表情。

## 来源与构建

生图使用已授权的 CPA 服务、安装的 imagegen CLI、`gpt-image-2` 和 high 质量。参考图作为实际附件传入。未更改模型服务配置或技能实现。

- `master.json`、`references/approved-game-idle.png`：造型基准。
- `baseline/`：改动前 v6 图集，用于待机保留及前后对照。
- `jobs.json`：39 组导入任务与既有时序，待机标记为保留。
- `generation-jobs.json`、`max-pilot.json`、`corrections.json`、`face-correction.json`、`model-refinements.json`：生成和定向修订任务。
- `selected.json`：最终采用的 12 组地面重绘。
- `anatomy-calibration.json`：38 组动态动作的逐帧标尺与源文件 SHA-256。源图改变会阻止沿用旧标定。
- `records/`：请求记录与长动作拼接来源。多张动作表只补空白并拼接，保持原始像素；受投首帧采用另一张已校验的等效受力姿势，记录于 `frame_overrides`。
- `imports/`：实际采用的源文件、缩放、位置和标定方式。
- `preserved-runtime.json`：应保持不变的其他运行资产哈希。
- `review/fixed-ruler.html`：按同一像素尺度对比所有动作；`motion-ruler.gif` 为素材动作序列预览。
- `acceptance.json`：最终选择、运行资产哈希与验证结果。

从已经保存的素材离线重建，无需再次付费生图：

```powershell
.venv/Scripts/python.exe tools/build_awakening_art.py --source-dir output/imagegen/awakening-v7 --character nezuko
.venv/Scripts/python.exe tools/review_awakening_motion.py
.venv/Scripts/python.exe tests/awakening_art_tests.py
```

`prepare_nezuko_awakening_v7.py` 是最初的生产准备脚本，会重建任务清单；最终重建请使用上面的导入命令，保留现有选择、拼接记录和标定。一般也不需要重新执行生图或拼接步骤。

实机验证使用 `tools/capture_awakening.gd -- --character=nezuko --output=res://artifacts/awakening-v7 --gallery --max-review --motion-review`。其中图库为指定帧渲染，运动序列通过真实方向及按钮输入；持续/非持续 MAX 在左右朝向分别验证。运动展示开启已有练习无限觉醒选项，其他流程仍检查正常到期和重置。

最终交付：完整回归、8项美术专项、48项实机检查通过；30/60/144 FPS状态一致。Windows包 `dist/DemonSlayer-0.2.3-nezuko-motion-windows-x86_64.zip` 已通过84招资源一致性、64条发布版连招及ZIP完整性检查。最终哈希与全部素材选择见 `acceptance.json`。实机预览为 `artifacts/awakening-v7/motion-preview.mp4` 和 `motion-overview.jpg`。
