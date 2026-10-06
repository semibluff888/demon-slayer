# 宿命对决：角色表现、庭院与主海报

游戏名称已改为 **《鬼灭之刃：宿命对决》**。本次交付见[实机截图与录像](../artifacts/fate-revisions/index.html)。

## 角色体型与受击

- 祢豆子的角色资源设置 `model_scale = 0.85`，全身、所有动作、奥义残影及左右朝向共用该倍率，脚底锚点保持一致。图集内部的逐帧比例校准仍然有效，加载／释放图集不会累乘倍率。
- 当前待机图像的实际显示高度约为祢豆子 62.3、炭治郎 67.1、善逸 67.5、猗窝座 75.4 世界单位。相机仍是固定 3 倍；祢豆子比炭治郎约矮 7%，比原先自身缩小 15%。
- 两位新角色的旧受击序列第 0 帧接近站姿，第 4、5 帧已回到恢复动作。连续命中与停顿会反复重播第 0 帧，导致看起来像待机。
- 现在每次受击从明显疼痛的第 2 帧开始，再播放第 1、3 帧，硬直未结束时保持最后的疼痛姿态。再次命中会重新表现冲击，停顿冻结当前姿态，脱离硬直后才恢复正常状态。
- 受击角色会绘制在大面积特效的实色层前方，保留上方的辉光和火花，防止表情被完全遮住；硬直结束后恢复原层级。
- 招式伤害、命中框、受击框、移动规则、取消规则和计时没有变更。

## 爆血方向

原爆血贴图的亮焰主体位于左侧。祢豆子的五组技能资源现在明确设置纹理水平翻转，让亮焰主体位于角色的局部前方；角色整体朝向只再镜像一次。普通透明主体和叠加光效共用 UV 变换，避免两层方向不一致。

飞踢朝前延伸，升空踢向前上方扬起，回旋踢沿腿部扫动；奥义与 MAX 的旋转幅度分别配置。左右两侧的三组轻重必杀、奥义和 MAX 均有实机截图。

## 新地图与海报

- 新增稳定地图 ID `corps_courtyard`，名称 **鬼杀队庭院**，共四张地图。明亮的晨间宅邸、木廊、庭园和开阔砂石地面与三张旧场景区分。
- 沿用 960 世界单位宽度、594 屏幕地面高度与现有镜头规则；中央与左右卷动位置均已检查。四张地图卡自动适配宽度；再战与练习重置继续保留当前地图。
- 登录页使用一张完整海报，炭治郎领衔的鬼杀队与猗窝座、无惨对峙。游戏名称已绘入海报，移除了原界面叠加的标题与英文副标题，模式、指南和声音按钮仍是 Godot 原生控件。

| 资产 | 游戏文件 | 提示词 |
| --- | --- | --- |
| 标题海报 | [title-poster.png](../art/ui/title-poster.png) | [海报提示词](../output/imagegen/fate-v1/prompts/title-poster.txt) |
| 鬼杀队庭院 | [panorama.png](../art/stages/corps_courtyard/panorama.png) | [庭院提示词](../output/imagegen/fate-v1/prompts/corps-courtyard.txt) |

两项图片通过项目已有 **CPA API／CLI + gpt-image-2** 流程生成，采用 imagegen 的结构化提示词规范。提示词、原始 PNG、实际返回尺寸、SHA256、请求记录与裁切参数均保存在 [fate-v1](../output/imagegen/fate-v1/jobs.json)。接口实际返回海报 1672×941、庭院 2172×724；庭院裁切为 2172×543 的连续全景，拆成四块带 8 像素边缘扩展的纹理。保存原生像素，没有把插值放大伪记为生成分辨率。

## 离线重建与验证

```powershell
.\.venv\Scripts\python.exe -X utf8 tools/build_fate_art.py
.\.venv\Scripts\python.exe -X utf8 tools/subset_fonts.py
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --editor --import --quit
.\tests\run_tests.ps1
```

以上构建命令不会访问生图接口。只有显式执行 `tools/run_roster_art_job.ps1 -Manifest output/imagegen/fate-v1/jobs.json -Id <任务ID>` 才会调用 CPA；已有输出会直接退出，已登记的不确定请求也不会自动重试。

完整测试通过；新增行为检查 167 项，涵盖四种攻击角色对两位新角色、两个朝向的超必杀／MAX受击，角色比例与资源重载，三种模式的庭院选择、再战与练习重置。新增三项图像测试覆盖来源记录、无缝分块与字体覆盖；原有本地预览测试按原配置跳过一项。

960×540、1280×720、1920×1080、3840×2160 和 1600×1000 的菜单实机截图已保存。30／60／144 FPS 战斗状态哈希仍为 `b8f2dc800cffcd6029a38cc5195b0b7670d07d7aea3b796de29908b16f974cd0`。验收录像为静音、30 FPS；战斗逻辑仍为 60 Hz。

```powershell
& 'D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --script res://tools/capture_fate_revisions.gd
.\.venv\Scripts\python.exe -X utf8 tools/build_fate_review.py --encode
```
