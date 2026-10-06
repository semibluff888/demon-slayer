# coding: utf-8
"""Author only the expansion's resources from verified existing move archetypes."""
import json,re,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROFILES={
 'nezuko':dict(base='zenitsu',order=20,name='灶门祢豆子',epithet='守护之火，永不熄灭',element='血鬼术·爆血',role='灵巧 · 近身压制',color='Color(1.0, 0.40, 0.61, 1)',walk=2.4,clips=['blood_kick','rising_kick','spinning_kick','blood_burst','awakened_combo'],names=['爆血飞踢','升空踢','回旋踢','血鬼术·爆血','爆血·觉醒连击'],descriptions=['突进踢击 · 游戏演绎','上升对空 · 游戏演绎','回旋连踢 · 游戏演绎','多段爆血 · 1格','短暂觉醒连击 · 3格'],effect='blood-flame'),
 'akaza':dict(base='tanjiro',order=30,name='猗窝座',epithet='斗气不息，拳意不止',element='破坏杀',role='均衡 · 拳脚控距',color='Color(0.30, 0.76, 1.0, 1)',walk=2.2,clips=['air_type','crown_splitter','disorder','annihilation','blue_afterglow'],names=['破坏杀·空式','破坏杀·脚式·冠先割','破坏杀·乱式','破坏杀·灭式','终式·青银乱残光'],descriptions=['远程冲击波；轻快重远','上挑踢击；迎击空中','连续拳击；近身压制','强力冲拳 · 1格','六段冲击 · 3格'],effect='shockwave')}
def field(s,k,v):
 line=k+' = '+v
 return re.sub(r'^'+re.escape(k)+r' = .*$',lambda _:line,s,flags=re.M) if re.search(r'^'+re.escape(k)+r' = ',s,re.M) else s.rstrip()+'\n'+line+'\n'
def quoted(v):return json.dumps(v,ensure_ascii=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--character',choices=list(PROFILES));args=p.parse_args()
 for cid,c in PROFILES.items():
  if args.character and args.character!=cid:continue
  base=c['base'];definition=(ROOT/f'resources/characters/{base}.tres').read_text(encoding='utf-8').replace(base,cid)
  for k,v in dict(display_name=quoted(c['name']),epithet=quoted(c['epithet']),element_name=quoted(c['element']),role=quoted(c['role']),accent=c['color'],walk_speed=str(c['walk']),roster_order=str(c['order'])).items():definition=field(definition,k,v)
  start=definition.index('move_list =')
  definition=definition[:start]
  rows=[dict(input=n,name=c['names'][i],description=c['descriptions'][i]) for i,n in enumerate(['236 + A/C','623 + A/C','214 + B/D','236236 + A/C','236236 + A+C'])]
  definition+='move_list = Array[Dictionary]('+json.dumps(rows,ensure_ascii=False)+')\nportrait_faces_right = true\n'
  definition += 'menu_focus_x = 0.64\n' if cid=='nezuko' else ''
  definition += 'model_scale = '+('0.85' if cid=='nezuko' else '1.0')+'\nhit_reaction_frames = PackedInt32Array(2, 1, 3)\n'
  (ROOT/f'resources/characters/{cid}.tres').write_text(definition,encoding='utf-8')
  keys=[s+b for s in ['5','2','j'] for b in 'ABCD']+['236A','236C','623A','623C','214B','214D','super','max','throw']
  for key in keys:
   source=base
   if key=='super':source='tanjiro'
   if key=='max':source='zenitsu'
   text=(ROOT/f'moves/core/{source}_{key}.tres').read_text(encoding='utf-8')
   text=field(text,'id',quoted(cid+'_'+key))
   profile=cid+'_body'
   if len(key)==2 and key[0] in '52j':
    attack={'A':'轻爪' if cid=='nezuko' else '轻拳','B':'轻踢','C':'重爪' if cid=='nezuko' else '重拳','D':'重踢'}[key[-1]]
    text=field(text,'display_name',quoted(('空中' if key[0]=='j' else '蹲身' if key[0]=='2' else '')+attack))
    text=field(text,'effect_id','"body"')
   elif key=='throw':
    text=field(text,'display_name','"近身投"')
    profile='throw'
   else:
    i=0 if key.startswith('236') else 1 if key.startswith('623') else 2 if key.startswith('214') else 3 if key=='super' else 4
    clip=c['clips'][i];profile=clip
    text=field(text,'display_name',quoted(c['names'][i]+('·重' if key[-1:] in ['C','D'] else '·轻' if key[-1:] in ['A','B'] else '')))
    text=field(text,'animation_id',quoted(clip));text=field(text,'effect_id',quoted(clip))
    if cid=='akaza' and key=='super':
     for k,v in dict(active='8',hit_frames='PackedInt32Array(8)',travel='4.2').items():text=field(text,k,v)
    if cid=='akaza' and key=='max':
     for k,v in dict(active='36',hit_frames='PackedInt32Array(11, 17, 23, 29, 35, 41)',travel='2.5').items():text=field(text,k,v)
   text=re.sub(r'path="res://resources/presentation/[^"]+"',f'path="res://resources/presentation/{profile}.tres"',text)
   (ROOT/f'moves/core/{cid}_{key}.tres').write_text(text,encoding='utf-8')
  for i,clip in enumerate([cid+'_body']+c['clips']):
   special=i>0;tier=2 if i==5 else 1 if i==4 else 0
   shape=('blood' if cid=='nezuko' else 'shockwave') if special else 'body'
   text='[gd_resource type="Resource" script_class="MovePresentation" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/presentation/move_presentation.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
   fields=dict(shape=quoted(shape),color=c['color'],sound_key=quoted('blood' if cid=='nezuko' and special else 'shockwave' if special else 'body_swing'),texture_key=quoted(c['effect'] if special else ''),body_opacity='0.80',glow_strength='0.45',particle_scale='1.0',super_tier=str(tier),trail_count='9' if tier else '3' if special else '0',trail_alpha='0.18',trail_interval='0.05',trail_lifetime='0.24')
   if cid=='nezuko' and special:
    fields['texture_flip_h']='false' if i==2 else 'true';fields['effect_motion']=quoted(['forward','rising','sweep','burst','flurry'][i-1])
   if cid=='akaza' and special:fields['sigil_texture_key']='"compass"'
   if cid=='akaza' and i==1:fields['projectile_texture_key']='"shockwave"'
   if cid=='nezuko' and tier==2:fields['cut_in_path']='"res://art/characters/nezuko/awakened-portrait.png"'
   text+=''.join(k+' = '+v+'\n' for k,v in fields.items())
   (ROOT/f'resources/presentation/{clip}.tres').write_text(text,encoding='utf-8')
 print('Expansion resources authored; existing fighter moves untouched.')
if __name__=='__main__':main()
