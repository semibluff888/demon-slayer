# 录制与空间管理

游戏运行只依赖 `art/`、`moves/`、`resources/`、`scenes/`、`scripts/` 和 `project.godot`。以下规则只影响开发时的测试证据，不修改游戏画质、帧率、输入或战斗规则。

## 默认保存视频

`capture_moves.gd`、`capture_idle_loop.gd`、`capture_tanjiro_vfx.gd` 共用 `capture_output.gd` / `capture_output.py`。需要项目 Python 环境，以及 PATH 中的 `ffmpeg`、`ffprobe`。缺少编码工具会在录制前报错，不会退回无限 PNG 输出。

```powershell
$engine = & tools/find-godot.ps1
& $engine --path . --fixed-fps 60 --audio-driver Dummy --script res://tools/capture_moves.gd -- --character=akaza --no-cinematic --script=idle:30,5A,idle:30,236A
```

输出为 `artifacts/art-v3/akaza/moves/capture.mp4` 与小型 `capture.json` 记录。待机录制按形态分别输出；炭治郎特效按招式、形态、朝向分别输出。视频为供人工检查的 H.264，正式游戏素材不经过此编码。

- 累积到 120 帧或约 128 MiB 时，编码一个片段；逐帧解码计数验证成功后才回收对应 PNG。不另复制整套中间图。
- 最终拼接片段并再次核对总帧数，成功后替换上次 `capture.mp4`，删除临时片段。
- 编码或校验失败保留当前 PNG、已验证片段和上次成功视频；排查后可重新录制，或执行完整清理。重新录制会重置该序列的旧中间帧。
- 单序列最多 18,000 帧、编码片段总计 512 MiB，超限报错并要求拆分，防止异常输入长时间写盘。正常模式临时 PNG 上限约为 128 MiB 加最后一帧。
- `--every=2` 的特效捕获以 30 FPS 编码，保持动作的真实时长，不会被错误地当成 60 FPS 加速播放。

## 无损逐帧质检

需要像素对比、刀尖标定或 `build_tanjiro_vfx_review.py` 接触表时，加 `--keep-frames`，保留原来的 PNG 文件名。默认每个序列最多 512 MiB；确需更多时加 `--max-raw-mib=1024`，允许范围为 1–2048 MiB。建议拆分招式、形态和朝向。不要把同一套 PNG 复制到 `review5`、`review6` 等历史目录；长期证据保存小型视频或精选对比图。

```powershell
& $engine --path . --fixed-fps 60 --script res://tools/capture_tanjiro_vfx.gd -- --moves=236A --forms=normal --facings=1 --every=2 --keep-frames
.venv/Scripts/python.exe tools/build_tanjiro_vfx_review.py sheet 236A-normal-right --ticks 8,10,12
```

重录会移除该序列旧的编号帧，避免短录制混入上次较长录制的尾帧；不会通配删除笔记或其他文件。无损录制成功后会删除该目录中上次的 `capture.mp4`，`capture.json` 记录本次为逐帧输出，避免旧视频与新帧混在一起。`build_tanjiro_vfx_review.py video` 按 `capture.json` 的真实帧率把这些 PNG 编成复查视频。

正在录制的目录有进程标记 `.capture-active.json`，记录录制进程的 PID 和启动时间，另一次录制不能覆盖。标记以原子替换写入；进程已退出、PID 被其他程序复用，或标记无法读取时，一律视为失效：可以直接重录，清理也不会因此中止，无需手动删除。

## 自动保留策略与手动清理

测试入口和上述主要录制工具在开始时运行 `clean-local.ps1 -Apply -RetainRecent`：只管理 `artifacts/`，清理超过 7 天的非活动产物，或按最旧目录回收至 2 GiB。按完整叶目录回收，避免留下半套编号帧；当前录制的目录暂不参与淘汰。最近 24 小时内的目录不会因容量被回收（`-RecentGraceHours` 可调，0 表示关闭），刚录好的 `--keep-frames` 质检帧因此能留到出完接触表；此时总量仍超上限会给出警告，需要时手动执行完整清理。有文件被回收时会打印一行摘要，列出目录。旧版录制工具的产物也会在下一次测试或主要录制时进入此保留策略。磁盘上未运行工具的静态文件不会自行定时删除。

```powershell
# 预览（不删除）；完整清理包括 tmp、参考抽帧、review 和失效导入
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1 -Apply
# 手动维护最近的测试证据
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1 -Apply -RetainRecent
# 参考视频也不再需要时（目前特效分析仍在使用 output/downloads/ 中的参考视频）
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1 -Apply -IncludeReferenceDownloads
```

清理器先验证全部目标路径在项目内、拒绝链接/目录联接，跳过 Git 跟踪文件、`.gdignore` 和活动录制目录。制作源图、提示词、标定/来源记录、必杀动画母片、字体源文件、开发环境、有效导入缓存和最新发行包保留。Git 历史不改写；被跟踪的历史预览即使匹配新的忽略规则也不会自动删除。

`output/imagegen/*/review/` 的对比图由保留的源图和标定重新生成，不再入库。需要把某张对比图作为检查点证据长期保存时，用 `git add -f` 显式加入。
