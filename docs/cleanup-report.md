# 2026-10-06 整理与发行验证

- 清理 50,281 个未跟踪生成文件，释放约 20.52 GiB。主要为测试截图/录像及其失效的 Godot 导入副本；同时移除下载缓存和可再生成预览。
- 项目总大小约从 23.76 GiB 降为 3.63 GiB，后者包含新生成的 291 MiB Windows ZIP 和可复用导出模板。
- 正式游戏素材、源图、提示词、来源记录、历史候选 demo、开发环境及 Git 历史均保留。
- artifacts/ 和 tmp/ 的 .gdignore 已纳入版本控制；build/ 和 dist/ 由打包工具创建 .gdignore，避免引擎扫描生成产物。
- 重写玩家入口 README，原操作和开发记录移至 game-guide.md；新增发布、清理、玩家操作和第三方许可说明。
- launch.cmd 和测试入口不再硬编码本机引擎路径；支持 GODOT、PATH 和 build/engine。本机已有路径仅记录在被忽略的 .godot/engine-path.txt。

## 验证

- 隔离项目导入及 Windows release 导出成功；JSON 动态图集明确纳入 PCK。
- 使用发行版 DemonSlayer.exe 自检四名角色的所有图集帧、四张地图、字体和主菜单：0 failed。
- 最终 ZIP 解压至含中文及空格的新目录，资源自检和实际 OpenGL 图形启动均退出 0，无错误。
- 所有现有 Godot 逻辑、菜单、演出测试通过；30 / 60 / 144 FPS 的战斗结果哈希一致。
- 四组 Python 美术验证通过；仅可选本地预览检查按原设计跳过。
- 修复一条过时的美术断言：善逸后投倒地在 2026-10-06 已按标定缩小至 0.9 倍，旧测试仍要求大于 1。更新为各角色已确认的精确倍率，保持贴地及有效缩放验证，不更改游戏素材。
- PowerShell 语法、git diff --check、ZIP 内容和 SHA-256 校验通过。

生成文件位于 dist/。GitHub 构建工作流仅具有 contents:read 权限，手动运行并提供 Actions 产物；不会自动创建或发布 Release。
