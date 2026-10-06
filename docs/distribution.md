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

## v0.1.2 连招导出回归

Godot 4.7.1 将文本资源转换为二进制时，本项目的 `DuelMove.cancel_targets` 导出后变为空数组。相同输入在源码通过，导出的 PCK 即使用开发引擎加载也无法取消。`project.godot` 明确关闭 `editor/export/convert_text_resources_to_binary`，使发布版加载原始招式资源。

`tools/build-release.ps1` 在导出前从源码生成 `resources/combat-manifest.json`（仅存在于暂存目录和成品 PCK），记录全部招式的可序列化脚本属性。发布 EXE 的 `--headless -- --verify-release` 对比属性，并运行四角色 × 双朝向 × 中场/版边 × 四路线，共 64 组真实输入验证：普通技连打、必杀取消、回旋接 MAX、升龙接 MAX。首击后持续防御用来识别断连，同时核对招式顺序、血量、HUD 和耗气。验证未通过时不生成 ZIP。

`tests/release_combat_tests.gd` 使用同一验证器提供开发版基线。该验证是引擎内逐帧输入回放，不等同于实体键盘或手柄手感验收。

## 自行提交与发布（PowerShell）

以下以**下一版 0.1.3** 为例，每次发布请使用新的版本号。

1. 在项目目录修改游戏及 `docs/RELEASE-NOTES.md`，写明本版变化。
2. 检查改动，运行测试，再构建对应版本；某一步报错就先修复，不继续发布。

```powershell
cd J:\Project\demon-slayer
git status
git diff
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File tools/build-release.ps1 -Version 0.1.3
```

打包脚本会用实际导出的 EXE 检查资源与连招。成功后，`dist/` 包含 ZIP、SHA-256、发行说明和验证日志。版本号重复时脚本会拒绝覆盖现有 ZIP。

3. 确认 `git status` 中都是本次需要提交的源码，然后提交并推送：

```powershell
git add README.md docs moves project.godot scripts tests tools
git diff --cached --stat
git commit -m "fix: 简述这次修改"
git push origin main
```

若还修改了其他目录（例如 `art/` 或 `resources/`），在 `git add` 后面加上对应路径。`dist/`、`build/` 已被 Git 忽略，游戏 ZIP 作为 Release 附件上传。

4. 为刚才构建并提交的版本打标签。打包后若又修改游戏代码或资源，需要重新测试、构建，保证包和标签一致。

```powershell
git tag -a v0.1.3 -m "Release v0.1.3"
git push origin v0.1.3
```

5. 打开 https://github.com/semibluff888/demon-slayer/releases/new ，选择已有的 `v0.1.3` 标签，标题填写版本名；将 `dist/DemonSlayer-0.1.3-windows-x86_64-notes.md` 的内容粘贴为说明，上传以下两个文件，然后点击 **Publish release**：

- `dist/DemonSlayer-0.1.3-windows-x86_64.zip`
- `dist/DemonSlayer-0.1.3-windows-x86_64.sha256`

分享 https://github.com/semibluff888/demon-slayer/releases/latest 即可让玩家找到最新版。玩家应下载 Windows ZIP，完整解压后运行 EXE；GitHub 自动附带的 Source code 是源码。

如安装了 GitHub CLI，也可用以下命令代替网页步骤（首次运行先 `gh auth login`）：

```powershell
gh release create v0.1.3 --verify-tag --title "宿命对决 v0.1.3" --notes-file dist/DemonSlayer-0.1.3-windows-x86_64-notes.md dist/DemonSlayer-0.1.3-windows-x86_64.zip dist/DemonSlayer-0.1.3-windows-x86_64.sha256
```
