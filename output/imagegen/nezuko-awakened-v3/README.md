# 鬼化祢豆子：静态定稿与待机动画

以用户指定的 `review/Fierce Oni Woman in Motion-1.png` 为完整待机原画，原样保存至 `references/approved-idle-master.png`。当前交付为 [待机动画 v2](idle-animation-v2/README.md)：12 帧、10 FPS、1.2 秒循环，已按反馈稳定膝盖和小腿，保留其余已认可的运动。

本次是静态原画与待机动画的阶段保存。静态原画已确认；动画整体此前已认可，腿部修订尚未单独获得明确确认，状态见 `review-status.json`。正式游戏图集、其他招式、头像和运行时代码尚未接入或修改。

## 保留文件

- `references/approved-idle-master.png`：唯一的后续造型基准，SHA-256 为 `62f7fc549a7f92e67e8f3bc5b34b24b74b019aced33cfcb5d6c5560a7ca9c96f`。
- `references/`：用户参考、当前游戏配色及身高对照素材，供后续动作制作使用。
- `idle-animation-v2/`：透明原画、12 帧原尺寸动画、游戏画布帧、独立图集、绑定参数及离线导出脚本。
- `prompts/`、`jobs.json`、`records/`：此前制作与校验的文字记录；其中历史路径仅表示当时的输入输出，不代表废稿仍保留。
- `runtime-baseline.json`：本阶段未更改的正式游戏文件校验值。

被定稿替代的 r1–r8 废稿、旧透明图和对照图、v1 动画输出、过期压缩包及仅供废稿使用的脚本，已移入本地 `.archive/2026-10-20/` 可恢复归档，不进入 Git。自动审批拒绝永久删除包含旧源图和脚本的清单，因此本次采用归档清理。完整清单见 `records/cleanup-2026-10-20.json`。v1 对照帧由当前脚本在内存中复现，并与清理前记录的像素哈希比对，无需读取旧图片。

预览图、视频和 ZIP 交付包保留在本地，但不重复放入 Git；均可从已提交的素材重新导出。用户指定的原文件路径保留，Git 中存放其 `references/` 下的同内容副本。

## 固定规格

- 高清画布 1120×1664；头长约 209 像素，约 7.23 头身；头部和角只平移、不缩放。
- 游戏画布 1024×640；固定脚底 `[448,568]`，统一缩放 `0.23436471362738645`、位移 `[290,197]`。
- 保持现有鬼化待机总显示高度：图集 356 像素、游戏约 71.645 单位。
- 稳定膝盖和小腿横向宽度，纵向呼吸位移最多 0.16 个高清像素；鞋与脚底固定。
- 表情、衣领、藤蔓纹、绑腿、鞋、身高和配色均以原画为准；动画不逐帧重新生图。

## 离线重新导出

使用项目 Python 环境，需 Pillow、NumPy、OpenCV；视频导出需 PATH 中的 ffmpeg。脚本使用 Windows 微软雅黑字体和现有 `tools/art_v3/idle_warp.py`。

```powershell
.venv/Scripts/python.exe -X utf8 output/imagegen/nezuko-awakened-v3/idle-animation-v2/prepare_master.py
.venv/Scripts/python.exe -X utf8 output/imagegen/nezuko-awakened-v3/idle-animation-v2/build_animation.py
```

校验包含循环衔接、固定脚底、刚性头部、腿部宽度、修订区域以外逐帧不变以及运行时文件未改动。构建不会调用 CPA，也不会安装正式游戏图集。
