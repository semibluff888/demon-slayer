"""Build the local battle UI review, comparisons, and optional input-driven videos."""
import argparse
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artifacts/battle-ui"
TITLES = [
    ("tanjiro", "236236A", "生生流转", "tanjiro-super"),
    ("tanjiro", "236236AC", "碧罗之天", "tanjiro-max"),
    ("zenitsu", "236236A", "霹雳一闪·六连", "zenitsu-super"),
    ("zenitsu", "236236AC", "霹雳一闪·神速", "zenitsu-max"),
]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def run(args):
    subprocess.run(args, cwd=ROOT, check=True,
                   creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0)


def encode(ffmpeg):
    cue = read(ART / "video/cues.json")
    run([sys.executable, str(ROOT / "tools/mix_phase2_audio.py"), "battle-ui", "--folder", str(ART / "video")])
    run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(cue["fps"]),
         "-i", str(ART / "video/frame-%05d.jpg"), "-i", str(ART / "video/soundtrack.wav"),
         "-frames:v", str(cue["frames"]), "-c:v", "libx264", "-preset", "medium", "-crf", "19",
         "-threads", "4", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
         "-shortest", "-movflags", "+faststart", str(ART / "preview.mp4")])
    for character, move, _, name in TITLES:
        item = next(c for c in cue["cues"] if c["character"] == character and c["move"] == move)
        run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
             "-ss", str(item["start_frame"] / cue["fps"]), "-i", str(ART / "preview.mp4"),
             "-t", str((item["end_frame"] - item["start_frame"]) / cue["fps"]),
             "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-threads", "4",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", str(ART / (name + ".mp4"))])


def thumbnail(source):
    target = ART / "thumbnails" / (source.stem + ".jpg")
    target.parent.mkdir(exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((960, 600), Image.Resampling.LANCZOS)
        image.save(target, quality=88)
    return target.relative_to(ART).as_posix()


def comparison():
    before = ROOT / "artifacts/battle-v5/matrix/1280-tanjiro-idle-right-0-idle.png"
    after = ART / "matrix/1280-tanjiro-idle-right-0-idle.png"
    if not before.is_file():
        return False
    output = Image.new("RGB", (1600, 484), "#101923")
    draw = ImageDraw.Draw(output)
    font = ImageFont.truetype(str(ROOT / "art/fonts/NotoSansSC-ui.ttf"), 18)
    for column, (source, label) in enumerate([(before, "BEFORE"), (after, "AFTER")]):
        with Image.open(source) as image:
            output.paste(image.convert("RGB").resize((800, 450), Image.Resampling.LANCZOS), (column * 800, 34))
        draw.text((column * 800 + 16, 6), label, font=font, fill="#d8c397")
    output.save(ART / "before-after.jpg", quality=94)
    return True


def acceptance():
    reports = []
    log_names = ["input_tests", "combat_tests", "damage_tests", "movement_tests", "combo_practice_tests",
                 "ui_tests", "ui_tests-rendered", "presentation_tests", "phase2_basics_tests",
                 "phase2_feedback_tests", "battle_visual_tests"]
    for name in log_names:
        text = (ROOT / "artifacts" / (name + ".log")).read_text(encoding="utf-8-sig")
        matches = re.findall(r"([A-Z /]+): (\d+) passed, (\d+) failed", text)
        if not matches or re.search(r"SCRIPT ERROR|ERROR:|FAIL:", text):
            raise ValueError(f"Unsuccessful validation log: {name}")
        label, passed, failed = matches[-1]
        if int(failed):
            raise ValueError(f"{name}: {failed} failures")
        reports.append(dict(suite=label.strip(), passed=int(passed), failed=0))
    hashes = []
    for fps in (30, 60, 144):
        text = (ROOT / "artifacts" / f"fps-{fps}.log").read_text(encoding="utf-8-sig")
        hashes.append(re.search(r"hash=([a-f0-9]{64})", text).group(1))
    assert len(set(hashes)) == 1
    matrix = read(ART / "matrix/captures.json")["captures"]
    hud = read(ART / "hud/captures.json")["captures"]
    for item in matrix + hud:
        image_path = ROOT / (item["path"][6:] if item["path"].startswith("res://") else item["path"])
        with Image.open(image_path) as image:
            assert list(image.size) == item["size"], image_path
    core_paths = ["scripts/combat.gd", "scripts/fighter_state.gd", "scripts/command_recognizer.gd",
                  "scripts/input_router.gd", "moves/core", "resources/characters"]
    unchanged = subprocess.check_output(["git", "diff", "HEAD", "--", *core_paths], cwd=ROOT)
    assert not unchanged, "Gameplay data or rules changed"
    result = dict(suites=reports, deterministic_hash=hashes[0], fps=[30, 60, 144],
                  combat_rules_unchanged=True, rendered_matrix=len(matrix), hud_fixtures=len(hud),
                  sizes=sorted({tuple(c["size"]) for c in matrix + hud}),
                  controller_validation="Native UI events from a simulated gamepad; no physical controller connected.")
    (ART / "acceptance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def gallery():
    report = acceptance()
    has_before = comparison()
    video_cards = []
    for character, move, title, name in TITLES:
        poster = thumbnail(ART / "matrix" / f"1280-{character}-{move}-right-0-charge.png")
        video_cards.append(f'<figure><video controls preload="metadata" poster="{poster}" src="{name}.mp4"></video><figcaption>{html.escape(title)}</figcaption></figure>')
    samples = [
        ("matrix/1280-tanjiro-idle-right-0-idle.png", "1280 × 720 · 常驻 HUD"),
        ("matrix/960-tanjiro-236236A-left--1-charge.png", "960 × 540 · 同角色与左版边"),
        ("matrix/3840-tanjiro-both-right-0-charge.png", "4K · 双方同时释放 MAX"),
        ("matrix/1600-tanjiro-idle-right-0-idle.png", "16:10 · 保持比例与留边"),
        ("hud/1280-combos.png", "多位连击数字与伤害"),
        ("hud/1280-meter-feedback.png", "气量不足与耗气反馈"),
        ("hud/1280-details.png", "无底板练习信息"),
        ("hud/1280-pause.png", "暂停菜单（首版）"),
        ("hud/1280-settings.png", "练习设置（首版）"),
        ("hud/1280-round-start.png", "无底板回合提示"),
    ]
    cards = []
    for name, title in samples:
        preview = thumbnail(ART / name)
        cards.append(f'<figure><a href="{name}"><img loading="lazy" src="{preview}" alt="{html.escape(title)}"></a><figcaption>{html.escape(title)}</figcaption></figure>')
    comparison_html = '<h2>调整前后</h2><a href="before-after.jpg"><img class="comparison" src="before-after.jpg" alt="Before / After"></a>' if has_before else ""
    body = f"""<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>月下对决 · 战斗 UI</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#101923;color:#f6f2e8;font:16px/1.8 "Microsoft YaHei",sans-serif}}main{{max-width:1280px;margin:auto;padding:48px 28px}}h1{{font-size:34px;margin:8px 0}}h2{{font-size:23px;margin-top:44px}}p{{color:#becbd5;max-width:950px}}a{{color:#d8c397}}.eyebrow{{color:#d8c397;font-size:12px;letter-spacing:3px}}.grid{{display:grid;grid-template-columns:1fr 1fr;gap:24px}}figure{{margin:0}}img,video{{display:block;width:100%;height:auto}}figcaption{{padding:10px 0;color:#becbd5;font-size:14px}}.comparison{{width:100%}}.note{{border-top:1px solid #3c4754;margin-top:40px;padding-top:20px}}@media(max-width:760px){{.grid{{grid-template-columns:1fr}}main{{padding:24px 16px}}}}
</style><main>
<div class="eyebrow">MOONLIT DUEL / BATTLE UI</div><h1>刀锋之间，留出战场。</h1>
<p>小型头像、细长生命条、三段呼吸槽与悬浮连击。四种奥义采用用户提供的透明书法图，本页保存首版画面；后续菜单、人物比例和 MAX 修正请查看<a href="../battle-revisions/index.html">最新预览</a>。下方图片均来自实际 Godot 渲染。</p>
{comparison_html}
<h2>四种奥义</h2><p>实际输入驱动，每段 2.5 秒，包含原有逻辑事件音效。<a href="preview.mp4">完整预览</a></p>
<div class="grid">{''.join(video_cards)}</div>
<h2>布局与状态</h2><div class="grid">{''.join(cards)}</div>
<p class="note">{report["rendered_matrix"]} 张战斗矩阵截图，{report["hud_fixtures"]} 张 HUD／菜单状态截图；覆盖 960×540 至 3840×2160 及 16:10 留边。回归检查通过，30／60／144 FPS 的战斗状态摘要一致。手柄菜单使用模拟输入验证。<a href="acceptance.json">验证记录</a></p>
</main></html>"""
    (ART / "index.html").write_text(body, encoding="utf-8")
    print(f"Review ready: {ART / 'index.html'} ({len(samples)} selected frames)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--encode", action="store_true")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()
    if args.encode:
        if not args.ffmpeg:
            parser.error("ffmpeg is required for --encode")
        encode(args.ffmpeg)
    gallery()
