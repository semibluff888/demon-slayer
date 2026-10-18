# 选人展示视频

选人页左右两侧播放的角色展示视频，来自用户提供的 AI 生成片段：纯品红底，768×1152，24fps，10 秒，原片带的音轨已去掉。Godot 内置只支持 Theora，而 Theora 没有 alpha 通道，所以离线抠像后把「预乘彩色 + 透明度」叠在同一帧里编码，游戏内用 shader 还原。若在运行时对 4:2:0 视频抠品红，会出现锯齿和粉边。

## 文件

| 位置 | 内容 |
| --- | --- |
| `output/user-assets/select-videos/raw/<id>.mp4` | 原始片段（只读，sha256 记录在 manifest） |
| `output/user-assets/select-videos/manifest.json` | 原文件名、哈希、处理参数、循环接缝、输出哈希与质检指标 |
| `art/characters/<id>/select.ogv` | 576×1744 Theora：上 864 行为预乘彩色，中间 16 行黑色隔离带，下 864 行为灰度 alpha；无音轨，每秒一个关键帧 |
| `art/characters/<id>/select.json` | 帧尺寸、隔离带、fps、帧数、接缝和触边情况；shader 的分带参数从这里读 |
| `art/characters/<id>/select-poster.png` | 从 ogv 解码回来的第 0 帧，同样是叠层布局；用于换片时的垫图、无窗口测试和兜底 |
| `artifacts/select-videos/<id>/` | 质检图（`sheet.png` 深色底和棋盘格、`seam.png` 循环接缝前后、`edges.png` 头肩放大）和 `metrics.json`，可重新生成 |

## 管线 `tools/build_select_videos.py`

1. **解码**：ffmpeg 以 rawvideo 管道逐帧输出 RGB。生成片段没有色彩标记，显式按 bt709/tv 解码。
2. **背景板**：每帧用品红度 key＝min(R,B)−G 大于 200 的像素拟合一张二次曲面。人物会触及画面边缘，所以不用边框中位数。
3. **分类与抠像**：
   - key＜64 为实心前景（人物内部实测 ≤52，祢豆子的粉色眼睛也在此范围）。
   - 接近背景板的像素为背景。
   - 离前景 4 px 以内的过渡像素：用距离变换找最近的前景色，沿「背景→前景」方向反混合求 alpha，颜色取该前景色。
   - 被人物包住的过渡像素保持实心；但品红度超过 100 的不算，那是隔着呼气雾看到的发丝缝隙。
   - 远离前景的过渡像素（呼气雾）：按品红度比例求 alpha，先扣掉噪声死区，再做 3 帧时间中值防闪烁。
   - 最外一圈实心像素做轻度去品红。
4. **缩放**：预乘状态下用 INTER_AREA 缩到 576×864，在 1080p 窗口里正好 1:1 显示。
5. **循环**：
   - 在起点 0–48、终点 192–239 中搜索：先比较 10 帧重叠段的剪影 IoU 与颜色相似度，再略微偏向更长的循环，以保留片尾。
   - 接缝做叠加式溶解：开头的姿势先在结尾姿势上淡入，结尾姿势再在下方淡出，避免两个半透明剪影叠出透空的身体。
   - 输出的第一帧是一帧干净的原帧。
6. **编码与校验**：libtheora `-q:v 8 -g 24`，按 bt601/tv 写入（Godot 的 Theora 解码按此换算）。之后检查流参数，完整解码一遍；再按 shader 的方式回读，计算角落 alpha、残余品红比例、背景噪声和接缝跳变。

源视频是动画常见的「一拍二」，相邻帧大量重复，所以接缝指标与「有动作的帧间差」比较，不和中位数比。

## 运行时

- `CharacterVisual._load_select_assets()` 在加载菜单素材时一并读取 `select_video`／`select_poster`／`select_layout`，对局资源释放时不清理。
- `scripts/ui/select_video.gd` 包含视频播放器和两层 poster，三者共用 `scripts/ui/shaders/stacked_alpha.gdshader`：
  - shader 用预乘混合，在 `vertex()` 里取 modulate；`mirror` 控制 P2 镜像，`inner_right` 决定只柔化靠屏幕中央的一侧，底部渐隐，并扣除编码噪声底。
  - 换角色先去抖 0.18 秒，只有光标停住的角色才启动解码。
  - 旧角色最后一帧在下方淡出；新角色的 poster 一直显示，直到解码器画出第一帧。
  - 循环由 `VideoStreamPlayer.loop` 完成，接缝处只停顿一个 60Hz 画帧，不闪黑。
  - 光标停在随机格或空位时，播放器停止并隐藏。
- 无窗口（headless）运行时只挂流、显示 poster，不解码；测试可把 `SelectVideo.headless_playback` 设为 true 做真实播放。
- `fighter_showcase.gd` 把视频放在 (0,144,384,576)，P2 放在 (896,144) 并镜像。原片左右会被裁掉，这样裁边正好落在屏幕边缘。角色没有视频时显示立绘。

## 新增或替换角色视频

```powershell
.venv\Scripts\python.exe -I tools/build_select_videos.py --import <片段.mp4> --id <角色id>
.venv\Scripts\python.exe -I tools/build_select_videos.py --only <角色id>
& $godot --headless --path . --import    # 新 poster 生成 .import，新 ogv 生成 .uid，与源文件一起提交
```

片段要求：纯品红底、竖幅 2:3、人物从头到腿且头顶不出框。阈值和画幅参数都是脚本顶部的常量，修改后需全部重建，manifest 会记录本次使用的参数。重建后请逐张查看 `artifacts/select-videos/<id>/` 下的质检图。

## 验证

- `tests/select_video_tests.py`：
  - 无需 ffmpeg：manifest 哈希、Ogg/Theora 头（尺寸、24fps、4:2:0、单一视频流）、`select.json`、poster 的隔离带、角落、躯干、预乘一致性和残余品红。
  - 有 ffmpeg 时：完整解码，检查每帧角落透明和循环接缝。
- `tests/select_screen_tests.gd`：宫格、循环光标、空位、随机与揭晓延迟、鼠标、展示视频挂载与去抖、立绘兜底，以及一次真实解码播放。
- `tools/capture_select_screen.gd`（需窗口，`--fixed-fps 60`，可加 `--hd`）：录制 `artifacts/select-screen*/capture.mp4` 和静帧，并在真实 GPU 合成下检查 matte、屏幕无品红、P2 操作不打断 P1 视频、循环接缝。
