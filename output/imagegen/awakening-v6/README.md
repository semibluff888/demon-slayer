# 祢豆子鬼化外观修订：已授权直接接入

用户已明确要求：本轮修改完成后直接接入游戏，无需再次确认。

造型定稿：../awakening-v6-preview/raw/nezuko-idle-v6.png。取消肩顶撕裂，沿用下垂双手、单角、藤纹、长发、战损羽织及不对称裙摆；领口保留锁骨和上胸表现，胸前仍由衣料遮盖。

生产内容：39 组动作、306 帧及独立觉醒头像。持续觉醒和 MAX 共用这套图集，回合演出继续遵循游戏已有还原规则。

- jobs.json：动作任务、逐帧原姿势边界及原始时序。
- static.json：觉醒头像任务。
- master.json：定稿与哈希。
- authorization.json：直接接入授权范围。
- preserved-runtime.json：普通形态、其他角色和现有特效的接入前哈希。
- records/：已授权 CPA 服务的生图记录；调用安装的 imagegen CLI，gpt-image-2，high 质量。
- imports/：离线抠图、缩放、锚点和来源记录。
- review/：源图与逐帧对照。

离线重建：

    .venv/Scripts/python.exe tools/build_awakening_art.py --source-dir output/imagegen/awakening-v6 --character nezuko
    .venv/Scripts/python.exe tools/build_nezuko_awakening_static.py
    .venv/Scripts/python.exe tools/review_awakening_v2.py --source-dir output/imagegen/awakening-v6 --all-frames

最终接入和验证状态以 acceptance.json 为准；生成中的图源不能视作已经通过验收。

最终状态：已接入并验证。完整回归、30/60/144 FPS一致性、36项实机检查、发布版资源与64条连招检查、ZIP完整性均通过。汇总见 acceptance.json。
