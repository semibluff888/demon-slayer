# 游戏 BGM 源文件

这里保存游戏实际使用的 8 首 BGM 的源音频和来源记录，不随游戏打包。游戏读取的是由这些源文件生成的 `art/music/<标识>.ogg`，曲目的显示名、入场点、循环区间和混音参数写在 `resources/music/library.json`。设计说明见 [docs/music.md](../../docs/music.md)。

## 曲目

| 标识 | 显示名 | 用途 | 时长 | 来源 |
| --- | --- | --- | --- | --- |
| `homura_movie` | 炎 · 电影版 | 主界面（默认） | 4:49 | LiSA《炎》MOVIE version，《无限列车篇》原声，官方音源 |
| `tanjiro_no_uta` | 灶门炭治郎之歌 | 主界面 | 5:30 | 椎名豪、中川奈美，OST 版，《立志篇》原声，官方音源 |
| `kisatsutai` | 鬼杀队 | 主界面 | 3:24 | 椎名豪，OST 版，《立志篇》原声，官方音源 |
| `hakuji_okaeri` | 狛治 · 欢迎回家 | 主界面 | 1:50 | 无限城篇第一章配乐 M80，B 站剪辑段 |
| `hashira_infinity_castle` | 柱结集 · 无限城之邀 | 选人（从 2:52 起）、战斗 | 5:46 | 椎名豪《柱結集～無限城への誘い》，《柱训练篇》原声，官方音源 |
| `rengoku_kyojuro` | 炎柱 · 炼狱杏寿郎 | 战斗 | 1:38 | 椎名豪，《无限列车篇》原声，官方音源 |
| `hekireki_issen` | 霹雳一闪 · 六连 | 战斗 | 2:07 | 椎名豪《鬼杀队～霹雳一闪 六连》，《立志篇》原声，官方音源 |
| `shinobu_vs_doma` | 蝴蝶忍 vs 童磨 | 战斗 | 2:44 | 无限城篇第一章配乐 M11+M12+M17，B 站剪辑段 |

官方音源是从官方 Topic 频道（椎名豪）和 LiSA 官方音乐频道下载的 AAC 原始音轨，未经转码。`hakuji_okaeri` 和 `shinobu_vs_doma` 取自 UP 主“仲夏音乐馆”的 [BV14A8G69EdQ](https://www.bilibili.com/video/BV14A8G69EdQ) 完整音轨，用 `ffmpeg -c copy` 按页面时间点无损截取（分别为 1176–1286 s 和 0–164 s）。M 编号依据声谱比对，对应官方发行的《劇場版「鬼滅の刃」無限城編 第一章 猗窩座再来 劇伴音楽集：フィルムスコアリング版 STEREO MIX》。多个编号表示该段拼接了几首配乐的片段。

每首的官方曲名、作者、专辑、链接、截取区间和 SHA-256 见 [sources.json](sources.json)。

## 重建游戏音频

```powershell
# 统一到 -16 LUFS（真峰值不超过 -1.5 dBTP），编码为 Vorbis q5，写入 art/music/，并把时长写回 library.json
.venv\Scripts\python.exe -X utf8 tools/build_music.py
# 首次生成新文件后，让 Godot 导入（生成 .import）
& $godot --headless --path . --import
```

挑选入场点、循环点和高潮点时可以用：

```powershell
.venv\Scripts\python.exe -X utf8 tools/build_music.py --profile rengoku_kyojuro        # 每 2 秒的响度曲线
.venv\Scripts\python.exe -X utf8 tools/build_music.py --suggest-loops rengoku_kyojuro  # 推荐接缝
.venv\Scripts\python.exe -X utf8 tools/build_music.py --preview rengoku_kyojuro        # 渲染循环接缝和高潮跳段的试听 WAV
```

## 整理记录

2026-10-19 从原先的 21 首 MP3 音乐库中选出游戏使用的 8 首，改为 ASCII 标识命名，其余 MP3、未使用的 M4A、B 站完整音轨、播放列表和整理资料已删除。
