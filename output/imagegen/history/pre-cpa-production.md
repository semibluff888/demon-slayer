# Pending imagegen production brief — no requests sent

Use the installed imagegen skill and built-in image_gen tool when available.
Generate each deliverable separately. Inspect it before using it as a reference
for the next asset. Save every actual prompt and returned original, and append
the real result metadata to manifest.json. Do not mark these prompts as outputs.

## Shared art direction

Premium hand-drawn 2D anime fighting game. Normal human proportions, 7 heads tall,
clean confident ink contours, controlled cel shading, fine face and costume detail.
Moonlit blue rim light from upper right; soft neutral key light preserves skin and
costume colors. No lettering, watermark, UI, emblems outside the costume, or camera
perspective changes. Side-view combat poses, facing right, readable silhouette,
full body and complete sword inside frame. Crisp at 240 pixels displayed height.

## Character designs (make and inspect these before motion or portraits)

Tanjiro Kamado: recognizable burgundy swept spiky hair, forehead scar, hanafuda
earrings, determined gentle face, green-and-black checkered haori over a layered
dark Demon Slayer uniform, white belt and leg wraps, accurate single katana grip.
Create consistent front, 3/4, side and back model views. Retain exactly this face,
hairstyle, costume pattern scale, sword, light direction and body proportions in
all subsequent images. Neutral pose, no special effects.

Zenitsu Agatsuma: recognizable golden yellow-to-orange choppy bob, amber eyes,
yellow-orange haori with small pale triangular pattern, dark Demon Slayer uniform,
white belt and wraps. Focused expression, low iaido guard and single katana.
Same art direction and proportions as the approved Tanjiro reference. Create front,
3/4, side and back model views. Check silhouette, fingers, blade and scabbard.

## Portraits

Use the approved character sheet as identity reference. One full-body polished
3/4 hero portrait with restrained dynamic haori and strong face detail. Transparent
background with clean alpha. Keep hair, feet, sword and scabbard entirely inside
image, generous margins. Each character separately. No text. Save accepted output
to art/characters/{character}/portrait.png; set portrait_focus from measured face.

## Animation groups, one consistent identity at a time

Use approved character design as strict reference. Uniform scale and camera for
every cell; no perspective drift, face redesign, costume changes or added swords.
Transparent background. Reference canvas 768×768 per frame, standing figure about
600 px high, ground-contact anchor (384,704). If source dimensions differ, record
actual crops and anchors, then use a SINGLE import scale. Never scale each pose to
its bounding box. Keep sword fully inside; enlarge the shared canvas if necessary.
Native Godot generates water/lightning/trails; do not bake them into body images.

Each motion group is a separate deliverable to inspect, not one overloaded sheet:

| Clip | Frames | Poses |
|---|---:|---|
| idle | 6 loop | balanced breathing; subtle coat movement; feet fixed |
| walk | 8 loop | approach with stable torso, clear alternating contacts |
| walk_back | 8 loop | controlled defensive retreat, guard retained |
| crouch | 3 | descend, settle, low ready pose |
| jump | 6 | takeoff, rise, apex, descend, landing, settle |
| guard / guard_low | 3 each | enter, contact brace, recover |
| hit | 4 | impact flinch, recoil, regain stance, settle |
| knockdown | 5 | loss of balance, fall, ground contact, settle, grounded |
| throw | 6 | reach, grasp, pivot, release, recover, ready |
| victory | 6 | sheathe, calm final stance, subtle cloth settling |
| stand_light / stand_heavy | 6 each | 2 windup, 2 slash, 2 recovery |
| crouch_light / crouch_heavy | 6 each | 2 windup, 2 low slash, 2 recovery |
| air_light / air_heavy | 6 each | 2 windup, 2 air slash, 2 recovery |
| water_slash / water_wheel | 9 each | 3 windup, 3 active, 3 recovery; Tanjiro only |
| iai / thunder | 9 each | 3 windup, 3 active, 3 recovery; Zenitsu only |

Startup/active/recovery boundaries go into phase_breaks. Idle/walk/walk_back loop;
guard holds final frame. Place normal attack sword reach to match the actual move
boxes in moves/*.tres. Check chronological contact sheets and animated playback.

## Moonlit wisteria courtyard — five registered layers, 2048×1152

Painted Japanese garden at night, pale round moon in upper right, distant mountains,
modest wooden temple with warm shoji windows, hanging violet wisteria framing upper
corners, stone lanterns at far sides, worn horizontal stone fighting terrace.
Sophisticated violet/navy atmosphere, warm amber accents, detailed painterly brushwork.
Keep the center 65% clear, low contrast behind fighters, no human figures or text.
Shared composition: floor contact at approximately y=916 of 1152; runtime overscan
maps it to y=594 of 720. No perspective vanishing lines that make the ground tilt.

First approve full composition reference. Then derive aligned layers using it:

1. sky.png: opaque night sky, moon, distant mountains only.
2. temple.png: midground temple, garden, lantern structures; transparent surroundings.
3. wisteria.png: hanging branches and violet blooms in upper corners; transparent center.
4. floor.png: stone ground from contact horizon downward; transparent upper portion.
5. foreground.png: sparse edge grasses and blossoms below feet, transparent center.

Use transparent output directly; preserve alpha. Only if a returned source uses a
solid matte, specify that exact matte_rgb in the offline import spec. Inspect edges
against dark AND light backdrops. Do not assume a checkerboard is real transparency.
