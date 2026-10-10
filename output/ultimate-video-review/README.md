# 四角色必杀动画预览

打开 `preview.html` 可逐段播放；单独 MP4 在 `clips/`，完整原视频在本地 `source/original.mp4`（约 462 MiB，超过 GitHub 单文件限制，不纳入 Git；新检出时可从下方来源重新获取，来源信息和切割点仍随仓库保存）。

- 来源：[用户提供的无 HUD 合集](https://www.youtube.com/watch?v=-cnMjZ1v4fU)
- 原视频：1920×1080、60FPS、约 11 分 27 秒；保留完整下载文件。
- 片段：H.264 / AAC、1080p60；逐帧精确重编码（CRF 17），无放大、无补帧、无裁画。
- 从命中瞬间起保留完整演出和短收尾，去掉发动前等待、对手起身和站立等待；音频首尾仅做 10ms / 40ms 淡入淡出以避免爆音。
- 画面检查未发现血条、HUD、广告叠层；原作场景、对手和原声仍在。
- 当前只下载、切割并提供预览，未修改游戏逻辑或接入视频。目录带 `.gdignore`。

| 视频 | 时长 | 原视频秒数 | 与当前游戏的关系 |
|---|---:|---|---|
| [炭治郎｜水之呼吸奥义](clips/01_tanjiro_water.mp4) | 12.00s | 2.40–14.40s | 生生流转：水系奥义候选，源视频未显示技能名 |
| [炭治郎｜火之神神乐奥义](clips/02_tanjiro_hinokami.mp4) | 13.30s | 36.40–49.70s | 碧罗之天：火系奥义候选，源视频未显示技能名 |
| [炭治郎｜游郭篇·水火连斩](clips/03_tanjiro_district.mp4) | 12.20s | 55.10–67.30s | 额外备选：水火组合演出，非已确认的碧罗之天 |
| [祢豆子｜爆血奥义](clips/04_nezuko_blood.mp4) | 15.15s | 91.55–106.70s | 血鬼术·爆血：爆血演出 |
| [祢豆子｜觉醒爆血连击](clips/05_nezuko_awakened.mp4) | 13.70s | 111.40–125.10s | 爆血·觉醒连击：觉醒形态候选演出 |
| [善逸｜霹雳一闪·六连](clips/06_zenitsu_sixfold.mp4) | 12.60s | 206.10–218.70s | 霹雳一闪·六连：普通版奥义候选 |
| [善逸｜霹雳一闪·神速](clips/07_zenitsu_godspeed.mp4) | 13.10s | 223.40–236.50s | 霹雳一闪·神速：游郭篇奥义候选 |
| [猗窝座｜罗针·破坏杀奥义](clips/08_akaza_ultimate.mp4) | 17.10s | 526.40–543.50s | 破坏杀·灭式：候选演出；此源中未找到青银乱残光 |

## 对应关系

原视频无技能字幕，文件名是便于预览的动作描述，非对所有官方招式名的认证。炭治郎额外提供游郭篇水火连斩作为备选。猗窝座仅发现一段普通形态奥义，包含罗针和冲击连击，未找到能确认是“终式·青银乱残光”的片段，未用别的招式冒充。

## 更高清候选（仅检索到，尚未验证画面是否无 HUD）

以下视频标题声称 4K / 60FPS，没有下载或替换本次源素材，可后续人工查看：

- [Every Demon Ultimate Arts & Surge Finisher (4K 60FPS) | Demon Slayer Hinokami Chronicles 2](https://www.youtube.com/watch?v=qQQBlBq-AwM)
- [ALL Infinity Castle Character Ultimates (Full DLC Pack) | Demon Slayer Hinokami chronicles2 4K 60FPS](https://www.youtube.com/watch?v=8hV0A42sZSw)
- [Demon Slayer The Hinokami Chronicles 2 - All Ultimate Arts 100% (4K60FPS) [ENG DUB]](https://www.youtube.com/watch?v=99rjzXyIqtA)

## 检查与复现

全部 8 个 MP4 已核验 1080p60、视频和音轨、持续时间，并通过全片解码检查。`manifest.json` 记录切割点；`review/` 内保留抽帧检查图和剪辑脚本。源文件最高分辨率即为 1080p，不是 4K。
