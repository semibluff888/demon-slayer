# 晨曦群像主菜单海报

2026-10-19 起，主菜单背景改用用户提供的晨曦群像图：炭治郎、祢豆子、善逸、伊之助与义勇、蝴蝶忍、炼狱、宇髄、蜜璃、无一郎坐立于映水回廊，背后是淡色朝阳与远山。左上角的「鬼滅の刃 / KIMETSU NO YAIBA」与标语是图内自带的题字，游戏不再叠加标题文字。

- [来源与审核记录](../output/user-assets/title-poster/manifest.json)（原文件名、SHA-256、尺寸）
- [原图](../output/user-assets/title-poster/raw/nine-friends-sunrise.png)
- [超分处理记录](../output/user-assets/title-poster/hd/nine-friends-sunrise.json)（模型、命令、遮罩、裁切与哈希）
- [导入记录](../output/user-assets/title-poster/imports/title-poster.json)
- [游戏运行背景](../art/ui/title-poster.png)

前一版[九柱与上弦群像海报](title-ensemble.md)的源图和记录仍保留，`tools/build_menu_art.py` 的候选列表以本图为首选。

## 4K 超分

原图只有 **1672×941**，1080p 以上直接拉伸会发糊。沿用庭院的离线流程，用 Real-ESRGAN ncnn Vulkan v0.2.0 的 `realesrgan-x4plus-anime` 模型做 4 倍超分（6688×3764），推理结果保存在 `hd/`，重建时不再运行模型。

- 人物线条、眼睛、羽织纹样与图内题字明显变清晰；山脊和题字边缘有极淡的亮边，缩小显示后看不出。
- 该模型会把远处有雾的城镇和树林压成色块，并在树冠上生成亮点。因此伊之助左侧、天际线到地面边沿之间的区域（原图坐标多边形，8 px 羽化）改用原图 Lanczos 放大，保留雾气。
- 上下各裁 1 行得到精确 16:9，再 Lanczos 缩到 **3840×2160** 作为运行贴图（PNG 约 4.5 MB；含 mipmap 约 33 MB 显存，回到标题页时加载约 95 ms）。

## 菜单适配

新图整体明亮，题字是浅底深字，原来从画面中部铺开的深色墨晕会压暗题字和天空，因此标题页按新构图重新排布：

- **选单**：按钮移到题字下方，左缘 `x = 56` 与图中题字对齐；宽度由 336 缩为 320，聚焦时的朱红笔刷也不会碰到伊之助。最初五项从 `y = 382` 起、高 50、间距 56；2026-10-19 加入第六项「退出游戏」后改为 `y = 374` 起、间距 52，同时去掉焦点项说明文字。
- **墨晕**：只覆盖题字以下的远山与城镇（`y ≥ 368`，向右渐隐），保留天空与朝阳原貌；底部提示条的墨带只在说明文字和按键提示下方加深，中间映水地面仅轻微压暗。
- **微粒**：余烬换成暖白色晨光微尘，从映水地面缓缓上浮，越过山脊线前淡出，避免在浅色天空上变成白点。

## 复现

离线安装，不调用任何服务：

```powershell
.\.venv\Scripts\python.exe -X utf8 tools/build_menu_art.py
& $godot --headless --path . --editor --import --quit
```

`build_menu_art.py` 核对源图与超分结果的哈希都和记录一致后，合成并写入 `art/ui/title-poster.png`；删除或拒绝 `hd/` 记录即回到原图直装。`tests/fate_art_tests.py` 检查运行图与重新合成的结果逐像素一致。

截图需窗口运行，输出到 `artifacts/title/`（720p、1080p 与 4K）：

```powershell
& $godot --path . --fixed-fps 60 --script res://tools/capture_title.gd
```
