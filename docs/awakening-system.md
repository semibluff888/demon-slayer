# 觉醒爆气

四人共用 B+C（P1 默认 I+J，P2 小键盘6+2，手柄 A+Y），耗2格。普通觉醒持续600逻辑帧（10秒），地面普通技命中后快速觉醒持续360帧（6秒）。双方停顿12帧后，普通发动有18帧可被攻击的起手；快速发动用6帧前进最多24世界单位，接触对方推挤框停止。

快速觉醒要求双方在地面，当前普通技已确认命中且处于取消窗口，不支持空挥、被防、扫倒、空中技、必杀、奥义、翻滚或受击状态。每套连招仅一次；只重新开放两次轻技、一次重技及普通技重复限制，保留实例编号、伤害递减、必杀和浮空追击上限。失败输入被消费，不回退普通技或在收招后意外发动。

|角色|伤害|受伤|行走/冲刺|其他|
|---|---:|---:|---:|---|
|炭治郎·全集中斑纹|115%|95%|110%/110%|斑纹、呼吸白雾|
|善逸·神速|108%|100%|120%/125%|闭目凝神、雷弧与短残影|
|祢豆子·鬼化爆血|120%|100%|105%/105%|普通技/必杀实际命中伤害的10%恢复，最多40生命|
|猗窝座·罗针|110%|85%|105%/105%|防御削血50%，防御时罗针增强|

攻击强化只作用于普通技和普通必杀，出招时锁定到实例，飞道具单独保存；减伤在接触时读取，覆盖奥义/MAX与投技。整招应用伤害倍率后一次取整，再按原规则拆分各段。削血单独计算，保持不致死；猗窝座的半削血向下取整。祢豆子恢复累计百分之一生命的余数，在双方同帧伤害全部结算后才执行，只对仍存活角色生效，额度只扣实际恢复量。

觉醒期间任何正常正回气均暂停，剩余气可放奥义。受击、倒地或投技不会解除；到期、KO、局末和练习重置解除。暂停、命中停顿和演出停顿冻结倒计时；投技正常消耗时长。不能重复发动或续时。练习提供2格、无限气和觉醒时间无限；仍需B+C发动，重置清除形态。

祢豆子使用独立鬼化图集，普通动作帧数、阶段与锚点保持一致。鬼化画面倍率为普通形态1.15倍，判定和技能距离不变。MAX共享鬼化外观，不叠加倍率；普通MAX结束还原，持续觉醒中的MAX结束保持形态直到觉醒到期。同角色镜像对战共享不可变图集，但各自独立选择形态。

## 数据与复现

CharacterDefinition.awakening 引用 AwakeningDefinition。运行中的时间、起手、恢复额度与快速觉醒次数保存在各自 DuelFighter，进入完整快照。输入入口仍为 Combat.step([{x,y,buttons},...])，BC掩码为6；内部指令为 awaken，事件为 awakening_start/end/warning/denied 和 heal。

    .venv/Scripts/python.exe tools/prepare_awakening_art.py
    .venv/Scripts/python.exe tools/run_roster_art.py --manifest output/imagegen/awakening-v1/jobs.json --group awakening --workers 3
    .venv/Scripts/python.exe tools/build_awakening_art.py
    .venv/Scripts/python.exe tools/subset_fonts.py
    ./tests/run_tests.ps1

生成需要明确授权使用 CPA；构建、字体和测试完全离线。队列不自动重试不确定请求。所有生图来源、提示词、参考图、请求记录及逐帧比例注册保存在 output/imagegen/awakening-v1/。逐帧对照在其 review/index.html。selected.json 固定最终采用的修正版，原始版本和修订提示词均保留。原生RGBA透明度直接保留；不透明青底图做色键分离，整个人物连通区域先提取后按序排列，避免空中/投技动作跨格裁切。动作画帧继承原招式时间轴，不通过加速动画改变战斗帧数。

专项测试使用真实方向与BC输入覆盖四人全部对阵、左右朝向、中场/版边及2格/3格路线，共128组，伤害结果记录在 artifacts/awakening-balance.json。帧率回归显式覆盖双方同时觉醒、受击、强化攻击与到期过程。

## 首版收益基线

下表固定炭治郎为未觉醒对手、中央相距34单位、使用相同 `5A → 5C → 236A` 起手。普通觉醒在起手前发动；快速觉醒在首个5C命中后发动并追加5A、5C；三格觉醒路线再接一格奥义，原三格路线接MAX。对手自首次命中后持续尝试防御，验证后续没有断连。数值是这些固定路线的实测伤害，不代表角色最优连段。

|角色|无消耗|一格奥义|两格普通觉醒|两格快速觉醒|三格普通觉醒＋奥义|三格快速觉醒＋奥义|原三格MAX|
|---|---:|---:|---:|---:|---:|---:|---:|
|炭治郎|139|321|159|220|341|402|428|
|善逸|139|321|150|211|332|393|428|
|祢豆子|139|321|166|227|348|409|428|
|猗窝座|139|321|152|213|334|395|428|

快速觉醒的两格/三格路线在收尾并再推进100帧后仍剩220～240帧强化时间；普通觉醒对应剩444～464帧。觉醒的价值还包含后续压制、移动、防守与祢豆子恢复，不能只按首套连段伤害判断平衡。完整原始数据及剩余气量见 `artifacts/awakening-balance.json` 的 `comparisons`；全对阵128条路线见 `routes`。

## v1 验收结果（2026-10-07）

现有完整回归套件通过，觉醒核心1400项、形态1768项通过；30/60/144 FPS状态哈希一致。最终32张实机流程截图及44项检查通过，覆盖960/1280/1920宽度、单边镜像觉醒、起手、跳跃、蹲身、受击、受投、暂停、到期和重置。全动作首中末帧图库也已检查；最终受投素材使用完整人物提取，避免跨格碎片。

导出Windows EXE通过84招资源一致性、64条原连招及全部四人的觉醒输入/耗气/时间/图集检查。试玩包：`dist/DemonSlayer-0.2.0-awakening-windows-x86_64.zip`，本地文件，不含生产参考图和提示词。

主要日志：`artifacts/awakening-final-regression.log`、`artifacts/awakening-core-final.log`、`artifacts/awakening-final-capture.log`；发布验证：`dist/DemonSlayer-0.2.0-awakening-windows-x86_64-smoke.log`。最终选用的117组图源与提示词在 `output/imagegen/awakening-v1/acceptance.json` 和 `selected.json` 中可追溯，四人觉醒图集共1424帧。


## 觉醒美术重制 v2

炭治郎、善逸、祢豆子使用新的统一模型参考和117组动作图源，包括祢豆子的MAX。生产目录为 `output/imagegen/awakening-v2/`：`pilots.json`记录造型稿，`jobs.json`记录动作，`effects.json`记录独立效果，`imports/`记录坐标、比例和源文件哈希。模型图作为身份参考，普通形态动作作为姿势参考；放大参考人物在单格中的占比，避免脸部细节在生图时丢失。猗窝座的资产通过 `preserved-akaza.json`逐文件核对。

构建新三人素材：

    .venv/Scripts/python.exe tools/build_awakening_art.py --source-dir output/imagegen/awakening-v2
    .venv/Scripts/python.exe tools/build_awakening_static.py
    .venv/Scripts/python.exe tools/review_awakening_v2.py

生成步骤使用已授权CPA；以上三个命令只读取本地素材。新图集保持原动作帧数、阶段与锚点。直立动作按高度标定，防止刀刃变长导致人物缩小；色键保留绿色衣料，仅去除亮青底与透明边缘的青色溢色。

新 `awakening_effects.gd` 在每个选手自己的节点中合成气焰、局部纹理、地面气流和发动爆发。独立动画时钟不因换动作重新起算，沿用角色的暂停和演出冻结状态；Shader 不使用引擎全局 TIME。猗窝座继续由原绘制逻辑显示罗针。HUD将名称、剩余时间、进度置于血条下的深色面板，并同步切换新版觉醒头像。


### v2 最终验收（2026-10-07）

最终接入117组重绘动作、926帧、3张头像和12张独立特效纹理。每位角色39组战斗及发动动作；回合入场、胜负演出沿用正常形态。人工检查逐帧源图后，修正祢豆子倒地/受投的额外手部、炭治郎受投的额外拳头，以及祢豆子投技/后跳残留竹筒和系带。最终选择记录于 `output/imagegen/awakening-v2/selected.json`，来源、提示词与最终图集哈希见 `acceptance.json`。猗窝座全部留存资产逐文件哈希一致。

完整回归通过：觉醒核心1400项、形态1768项、新表现30项；美术专项5项通过。30/60/144 FPS状态哈希一致。旧美术测试中的本地预览测试按原规则跳过；新版动作源图和实机图均另行检查。

最终实机44项检查无失败，输出552张截图（36张流程画面和516张全动作首/中/末帧），包含960×540、1280×720和1920×1080。三人的全部战斗动作代表帧均检查了游戏内尺寸和位置；镜像单边觉醒、蹲防、跳跃、受击、受投、暂停、到期和重置通过。`artifacts/awakening-v2/redesign-overview.jpg` 为三张真实游戏画面的裁切拼图。

验证日志：`artifacts/awakening-v2-final-regression.log`、`artifacts/awakening-v2-final-import.log`、`artifacts/awakening-v2-final-capture.log`。

Windows试玩包：`dist/DemonSlayer-0.2.1-awakening-art-windows-x86_64.zip`。最终导出EXE通过84招资源逐项一致性、64条真实输入连招以及资源/觉醒冒烟检查；ZIP完整性校验通过。首次全量导入遇到Godot原生异常，在同一暂存目录单次重新导入后完成导出与验证，未调整游戏代码。SHA-256：`44664d189c0c6dc30cbe966052d68e34505f8e4989c1dd5a8121427ef1c0459c`。

## 祢豆子外观修订 v6（2026-10-08）

以用户参考图衍生的最终模型重绘祢豆子39组战斗/发动动作、306帧，包含MAX。取消肩顶破洞，保留更明显的单角、藤纹、长发、战损羽织与不对称裙摆；待机双手自然下垂。胸前保持衣料遮盖。用户已明确授权修改后直接接入，无需再等待预览确认。

生产目录为 `output/imagegen/awakening-v6/`，`master.json`记录模型，`jobs.json`记录原动作时间轴与参考姿势，`selected.json`固定倒地第三帧多余手部的修正版。图集43组、348帧中，39组/306帧为新生成动作，另外4组/42帧为原有回合演出；游戏在回合结束时沿用既有解除形态规则。普通形态、其他角色与特效的保留哈希见 `preserved-runtime.json`。

新头像同时用于HUD觉醒状态和MAX发动特写，`awakened_combo.tres`以及对应资源生成器使用同一路径。猗窝座已确认的觉醒头像另行接入，来源与实机核对在 `output/imagegen/awakening-v3-preview/imports/akaza-portrait.json`。

离线重建：

    .venv/Scripts/python.exe tools/build_awakening_art.py --source-dir output/imagegen/awakening-v6 --character nezuko
    .venv/Scripts/python.exe tools/build_nezuko_awakening_static.py
    .venv/Scripts/python.exe tools/review_awakening_v2.py --source-dir output/imagegen/awakening-v6 --all-frames

完整回归通过（`artifacts/awakening-v6-regression.log`），觉醒核心1400项、形态1768项、表现30项，美术专项5项；30/60/144 FPS状态一致。实机检查36项通过，153张截图覆盖单边镜像觉醒、960/1280/1920宽度、起手、跳跃、蹲身、受击、受投、暂停、到期、重置，以及左右朝向的普通MAX/觉醒MAX特写与结束还原。见 `artifacts/awakening-v6/captures.json` 及五张 `runtime-gallery-*.jpg`。

本轮生图使用已授权CPA服务与安装的imagegen CLI。动作参考和模型作为实际附件传入；全部提示词、生成记录、源文件哈希、逐帧注册及最终验收摘要均留存在生产目录中。

本轮已完成接入与导出验证：Windows试玩包为 `dist/DemonSlayer-0.2.2-nezuko-awakening-windows-x86_64.zip`，SHA-256为 `6a36a62be651d9175358288a173c10685565ab1f21fd5225c9d58f49caa68e15`。发布版资源检查与64条真实输入连招通过，ZIP完整性通过。最终验收与来源汇总见 `output/imagegen/awakening-v6/acceptance.json`。

## 祢豆子动态比例修订 v7（2026-10-08）

以用户已认可的游戏内 v6 待机作为统一模型，6 帧待机逐像素保留；重制其余38组动态动作、300帧，包含移动、前后冲刺、跳跃、蹲身、普通攻击、技能、投技、防御、受击与 MAX。持续觉醒与未持续觉醒的 MAX 共用最终图集；头像和其他角色保留。

修复两类比例漂移：动态图源混入原普通形态的短肢、大头体态，以及按完整轮廓适配尺寸导致头发、踢腿、蹲身影响人体缩放。v7使用约59.5图集像素的头骨长度为共同标尺，沿头部轴线测量，排除角、松散头发和张嘴的下颌延伸；横向按腰带定位，底部保持原动作接触位置。人工标尺有约3个源像素的量测误差，因此同时检查同尺度全身对照和实机画面，不将数值相同当成造型完全一致的证明。12组地面动作及MAX、受投动作在初版审核后使用待机作为唯一造型图片附件再次重绘。

发力阶段增加张嘴、露牙和咬牙表情，移动、准备与收招按动作保持克制。画帧数、阶段和战斗时序不变；原1.15倍鬼化规则仍只应用一次。脚底锚点、普通形态以及其他角色资产由自动化检查验证。

生产目录 `output/imagegen/awakening-v7/` 保存实际参考附件、提示词、请求记录、最终选择和逐帧标定。`selected.json`固定12组地面修订，`anatomy-calibration.json`绑定源图SHA-256，防止替换源图后误用旧缩放。长动作由六帧以内的图表无缩放拼接；全部来源及受投等效帧替换见 `records/`。`review/fixed-ruler.html`提供同一尺度的完整动作对照。

离线重建：

    .venv/Scripts/python.exe tools/build_awakening_art.py --source-dir output/imagegen/awakening-v7 --character nezuko
    .venv/Scripts/python.exe tools/review_awakening_motion.py

最终完整回归通过，觉醒核心1400项、形态1768项、表现30项、美术专项8项；30/60/144 FPS状态哈希一致。现有本地预览测试按原规则跳过一次，新素材已另行完成源图和实机检查。实机专项48项通过，310张截图包含153张流程/图库画面及157张真实输入动作样本，验证左右朝向的普通MAX/持续MAX、单边镜像形态、暂停、到期和重置。运动展示使用已有练习无限觉醒选项。

验证日志：`artifacts/awakening-v7-regression.log`、`artifacts/awakening-v7-final-import.log`、`artifacts/awakening-v7-final-capture.log`。预览与实机记录位于 `artifacts/awakening-v7/`，最终文件哈希和发布信息见生产目录的 `acceptance.json`。

Windows试玩包：`dist/DemonSlayer-0.2.3-nezuko-motion-windows-x86_64.zip`。发布版通过84招资源逐项一致性、64条真实输入连招及ZIP完整性检查。SHA-256：`2c7cdc450603993287c421e11d7727a9353b336cc071a10e3ce7d040eefe1981`。


## 祢豆子移动与技能修订 v8（2026-10-08）

按用户反馈，本轮采用已认可的 v7 MAX 和静态待机作为实际图片附件，重绘前后行走、前后冲刺、四种空中攻击、爆血飞踢、升空踢、回旋踢及血鬼术·爆血，共12组90帧。其他31组258帧的画面、偏移和动作元数据完整保留，包括待机与 MAX。普通形态、其他角色与战斗逻辑未在本轮修改。

v7 行走不仅存在体态偏小，也继承了不稳定的横向基准：六帧腰部位置跨越约79图集像素，末段身高由356降到324。v8 将前后行走的腰部固定在 x=449，站立高度控制在354～357，脚底为 y=569；修正循环首尾的身体跳动，并将步态动画播放速度从12调整到20 FPS，配合原有世界移动速度。此调整只影响两组行走动画，攻击、技能、MAX时序保持原值。

冲刺和技能按 MAX 的头骨、躯干与腿长统一尺度。空中攻击固定腰部基准 (449,322)，保留姿态产生的高低变化；脚尖或发梢不会成为整个人物缩放的依据。明确的逐帧腰部坐标替代了服饰颜色启发式定位。三帧图源边缘的截脚风险使用本轮完整等效踢腿姿势替换，逐项保留来源和理由。

生产文件位于 `output/imagegen/awakening-v8/`：`selected.json`保存最终行走版本，`motion-calibration.json`保存逐帧标尺与源图 SHA-256，`imports/`保存最终偏移，`baseline/`保存完整 v7 基线，`acceptance.json`保存最终验证结果。人工头骨测量约有3个源像素误差，仍需结合相同像素尺度下的全身对照和实机画面判断。

离线重建使用 `.venv/Scripts/python.exe tools/build_nezuko_awakening_v8.py`，随后执行 Godot 导入与 `tests/run_tests.ps1`。最终导入不得带 `--partial`。美术11项专项验证素材来源、循环定位、身高稳定性与258帧保留内容；完整回归通过，30/60/144 FPS状态一致。实机脚本追加左右朝向各四个完整步态循环、四种空中攻击及全部技能，并保持普通MAX/持续觉醒MAX、暂停、到期和重置检查。

最终实机92项检查全部通过，输出931张截图，其中778张为真实输入动作样本。左右朝向的前后行走各覆盖四轮循环；结合角色世界坐标和最终绘图腰部位置计算，所有采样（含首尾接缝）均沿输入方向持续移动。采集窗口曾暂时停止出帧后自行恢复，原流程最终完成，无需替换或合成缺失画面。详见 `artifacts/awakening-v8/captures.json` 和 `walk-registration-check.json`。最终视频与对照图为真实游戏截图拼接。


## 祢豆子细节修订 v9（2026-10-09）

前后行走从20 FPS恢复12 FPS，保留全部已认可行走画帧。站立重攻击中间帧横向收窄4%；升空踢中间帧补正3%～9%；重攻击、升空踢和飞踢首尾直接复用静态待机，消除完全收招时的尺寸跳变。飞踢第2/7帧复用MAX弓步、第4帧复用MAX发力姿势并对齐腰部，修正夸张腿长。蹲防使用一次CPA局部编辑，仅合成双拳与前臂区域，保留其余造型。

正面投技保留动作并逐帧补正5.5%～12%，修正原第3帧横向偏移，首尾复用待机。反向投技前四帧复用正面抓取，第4/5帧保留转身过渡，第6～11帧使用修正后正面动作的镜像。投技期间渲染朝向固定，因此镜像写入反投画帧；围绕实际脚底锚点翻转，末帧恰好接入结束后朝向落地对手的待机。

本轮改动54帧，294帧像素保留；MAX、战斗判定及动作时序保持原样。生产与离线重建见 `output/imagegen/awakening-v9/README.md`、`corrections.json` 和 `tools/build_nezuko_awakening_v9.py`。按用户要求只做素材及资源校验、场景加载与打包必要检查，未执行实机画面验收、录像或完整战斗回归。
