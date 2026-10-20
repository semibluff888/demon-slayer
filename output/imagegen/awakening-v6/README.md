# 祢豆子鬼化头像（v6 留存）

v6 原本是祢豆子鬼化外观的第 6 版（39 组动作、306 帧和独立觉醒头像）。动作帧后来被 v7～v9 取代，现行图集来自 `../awakening-v9/`，其 `baseline/` 存有完整的早期图集。2026-10-20 清理时只留下仍在游戏中使用的觉醒头像来源：

- `raw/nezuko-portrait.png`：生成原图，对应 `art/characters/nezuko/awakening/portrait.png`（HUD 觉醒头像、MAX 头像特写）。
- `static.json`、`prompts/`、`records/`、`authorization.json`：任务、提示词、生图记录和接入授权。
- `imports/nezuko-static.json`：缩放方式和源图 / 成品的 SHA-256。

离线重建头像：

    .venv/Scripts/python.exe tools/build_nezuko_awakening_static.py

v6 的动作源图、对照基线和验收记录可在 Git 历史中找回，见 `docs/cleanup-2026-10-20.md`。
