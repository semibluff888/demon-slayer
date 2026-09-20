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
def build():
 target=ROOT/'resources/presentation';target.mkdir(parents=True,exist_ok=True)
 for key,(shape,color,sound,trails) in PROFILES.items():
  text='[gd_resource type="Resource" script_class="MovePresentation" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/presentation/move_presentation.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
  text+=f'shape = "{shape}"\ncolor = Color({", ".join(str(x) for x in color)})\nsound_key = "{sound}"\ntrail_count = {trails}\ntrail_alpha = 0.12\n'
  (target/(key+'.tres')).write_text(text,encoding='utf-8')
if __name__=='__main__':build()
