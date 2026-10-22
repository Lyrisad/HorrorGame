import sys
from PIL import Image
# grid2.py out cols img1 img2 ... : planche simple
out = sys.argv[1]; cols = int(sys.argv[2]); ims = [Image.open(p) for p in sys.argv[3:]]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows))
for i, im in enumerate(ims):
    sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.save(out)
