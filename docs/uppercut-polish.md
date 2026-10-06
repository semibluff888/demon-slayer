# 升空踢、角色比例与升龙调整

[实机对比与录像](../artifacts/uppercut-polish/index.html) · [升龙测量记录](../artifacts/uppercut-polish/verification.json)

## 祢豆子

- 升空踢的最终渲染结果水平翻转：同时反转源纹理翻转标记与旋转角，避免只翻贴图却留下反向旋转。面向左、右时均保持圆弧主要朝外。
- 站立 B、D、蹲防分别对原校准倍率再乘 1.085、1.045、1.12；使用同一动作内的统一倍率，脚底锚点保持一致。
- 祢豆子的整体 `model_scale = 0.85` 保留。修正局部动作比例，不扩大祢豆子的整体身高。
- B/D 各帧身体高度与待机约相差 2% 以内；蹲防以露出的脸部与躯干作为尺度参照，不把蹲姿拉成站立高度。

校准记录位于 [scale-calibration.json](../output/imagegen/roster-v1/scale-calibration.json)，对比页面左侧 P1 使用保存的修改前图像，右侧 P2 使用当前图集，二者使用相同角色倍率与战斗状态。

## 升龙轨迹与连段

参考同类格斗游戏的设计方式：地面起手、上升攻击、下落、落地恢复；轻版紧凑，重版更高且恢复更长。以下均为本项目实际测量，不是对拳皇／街霸某一版本帧表的复刻。战斗逻辑仍为 60 Hz。

| 版本 | 最大离地高度（游戏单位） | 腾空逻辑帧 | 不含命中停顿的腾空时间 | 落地后恢复 |
| --- | ---: | ---: | ---: | ---: |
| 修改前 A / C | 12.08 | 15 | 0.25 秒 | 轻重轨迹相同 |
| 623A | 37.18 | 26 | 约 0.43 秒 | 11 帧 |
| 623C | 58.14 | 33 | 约 0.55 秒 | 13 帧 |

四人的 A/C 使用这组轨迹，原伤害、起手帧、有效攻击帧及对空保护时间保留。新增 `lift_frame` 表示在起手完成后离地，`launch` 表示命中时挑起对手；对手落地进入倒地状态。起手中被打断不会延迟起跳，KO 收尾中也会完成计划好的起跳与落地。

`5A → 5C → 623A/C → 236236A / 236236AC` 可以连续命中。升龙仍需命中确认才能取消奥义／MAX。本页首次调整仅在有效期内开放取消，后续已按实操反馈增加收招前 12 帧的余量；现行窗口、缓冲与慢速输入验证见[游戏设置与连段容错](menu-settings.md)。取消时停止继续上升、自然下落，防止地面奥义在高处站着播放或漏掉后续命中。挥空、被防、过晚输入均不能取消。

| 角色 | 轻升龙接奥义 / MAX | 重升龙接奥义 / MAX |
| --- | ---: | ---: |
| 祢豆子、善逸 | 491 / 656 | 513 / 678 |
| 炭治郎、猗窝座 | 500 / 665 | 522 / 687 |

表格是上述完整路线的总伤害。奥义／MAX 本身完整命中仍为 280／445。验证覆盖四人全部 16 种对阵、左右朝向、中场和版边；首击之后对手持续按后防守，以检查连段空隙。命中停顿、奥义冻结会增加实际观看时间。

## 善逸上撩美术

善逸原上撩主要是地面居合姿势，现在替换为独立九帧序列，包含蓄势、离地、空中屈膝上撩和落地收刀。腾空恢复阶段根据上升／下落保持相应姿势，落地前不显示最后的站立收刀帧。上撩继续属于游戏演绎动作。

使用 imagegen 提示词规范和项目已有 CPA API／CLI，模型 `gpt-image-2.5`。原始输出实际为 1254×1254；提示词、两张角色参考、源图、哈希、逐帧裁切、脚底／骨盆校准均保存于 [uppercut-v1](../output/imagegen/uppercut-v1/jobs.json)。整组动作使用统一尺寸，独立图集为 [uppercut-iai.png](../art/characters/zenitsu/uppercut-iai.png)，旧图集重建后会自动重新应用已登记的动作覆盖。

## 庭院高清资源

旧庭院生成源图为 2172×724，游戏裁切为 2172×543，720p 下需要绘制到 3168×792，因此可见放大模糊。本次对完整源图使用本地 **Real-ESRGAN x4plus-anime** 进行四倍神经网络超分，获得 8688×2896，再按原裁切区域精确乘四裁为 **8688×2172**。不改变相机、地平线、场地宽度及角色落脚位置。

超分先处理整张图，再拆成四张 2172×2172 纹理，每块附 8 像素边缘扩展，启用 mipmaps；没有独立重绘分块引起的几何接缝。瓦片、窗格、木廊和植被边缘已与原图对照，场景检查包含左右卷动以及 720p／1080p／4K 实机画面。

这里的 8688×2172 是**超分后尺寸**，原始生图仍为 2172×724，二者在 [processing.json](../output/imagegen/courtyard-hd-v1/processing.json) 中分别记录。先前尝试的十张 CPA 细节分块因网络超时未产出可接受素材；相关提示词与不确定请求记录保留，不自动重试，也未用于游戏。最终采用已生成庭院图的本地后处理。

离线处理工具、所选模型、许可证和哈希保存在 [distribution.json](../output/super-resolution/distribution.json)。默认重建使用保存的超分结果，得到相同图像；`tools/build_courtyard_hd.py --reprocess` 会使用本地模型生成独立候选图，供人工复核，不覆盖已接受结果。

| 素材 | 实际尺寸 | 位置 |
| --- | --- | --- |
| 原始 CPA 生成庭院 | 2172×724 | [原图](../output/imagegen/fate-v1/raw/corps-courtyard.png) |
| 整图四倍超分结果 | 8688×2896 | [处理结果](../output/imagegen/courtyard-hd-v1/raw/corps-courtyard-realesrgan-x4plus-anime.png) |
| 游戏连续全景 | 8688×2172 | [运行素材](../art/stages/corps_courtyard/panorama.png) |

## 离线重建

以下命令只使用项目中保存的源图，不调用生图接口：

```powershell
.\.venv\Scripts\python.exe -X utf8 tools/build_roster_art.py --part animation --character nezuko
.\.venv\Scripts\python.exe -X utf8 tools/build_uppercut_art.py
.\.venv\Scripts\python.exe -X utf8 tools/build_courtyard_hd.py
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
.\tests\run_tests.ps1
```

显式生图入口是 `tools/run_roster_art_job.ps1 -Manifest <清单> -Id <任务ID>`。已有图片或状态不确定的请求不会自动重试。可传入 `-Python .venv-imagegen/Scripts/python.exe -PreferIPv6`，仅让生图子进程对配置的 CPA 域名优先使用 IPv6；仍使用原主机名与正常证书验证，系统网络设置不变。

## 验证与录像

- 新增升龙专项 1221 项：轨迹、起手与落地、左右特效镜像、完整连段、耗气、受防、挥空、被打断及 KO 收尾。
- 图像检查覆盖 B/D 的逐帧比例和脚底、蹲防头部尺度，以及善逸新动作来源、锚点和抠图边缘。
- 最终完整测试与 30／60／144 渲染帧率一致性结果见 [full-suite.log](../artifacts/uppercut-polish/full-suite.log)。
- 截图由 Godot 正式渲染路径产生，连段由真实方向与按键输入驱动；录像为 30 FPS 静音捕获。

```powershell
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --script res://tools/capture_uppercut_polish.gd
.\.venv\Scripts\python.exe -X utf8 tools/build_polish_review.py --encode --ffmpeg "E:/Program Files/ffmpeg-7.1.1-essentials_build/bin/ffmpeg.exe"
```
