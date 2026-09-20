"""Author the first combat roster as editable Godot resources; no runtime codegen."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
MOVES = ROOT / "moves" / "core"
CHARS = ROOT / "resources" / "characters"

class Raw(str):
    pass

def value(v):
    if isinstance(v, Raw):
        return str(v)
    if isinstance(v, bool):
        return str(v).lower()
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    return str(v)

def move_resource(data):
    path = MOVES / (data["id"] + ".tres")
    text = '[gd_resource type="Resource" script_class="DuelMove" load_steps=2 format=3]\n\n'
    text += '[ext_resource type="Script" path="res://scripts/move_data.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    text += "".join(f"{k} = {value(v)}\n" for k,v in data.items())
    path.write_text(text, encoding="utf-8")
    return "res://moves/core/" + path.name

def packed(items):
    return Raw("PackedStringArray(" + ", ".join(value(x) for x in items) + ")")

def make_roster():
    MOVES.mkdir(parents=True, exist_ok=True)
    CHARS.mkdir(parents=True, exist_ok=True)
    profiles = [
        dict(id="tanjiro", display_name="灶门炭治郎", epithet="心怀温柔，挥刀向前", element_name="水之呼吸",
             role="均衡 · 控距衔接", accent=Raw('Color(0.396, 0.796, 0.831, 1)'), walk_speed=2.15,
             specials=["水之呼吸·壹之型 水面斩", "水之呼吸·贰之型 水车", "水之呼吸·陆之型 扭转漩涡",
                       "水之呼吸·拾之型 生生流转", "火之神神乐·碧罗之天"],
             descriptions=["短程水刃；轻快重远", "上升迎击；对空保护", "回旋多段；近身衔接", "多段水龙斩 · 1格", "大圆弧斩 · 3格 MAX"]),
        dict(id="zenitsu", display_name="我妻善逸", epithet="雷鸣一瞬，意志不息", element_name="雷之呼吸",
             role="迅速 · 居合突进", accent=Raw('Color(0.941, 0.773, 0.471, 1)'), walk_speed=2.45,
             specials=["雷之呼吸·壹之型 霹雳一闪", "居合·上撩", "居合·回身斩",
                       "霹雳一闪·六连", "霹雳一闪·神速"],
             descriptions=["直线突进；重版更远", "快速对空（演绎技）", "撤步回斩（演绎技）", "六段突进 · 1格", "高速居合 · 3格 MAX"])
    ]
    for profile in profiles:
        cid = profile["id"]
        normal_refs, motion_refs, all_refs = {}, {}, []
        def add(key, data, collection):
            data["id"] = cid + "_" + key
            ref = len(all_refs) + 2
            all_refs.append((ref, move_resource(data)))
            collection[key] = ref
        for stance, prefix in [("stand","5"), ("crouch","2"), ("air","j")]:
            for button in "ABCD":
                light = button in "AB"
                body = button in "BD"
                clip = stance + ("_light" if light else "_heavy")
                dmg = {"A":45, "B":32, "C":80, "D":76}[button]
                startup = {"A":5, "B":4, "C":9, "D":10}[button]
                if stance == "crouch":
                    dmg -= 5
                if stance == "air":
                    dmg = {"A":42, "B":35, "C":75, "D":70}[button]
                    startup += 1
                sweep = stance == "crouch" and button == "D"
                reach = {"A":46, "B":37, "C":65, "D":52}[button]
                if cid == "zenitsu":
                    reach -= 2
                data = dict(display_name=("空中" if stance == "air" else ("下段" if stance == "crouch" else "")) +
                                {"A":"轻斩","B":"轻体术","C":"重斩","D":"重体术"}[button],
                            kind="light" if light else "heavy", level="high" if stance == "air" else ("low" if stance == "crouch" and button != "C" else "mid"),
                            startup=12 if sweep else startup, active=4 if not light else 3,
                            recovery=24 if sweep else (11 if light else 18), damage=85 if sweep else dmg,
                            hitstun=25 if light else 30, blockstun=11 if light else 15, hitstop=4 if light else 6,
                            push=0.55 if light else 0.9, stance=stance, animation_id=clip,
                            effect_id="body" if body else clip, knockdown=sweep,
                            box=Raw(f"Rect2(7, {-27 if stance == 'crouch' else -52}, {reach}, {26 if stance == 'crouch' else 37})"),
                            cancel_targets=packed([] if stance == "air" or sweep else
                                (["light","heavy","skill","super","max"] if light else ["skill","super","max"])))
                if stance == "air":
                    data["box"] = Raw(f"Rect2(7, -46, {reach}, 54)")
                add(prefix + button, data, normal_refs)
        for i,motion in enumerate(["236","623","214"]):
            for button in ("AC" if motion != "214" else "BD"):
                heavy = button in "CD"
                is_water = cid == "tanjiro"
                damage = ([105, 110, 100] if is_water else [105, 100, 95])[i] + (25 if heavy else 0)
                data = dict(display_name=profile["specials"][i] + ("·重" if heavy else "·轻"),
                            kind="skill", startup=([10,7,11][i] + (4 if heavy else 0)),
                            active=[3,9,14][i], recovery=[24,29,25][i]+(5 if heavy else 0),
                            damage=damage, hitstun=34, blockstun=16, hitstop=6,
                            push=0.6, box=Raw("Rect2(5, -55, 76, 49)"),
                            cancel_targets=packed(["super","max"]), cancel_window=26,
                            animation_id=(["water_slash","water_wheel","water_wheel"] if is_water else ["thunder","iai","iai"])[i])
                if i == 0:
                    if is_water:
                        data.update(projectile_speed=5.0 if heavy else 4.2, projectile_lifetime=48 if heavy else 36,
                                    box=Raw("Rect2(8, -48, 65, 32)"))
                    else:
                        data.update(travel=7.5 if heavy else 6.0, active=12 if heavy else 9)
                elif i == 1:
                    data.update(lift=-3.4, travel=1.0, anti_air_until=12 if heavy else 9,
                                box=Raw("Rect2(2, -90, 59, 83)"))
                else:
                    data.update(travel=1.6 if is_water else 2.6, startup_travel=0.0 if is_water else -0.8,
                                hit_frames=Raw(f"PackedInt32Array({data['startup']}, {data['startup']+7})"),
                                box=Raw("Rect2(-8, -55, 94, 49)"))
                add(motion + button, data, motion_refs)
        for kind, key, cost, damage, i in [("super","super",100,280,3),("max","max",300,445,4)]:
            water = cid == "tanjiro"
            count = (4 if water else 6) if kind == "super" else (1 if water else 3)
            startup = 8 if kind == "super" else 11
            data = dict(display_name=profile["specials"][i], kind=kind, startup=startup,
                        active=max(5,count*6), recovery=34 if kind=="super" else 42,
                        damage=damage, hitstun=35, blockstun=15, hitstop=4, push=0.35,
                        meter_cost=cost, freeze_frames=12 if kind=="super" else 18,
                        travel=2.5 if water else 4.2, knockdown=True,
                        hit_frames=Raw("PackedInt32Array("+", ".join(str(startup+n*6) for n in range(count))+")"),
                        animation_id=("water_wheel" if water else "thunder"),
                        effect_id=("flame" if water and kind=="max" else ("water_wheel" if water else "thunder")),
                        box=Raw("Rect2(-8, -82, 124, 77)"))
            add(key, data, motion_refs)
        throws = {}
        add("throw", dict(display_name="近身投",kind="throw",level="throw",startup=5,active=2,recovery=29,
                         damage=100,hitstun=34,blockstun=0,hitstop=7,push=4,
                         box=Raw("Rect2(0, -48, 44, 48)"),knockdown=True,animation_id="throw"), throws)
        text = f'[gd_resource type="Resource" script_class="CharacterDefinition" load_steps={len(all_refs)+2} format=3]\n\n'
        text += '[ext_resource type="Script" path="res://scripts/character_definition.gd" id="1"]\n'
        text += "".join(f'[ext_resource type="Resource" path="{path}" id="{ref}"]\n' for ref,path in all_refs)
        text += '\n[resource]\nscript = ExtResource("1")\n'
        text += "".join(f"{k} = {value(v)}\n" for k,v in profile.items() if k not in ["specials","descriptions"])
        text += f'visual_directory = "res://art/characters/{cid}/"\n'
        def refs(items):
            return "{\n" + ",\n".join(f'{value(key)}: ExtResource("{ref}")' for key,ref in items.items()) + "\n}"
        text += "normals = " + refs(normal_refs) + "\n"
        text += "motions = " + refs(motion_refs) + "\n"
        text += f'throw_move = ExtResource("{throws["throw"]}")\n'
        rows=[]
        for i,notation in enumerate(["236 + A/C","623 + A/C","214 + B/D","236236 + A/C","236236 + A+C"]):
            rows.append("{"+", ".join(f"{value(k)}: {value(v)}" for k,v in
                dict(input=notation,name=profile["specials"][i],description=profile["descriptions"][i]).items())+"}")
        text += "move_list = Array[Dictionary]([" + ",\n".join(rows) + "])\n"
        (CHARS / (cid+".tres")).write_text(text,encoding="utf-8")

if __name__ == "__main__":
    make_roster()
    print("Authored 42 combat moves and 2 character definitions.")
