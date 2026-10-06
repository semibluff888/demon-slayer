# 九柱与上弦群像海报

本次主菜单背景保留炭治郎领衔鬼杀队、与猗窝座正面对峙的构图，扩充至 21 位角色。

- 主角组：炭治郎、祢豆子、善逸、伊之助。
- 九柱：富冈义勇、炼狱杏寿郎、蝴蝶忍、宇髄天元、甘露寺蜜璃、时透无一郎、悲鸣屿行冥、伊黑小芭内、不死川实弥。
- 鬼方：鬼舞辻无惨、黑死牟（上弦壹）、童磨（贰）、猗窝座（叁）、半天狗（肆）、玉壶（伍）、妓夫太郎与堕姬（陆）。

采用 imagegen 提示词规范和项目 CPA API/CLI 流程，模型为 `gpt-image-2`。第一轮以旧海报为参考扩充群像；检查发现缺少宇髄天元、妓夫太郎，第二轮只补充这两位。正式采用第二轮结果，第一轮保留为制作过程与编辑参考。

- [任务清单](../output/imagegen/title-ensemble-v3/jobs.json)
- [完整群像提示词](../output/imagegen/title-ensemble-v3/prompts/title-all-hashira.txt)
- [补绘提示词](../output/imagegen/title-ensemble-v3/prompts/title-all-hashira-r2.txt)
- [正式采用的源图](../output/imagegen/title-ensemble-v3/raw/title-all-hashira-r2.png)
- [生成与审核记录](../output/imagegen/title-ensemble-v3/records/title-all-hashira-r2.json)
- [导入记录](../output/imagegen/title-ensemble-v3/imports/title-poster.json)
- [游戏运行背景](../art/ui/title-poster.png)

请求尺寸 3840×2160，两轮实际返回均为 **1672×941**。保留原图像素，未裁切或放大冒充原生 4K。中文游戏名保留在海报内，菜单仍由 Godot 绘制；按钮宽度从 362 缩为 300，避开伊之助面具，菜单位置与操作保持原样。

离线重建只读取已保存且审核通过的源图，不调用生图服务：

```powershell
.\.venv\Scripts\python.exe -X utf8 tools/build_menu_art.py
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
```

`build_menu_art.py` 优先选择本次已采用的海报，源文件哈希须与审核记录一致；旧版源图仍保留。历史美术构建入口也调用该选择逻辑，避免降回旧背景。

本次进行生成图目视审查、资源导入和主菜单实机截图，未运行游戏测试。截图位于 [720p](../artifacts/title-ensemble-v3/title-1280x720.png) 与 [1080p](../artifacts/title-ensemble-v3/title-1920x1080.png)，可使用 `tools/capture_title_ensemble.gd` 重建。
