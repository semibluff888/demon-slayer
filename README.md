# 鬼灭之刃：宿命对决

Godot 4.7.1 制作的 2D 格斗游戏。当前有炭治郎、善逸、祢豆子、猗窝座四名可玩角色，以及四张地图，支持电脑对战、本地双人和自由练习。海报上的其他角色暂不可选。

## 下载即玩（Windows）

前往 **[GitHub Releases](https://github.com/semibluff888/demon-slayer/releases)**，下载 `DemonSlayer-<版本>-windows-x86_64.zip`，完整解压后双击 `DemonSlayer.exe`。保留同目录的 `DemonSlayer.pck`。

**玩家不需要安装 Godot、Python 或任何开发工具。** GitHub 自动生成的 `Source code` 是开发源码，不是游戏安装包。当前提供 Windows 10/11 x64 版本，显卡需支持 OpenGL 3.3；发行版未进行代码签名。

| 操作 | P1 | P2 |
| --- | --- | --- |
| 移动 | WASD | 方向键 |
| 轻攻击 / 轻体术 | U / I | 小键盘 5 / 6 |
| 重攻击 / 重体术 | J / K | 小键盘 2 / 3 |
| 菜单确认 / 返回 | U / I | 小键盘 5 / 6 |
| 暂停 | Esc | Esc |

新增 **B+C 觉醒爆气**（P1 I+J / P2 小键盘6+2）：消耗2格，普通发动10秒，普通技命中可快速觉醒接续连招。四人各有强化特性，祢豆子持续鬼化。详见[觉醒规则](docs/awakening-system.md)。

支持手柄和自定义按键。菜单及暂停页中的「帮助」「游戏设置」提供操作说明和调整入口。详见[完整招式与制作记录](docs/game-guide.md)。

设置中的 **必杀动画演出** 默认开启：奥义 / MAX 命中后播放视频，保留顶部 HUD 与连击，并在当前地图完成收尾。关闭可沿用简化演出。见[演出映射与剪辑说明](docs/cinematic-ultimates.md)。

## 开发与打包

开发需要 Godot **4.7.1 stable**。先设置环境变量 `GODOT` 为引擎可执行文件路径，然后双击 `launch.cmd`；也可在编辑器中导入 `project.godot`。`launch.cmd` 自动选择同目录的无控制台版 Godot，启动后不保留命令窗口；启动失败会弹窗说明原因。制作美术时才需要 Python 与 `requirements-art.txt`。

```powershell
# 首次准备：下载并校验官方编辑器和 Windows 导出模板
powershell -ExecutionPolicy Bypass -File tools/install-export-tools.ps1
# 自动找到 build/engine 中的引擎；也可传 -Godot 或设置 GODOT
powershell -ExecutionPolicy Bypass -File tools/build-release.ps1 -Version 0.1.2
# 测试
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1 -Godot '你的 Godot 可执行文件路径'
```

成品在 `dist/`：游戏 ZIP、SHA-256 校验文件、发行说明及验证日志。打包在独立暂存目录进行，仅包含游戏运行内容；JSON 图集清单会明确打包，并通过导出后的可执行程序验证角色与地图完整性、84 招属性一致性和 64 组真实输入连招。

[发布流程、目录职责与清理说明](docs/distribution.md) · [第三方许可](THIRD-PARTY-NOTICES.md)

## 本地清理

```powershell
# 先查看可清理体积，默认不删除
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1
# 删除测试录像、截图、临时文件及不再引用的导入缓存
powershell -ExecutionPolicy Bypass -File tools/clean-local.ps1 -Apply
```

清理脚本跳过 Git 跟踪文件，并保留正式素材、制作源文件和仍有效的导入缓存。`artifacts/` 中的历史实机证据属于可重新生成的本地产物，不包含在源码下载或发行包中。
