# 炭治郎技能特效（重制中）

目标：复刻《火之神血风谭》中炭治郎的水之呼吸和火之神神乐特效。参考拆解见 [tanjiro-reference.md](tanjiro-reference.md)。目前已完成水面斩样板（236A/C，含普通形态和觉醒水火交融两版），其余招式在样板确认后逐个替换。

## 结构

| 文件 | 作用 |
|---|---|
| `scripts/presentation/vfx/tanjiro_vfx.gd` | 炭治郎特效主体，挂在 `EffectsView` 下；`handles(move)` 列出已重做的招式，其余招式和其他角色仍走原代码 |
| `scripts/presentation/vfx/vfx_ribbon.gd` | 三角带彩带（直接提交三角形，弧线自交也安全），支持按弧长平铺纹理、选取纹理行 |
| `scripts/presentation/vfx/vfx_pool.gd` | 确定性粒子池（精灵表、重力、阻力、拉伸），只按传入的演出时间推进 |
| `scripts/presentation/vfx/blade_track.gd` | 读取刀身轨迹 `blade-tracks.json` |
| `scripts/presentation/vfx/shaders/erode_*.gdshader` | 彩带侵蚀：顶点 alpha 表示"存在度"，配合噪声碎成泡沫或火舌（`erode_mix` 正常混合，`erode_add` 叠加） |
| `art/effects/tanjiro/` | 生图素材加工结果和 `manifest.json`（来源、提示词、哈希） |

图层顺序（同一 z 时按树序）：

| 图层 | z | 内容 |
|---|---|---|
| WATER | 9 | 水丝彩带（侵蚀 Shader） |
| SOLID | 9 | 月牙浪精灵、卷浪 |
| FRONT | 10 | 命中水花、水珠、泡沫、火粒，以及月牙浪的火芯 |
| FLAME | 10 | 刀光残影（叠加） |
| LIGHT | 10 | 辉光、水雾、X 字闪光、冲击环、发动闪光（叠加） |

WATER 和 SOLID 低一层，受击者会被抬到 z 10，因此始终压在水体之上。

## 规则

- **形状由招式帧驱动**：形状只由 `move_frame` 和刀身轨迹决定。非冻结时可叠加物理插值小数，截图和测试会关闭这一项。
- **粒子由战斗 tick 驱动**：粒子按战斗 tick 生成，每个 tick 只生成一次，随机数由攻击实例和 tick 决定，因此逐帧推进和批量推进的结果相同。
- **冻结**：粒子和爆发只随 `EffectsView` 的演出时间推进，命中停顿、超杀冻结、暂停、KO 冻结时全部静止。
- **通用命中特效**：已重做招式的通用命中记录仍照常写入（测试依赖），但白光减弱、星芒不画，由本模块的金色 X 字和水花代替。
- **配色**：觉醒时水和火都用正常混合穿插；叠加混合的橙光会把蓝水冲成发白的淡紫。

## 水面斩（236A/C）

| 阶段 | 表现 |
|---|---|
| 起手（第 3 帧起） | 刀身上出现细水带，水珠被吸向刀身；判定前 4 帧身体蓝白闪光 |
| 判定 | 自脑后经头顶劈至前下方的大弧水斩，由 4 股收尖水丝和尾部 3 根散丝组成，外缘有浮世绘卷浪，最外侧是淡白刀光；1.5 帧内扫出，第 3 帧起从尾部侵蚀并碎成水珠；脚下有亮青色水痕 |
| 弹道 | 竖立的月牙浪（轻版、重版各一张图），后拖水丝，地面有水痕，沿途掉落水珠和水雾；寿命结束时碎成水珠和泡沫 |
| 命中 | 第一帧即为完整大小的水花冠，加金色 X 字闪光、冲击环、放射水珠；防御时是小水花向后溅 |
| 觉醒 | 水丝间穿插不透明火丝，月牙浪内包火芯，并伴随红色花瓣火粒和火星 |

重版（236C）的弧、浪、粒子均放大约 1.2 倍。

## 工具

```
python tools/build_vfx_reference.py overview|burst|palette|board ...   # 参考视频抽帧、调色板、参考板
python tools/build_blade_tracks.py tanjiro                              # 刀身轨迹与 QA 接触表
python tools/build_tanjiro_vfx_art.py                                   # 生图素材 -> art/effects/tanjiro/
godot --path . --fixed-fps 60 --script res://tools/capture_tanjiro_vfx.gd -- --moves=236A,236C --every=1
python tools/build_tanjiro_vfx_review.py sheet|compare|video <截图目录名> ...
```

生图走用户的 CPA 接口（gpt-image-2）。提示词、原图和记录在 `output/imagegen/tanjiro-vfx-v1/`，原图不入库。新增导入的贴图需要在 `.import` 中开启 `mipmaps/generate=true`。

## 测试

`tests/tanjiro_vfx_tests.gd`（已加入 `tests/run_tests.ps1`）覆盖以下内容：

- 路由与图层
- 刀身轨迹
- 弧线几何
- 冻结与零速
- 不修改战斗状态
- 命中爆发
- 弹道释放
- 全部粒子在 1.5 秒内消失
- 重置清空
- 逐帧与批量推进结果一致
