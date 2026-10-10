from inspect_video import sheet
ranges=[('water_edges',2.0,13.3),('fire_edges',36.0,48.3),('district_edges',55.0,66.1),('nezuko_edges',91.6,104.5),('awakened_edges',111.2,123.1),('sixfold_edges',206.0,217.0),('godspeed_edges',223.2,235.0),('akaza_edges',526.0,541.8)]
for name,start,end in ranges:
    sheet(name,[round(start+i*0.15,3) for i in range(8)]+[round(end+i*0.15,3) for i in range(8)])
