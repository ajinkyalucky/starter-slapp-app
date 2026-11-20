import re
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
from reportlab.lib.colors import CMYKColor, CMYKColorSep

W, H = 65.0, 95.0            # wallet face, mm
R = 8.0                      # corner radius (assumed from photo)
SAFE = 6.0                   # safe inset
M = 9.5                      # artwork margin
HEART_W, HEART_TOP = 5.0, 10.0
KING_W = 17.5

K = CMYKColor(0, 0, 0, 1)
GUIDE = CMYKColorSep(0, 1, 0, 0, spotName='Dieline')
SAFEC = CMYKColorSep(1, 0, 0, 0, spotName='SafeArea')
GREY = CMYKColor(0, 0, 0, 0.55)

def d_of(f): return re.search(r' d="([^"]+)"', open(f).read()).group(1)

def subpaths(d):
    toks = re.findall(r'[MLCZ]|-?[\d.]+(?:e-?\d+)?', d)
    out, cur, i = [], None, 0
    while i < len(toks):
        t = toks[i]
        if t == 'M': cur = [('M', float(toks[i+1]), float(toks[i+2]))]; out.append(cur); i += 3
        elif t == 'L': cur.append(('L', float(toks[i+1]), float(toks[i+2]))); i += 3
        elif t == 'C': cur.append(('C', *map(float, toks[i+1:i+7]))); i += 7
        elif t == 'Z': cur.append(('Z',)); i += 1
        else: raise ValueError(t)
    return out

king = subpaths(d_of('king.svg'))
# drop stray 1.15 x 6 unit sliver at top of source file (not part of the artwork)
king = [s for s in king if not all(c[0] == 'Z' or c[2] < 7 for c in s)]
heart = subpaths(d_of('heart.svg'))

def bbox(sp):
    xs = [c[i] for s in sp for c in s if c[0] != 'Z' for i in range(1, len(c), 2)]
    ys = [c[i] for s in sp for c in s if c[0] != 'Z' for i in range(2, len(c), 2)]
    return min(xs), min(ys), max(xs), max(ys)

def place(sp, x, y, w):
    """x,y = top-left in mm from wallet top-left; returns list of subpaths in mm + size"""
    x0, y0, x1, y1 = bbox(sp); s = w / (x1 - x0)
    res = []
    for sub in sp:
        n = []
        for c in sub:
            if c[0] == 'Z': n.append(c); continue
            pts = []
            for i in range(1, len(c), 2):
                pts += [x + (c[i] - x0) * s, y + (c[i+1] - y0) * s]
            n.append((c[0], *pts))
        res.append(n)
    return res, (y1 - y0) * s

king_h = (bbox(king)[3] - bbox(king)[1]) * KING_W / (bbox(king)[2] - bbox(king)[0])
heart_h = (bbox(heart)[3] - bbox(heart)[1]) * HEART_W / (bbox(heart)[2] - bbox(heart)[0])
KX, KY = W - M - KING_W, H - M - king_h
HX, HY = M, HEART_TOP
KING, _ = place(king, KX, KY, KING_W)
HEART, _ = place(heart, HX, HY, HEART_W)

def art(c, ox, oy, sc):
    """draw artwork; (ox,oy) = page pt position of wallet top-left, sc = scale"""
    X = lambda x: ox + x * mm * sc
    Y = lambda y: oy - y * mm * sc
    c.setFillColor(K)
    for shape in (KING, HEART):
        p = c.beginPath()
        for sub in shape:
            for cm in sub:
                if cm[0] == 'M': p.moveTo(X(cm[1]), Y(cm[2]))
                elif cm[0] == 'L': p.lineTo(X(cm[1]), Y(cm[2]))
                elif cm[0] == 'C': p.curveTo(X(cm[1]), Y(cm[2]), X(cm[3]), Y(cm[4]), X(cm[5]), Y(cm[6]))
                else: p.close()
        c.drawPath(p, stroke=0, fill=1, fillMode=0)
    return X, Y

# ---------- 1. production artwork, 1:1, page = wallet face ----------
c = canvas.Canvas('wallet-deboss-artwork.pdf', pagesize=(W*mm, H*mm))
c.setTitle('Wallet deboss artwork 65 x 95 mm'); c.setAuthor(''); 
art(c, 0, H*mm, 1); c.showPage(); c.save()

# ---------- 2. handover sheet, A4 landscape, drawing at 150% ----------
PW, PH = 297*mm, 210*mm
S = 1.5
c = canvas.Canvas('wallet-deboss-handover.pdf', pagesize=(PW, PH))
c.setTitle('Wallet deboss handover')
ox, oy = 42*mm, PH - 36*mm
X, Y = art(c, ox, oy, S)

c.setLineWidth(0.5); c.setStrokeColor(GUIDE)
c.roundRect(X(0), Y(H), W*mm*S, H*mm*S, R*mm*S)
c.setStrokeColor(SAFEC); c.setDash(3, 2)
c.roundRect(X(SAFE), Y(H-SAFE), (W-2*SAFE)*mm*S, (H-2*SAFE)*mm*S, (R-SAFE/2)*mm*S)
c.setDash()

def dim(x1, y1, x2, y2, label, off=0, side=1, lx=None, ly=None):
    """dimension line between two points in wallet mm; horizontal or vertical"""
    c.setStrokeColor(GREY); c.setFillColor(GREY); c.setLineWidth(0.35); c.setFont('Helvetica', 6.5)
    t = 2.2
    if y1 == y2:
        c.line(X(x1), Y(y1), X(x2), Y(y1))
        c.line(X(x1), Y(y1)-t, X(x1), Y(y1)+t); c.line(X(x2), Y(y1)-t, X(x2), Y(y1)+t)
        c.drawCentredString(X(lx) if lx is not None else (X(x1)+X(x2))/2, Y(y1) + (3 if side > 0 else -8.5), label)
    else:
        c.line(X(x1), Y(y1), X(x1), Y(y2))
        c.line(X(x1)-t, Y(y1), X(x1)+t, Y(y1)); c.line(X(x1)-t, Y(y2), X(x1)+t, Y(y2))
        if side > 0: c.drawString(X(x1) + 4, (Y(ly) if ly is not None else (Y(y1)+Y(y2))/2) - 2.2, label)
        else: c.drawRightString(X(x1) - 4, (Y(y1)+Y(y2))/2 - 2.2, label)

f = lambda v: ('%.1f' % v).rstrip('0').rstrip('.')
dim(0, -5, W, -5, '65 mm')
dim(-5, 0, -5, H, '95 mm', side=-1)
# heart
dim(0, HY + heart_h/2, HX, HY + heart_h/2, f(HX), lx=(SAFE+HX)/2)
dim(HX + HEART_W/2, 0, HX + HEART_W/2, HY, f(HY))
dim(HX, HY + heart_h + 3, HX + HEART_W, HY + heart_h + 3, f(HEART_W), side=-1)
# king
dim(KX + KING_W, KY + king_h/2, W, KY + king_h/2, f(M), lx=W-(SAFE+M)/2)
dim(KX + KING_W/2, KY + king_h, KX + KING_W/2, H, f(M), ly=H-(SAFE+M)/2)
dim(KX, KY - 3, KX + KING_W, KY - 3, f(KING_W))
dim(KX - 3, KY, KX - 3, KY + king_h, f(king_h), side=-1)
# safe
dim(0, 52, SAFE, 52, f(SAFE), lx=SAFE/2-0.4)

# text column
tx = 168*mm; ty = PH - 36*mm
def line(txt, size=8.5, col=K, gap=13, font='Helvetica'):
    global ty
    c.setFillColor(col); c.setFont(font, size); c.drawString(tx, ty, txt); ty -= gap
line('Card wallet deboss', 17, gap=17)
line('Print handover  ·  green and brown, same artwork', 8.5, GREY, gap=30)
def block(head, rows):
    global ty
    line(head.upper(), 6.5, GREY, gap=13)
    for a, b in rows:
        c.setFillColor(GREY); c.setFont('Helvetica', 8.5); c.drawString(tx, ty, a)
        c.setFillColor(K); c.drawString(tx + 38*mm, ty, b); ty -= 13
    ty -= 12
block('Size', [('Wallet face', '65 x 95 mm'), ('Corner radius', '%s mm, match to die' % f(R)),
               ('Safe area', '%s mm inset from edge' % f(SAFE)), ('Drawing scale', '150 %')])
block('Heart', [('Size', '%s x %s mm' % (f(HEART_W), f(heart_h))), ('From left edge', '%s mm' % f(HX)),
                ('From top edge', '%s mm' % f(HY))])
block('Crown mark', [('Size', '%s x %s mm' % (f(KING_W), f(king_h))), ('From right edge', '%s mm' % f(M)),
                     ('From bottom edge', '%s mm' % f(M)), ('Smallest pixel', '%.2f mm' % (9.8281 * KING_W / 334.154))])
block('Finish', [('Process', 'Blind deboss, no foil, no ink'), ('Artwork colour', '100 % K, vector'),
                 ('Black area', 'Pressed into the leather'), ('Leather', 'Green, brown')])
line('KEY', 6.5, GREY, gap=13)
for col, dash, lab in ((GUIDE, None, 'Cut edge, not printed'), (SAFEC, (3, 2), 'Safe area, not printed')):
    c.setStrokeColor(col); c.setLineWidth(0.8)
    if dash: c.setDash(*dash)
    c.line(tx, ty + 3, tx + 12*mm, ty + 3); c.setDash()
    c.setFillColor(K); c.setFont('Helvetica', 8.5); c.drawString(tx + 16*mm, ty, lab); ty -= 13
c.showPage(); c.save()
print(KX, KY, king_h, heart_h)
