# 回合动作预览

双击 **index.html** 查看 8 段带音效的实际引擎录像；双击 **launch.cmd** 打开独立 Godot demo。可通过角色、A–D 方案、开场/胜利/落败/完整流程切换，使用镜像、速度、暂停、重播及时间轴比较。

每段完整录像 12.7 秒：双方同时开场 → ROUND / READY / GO! → 短交手 → 当前角色获胜 → 当前角色落败。开场与胜利各 18 幅不同画帧，倒地 12 幅；共 24 段、384 幅。素材仅在此目录引用，正式游戏使用已有胜利与倒地动画。角色新动作是否接入正式游戏，等待方案选定。

| 角色 | A | B | C | D |
| --- | --- | --- | --- | --- |
| 炭治郎 | 礼仪 | 水息 | 火意 | 守护 |
| 善逸 | 惊怯 | 入静 | 雷鸣 | 梦醒 |

## 文件

- assets/：独立透明图集，沿用 1024×640 画布、[448,568] 接地点、340 像素站立标尺。
- raw/、prompts/、records/：24 张 CPA 原始动作图、实际提示词、来源与请求记录。模型 gpt-image-2；费用服务未提供，保留 null。
- calibration.json、imports/：各动画固定比例、逐帧裁切与接地记录。没有覆盖正式角色图集。
- review/：逐帧联系表、GIF 和引擎动作检查拼图。
- previews/：8 段 1280×720 / 30 FPS 视频、正式游戏演出视频，以及 144 张多分辨率/朝向截图。
- asset-report.json：帧数、实际源图尺寸与完整性报告。

## 离线重建

在项目根目录执行（不调用生图服务）：

```powershell
.\.venv\Scripts\python.exe demo/round-presentation/build.py
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --script res://demo/round-presentation/capture.gd
.\.venv\Scripts\python.exe demo/round-presentation/review.py --encode
```

本机编码器位置写在 review.py 的 FFMPEG 常量。重新生图是独立操作：prepare.py 生成提示词，generate.ps1 -Character tanjiro/zenitsu 使用既有 CPA 帮助脚本。已存在输出会跳过；不确定请求会停止，避免重复付费请求。

本地 HTTP 预览（可直接跳到视频章节）：

```powershell
.\.venv\Scripts\python.exe demo/round-presentation/serve.py
# http://127.0.0.1:8786/
```

验证：项目 tests/run_tests.ps1 包含正式回合回归；独立场景用 --headless --path . --script res://demo/round-presentation/verify.gd 检查素材、全部动作末帧、镜像、时间轴、暂停和选择控件。浏览器自动连接在本机因沙盒初始化失败而不可用；页面链接与媒体通过离线/HTTP 检查，Godot 交互及真实渲染已验证。
