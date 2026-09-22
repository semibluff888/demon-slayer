"""Author display-only move profiles. No attack geometry or balance lives here."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROFILES={
 'blade':('blade',(0.75,0.89,1.0,1),'swing',0),
 'body':('body',(0.90,0.83,0.67,1),'body_swing',0),
 'water_slash':('water_slash',(0.50,0.85,1.0,1),'water_slash',0),
 'water_wheel':('water_wheel',(0.46,0.84,1.0,1),'water_wheel',0),
 'water_vortex':('water_vortex',(0.40,0.90,0.89,1),'water_wheel',0),
 'water_dragon':('water_dragon',(0.38,0.83,1.0,1),'water_slash',1),
 'sun_arc':('sun_arc',(1.0,0.40,0.09,1),'flame',0),
 'thunder':('thunder',(1.0,0.87,0.46,1),'thunder',2),
 'iai':('iai',(1.0,0.86,0.57,1),'iai',0),
 'iai_return':('iai_return',(1.0,0.79,0.38,1),'iai',0),
 'sixfold':('sixfold',(1.0,0.88,0.46,1),'iai',2),
 'godspeed':('godspeed',(0.80,0.89,1.0,1),'thunder',2),
 'throw':('none',(0.9,0.8,0.7,1),'body_swing',0),
}
VISUALS={
 'water_slash':('water-slash',0.90,0.48,1.1,0),
 'water_wheel':('water-wheel',0.88,0.52,1.2,0),
 'water_vortex':('water-wheel',0.84,0.45,1.2,0),
 'water_dragon':('water-dragon',0.93,0.55,1.5,1),
 'sun_arc':('sun-flame-arc',0.95,0.65,1.8,2),
 'thunder':('thunder',0.86,0.58,1.1,0),
 'iai':('thunder',0.80,0.50,1.0,0),
 'iai_return':('thunder',0.80,0.50,1.1,0),
 'sixfold':('thunder',0.88,0.62,1.5,1),
 'godspeed':('thunder',0.96,0.72,1.8,2),
}
TITLES = {"water_dragon", "sun_arc", "sixfold", "godspeed"}

def build():
 target=ROOT/'resources/presentation';target.mkdir(parents=True,exist_ok=True)
 for key,(shape,color,sound,trails) in PROFILES.items():
  text='[gd_resource type="Resource" script_class="MovePresentation" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/presentation/move_presentation.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
  text+=f'shape = "{shape}"\ncolor = Color({", ".join(str(x) for x in color)})\nsound_key = "{sound}"\ntrail_count = {trails}\ntrail_alpha = 0.12\n'
  if key in VISUALS:
   texture,body,glow,particles,tier=VISUALS[key]
   text+=f'texture_key = "{texture}"\nbody_opacity = {body}\nglow_strength = {glow}\nparticle_scale = {particles}\nsuper_tier = {tier}\n'
  if key in TITLES:
   text=text.replace('load_steps=2', 'load_steps=3')
   text=text.replace('[resource]', f'[ext_resource type="Texture2D" path="res://art/ui/super-titles/{key}.png" id="2"]\n\n[resource]')
   text+='title_texture = ExtResource("2")\n'
  (target/(key+'.tres')).write_text(text,encoding='utf-8')
if __name__=='__main__':build()
