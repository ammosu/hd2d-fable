import sys,glob,json
from PIL import Image
names=sys.argv[2:]; S=int(sys.argv[1])
fs=[f for f in sorted(glob.glob('tex/*.png')) if not names or any(f.split('/')[-1].startswith(n) for n in names)]
ims=[Image.open(f).convert('RGBA') for f in fs]
MW=1900; x=y=0; rowh=0; pos=[]
for i in ims:
    w,h=i.width*S,i.height*S
    if x+w>MW: x=0; y+=rowh+8; rowh=0
    pos.append((x,y)); x+=w+8; rowh=max(rowh,h)
sheet=Image.new('RGBA',(MW,y+rowh),(70,75,95,255))
for i,p in zip(ims,pos):
    j=i.resize((i.width*S,i.height*S),Image.NEAREST); sheet.paste(j,p,j)
sheet.save('tools/work/contact.png'); print(sheet.size)
