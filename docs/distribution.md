# 发布与项目目录

## 给玩家分享

发送 GitHub Release 页面或 Windows ZIP 下载链接。玩家完整解压后运行 DemonSlayer.exe；无需 Godot。
发布工具只打包 art、moves、resources、scenes、scripts 和 project.godot；不会带入测试视频、美术生产记录、Python 环境或本机凭据。运行时通过 JSON 动态读取图集，export_presets.cfg 因此必须保留 `include_filter="*.json"`。场景的完整 panorama.png 是制作母图，发行包使用切片。

## 重新发布

1. 执行 tools/install-export-tools.ps1 准备官方 Godot 4.7.1 编辑器和 Windows x64 release 模板。已有编辑器可加 -SkipEditor，并设置 GODOT。下载按官方 SHA-512 验证，只保留需要的 Windows 模板，删除下载大包。
2. 执行 tools/build-release.ps1 -Version 0.1.0。版本号必须唯一；脚本拒绝覆盖已有 ZIP。成功后自动删除暂存项目及其缓存。
3. 将 dist 中的 ZIP 和 .sha256 上传至 GitHub Release，正文使用同目录 notes.md。发布使用的 Git 标签应指向构建时的源码提交。
4. 仓库另附只读权限的 GitHub Actions 工作流：手动填写版本号构建并上传 Actions 产物；Release 由仓库维护者手动创建。工作流中的引擎版本固定为 4.7.1，不具有发布权限。

## 目录职责

| 目录 | 用途 | 保留策略 |
| --- | --- | --- |
| art/、moves/、resources/、scenes/、scripts/ | 正式游戏资源和逻辑 | 保留；进入运行包 |
| tools/、tests/ | 美术生产、录制、打包与自动验证 | 保留；不进入运行包 |
| output/ | 生图源文件、提示词、来源记录、离线处理工具 | 保留制作来源；可清理指定缓存 |
| demo/ | 历史候选动作展示 | 保留；不进入运行包 |
| docs/ | 操作、制作和发布说明 | 保留 |
| artifacts/、tmp/ | 本地测试录像、截图、临时文件 | 可随时重新生成 |
| .godot/ | Godot 自动生成缓存 | 清理失效导入；完整删除后需要重新导入 |
| .venv/、.venv-imagegen/ | 本地美术开发环境 | 未打入发行包；本次保留供后续制作 |
| build/、dist/ | 导出工具、暂存文件、最终发行包 | Git 忽略，Godot 忽略 |
| .git/ | 版本历史 | 保留，不改写历史 |

clean-local.ps1 默认只报告；-Apply 才删除。它验证路径在本项目内、拒绝链接路径，并跳过所有 Git 跟踪文件。不要在录制或导入过程中运行清理。有效的 art/ 和 demo/ 导入缓存仍会保留。

历史说明中提及的 artifacts 截图/录像已清理，可通过 tools/capture_*.gd 和 tools/build_*_review.py 重新生成。制作源图及其 provenance 仍保留在 output/，避免丢失离线复现能力。

本次整理和验证结果见 [整理报告](cleanup-report.md)。
