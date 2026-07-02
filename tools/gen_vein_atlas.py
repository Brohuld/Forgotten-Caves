import random
from PIL import Image, ImageDraw

CELL = 128
GRID = 4
ATLAS = CELL * GRID

ROCK_BASE = (110, 114, 125)

# Ordre fixe = MetalTypes.TABLE + GemTypes.TABLE (voir VeinMaterials.atlas_order()
# dans VoxelWorld.gd/VeinMaterials.gd) - NE PAS CHANGER L'ORDRE ICI SANS CHANGER
# AUSSI CET ORDRE COTE GDSCRIPT (sinon les couleurs ne correspondront plus).
MATERIALS = [
    ("fer",           "metal", (140, 77, 56)),
    ("cuivre",        "metal", (184, 97, 41)),
    ("etain",         "metal", (179, 184, 189)),
    ("charbon",       "metal", (26, 26, 28)),
    ("argent",        "metal", (217, 219, 224)),
    ("or",            "metal", (242, 199, 38)),
    ("platine",       "metal", (204, 212, 230)),
    ("emeraude",      "gem", (26, 140, 77)),
    ("rubis",         "gem", (191, 20, 38)),
    ("saphir",        "gem", (31, 71, 173)),
    ("lapis_lazuli",  "gem", (51, 61, 133)),
    ("jade",          "gem", (102, 166, 122)),
    ("diamant_blanc", "gem", (230, 240, 247)),
    ("diamant_rose",  "gem", (237, 191, 204)),
    ("diamant_noir",  "gem", (36, 33, 38)),
]


def clamp255(v):
    return max(0, min(255, int(v)))


def shade(color, delta):
    return tuple(clamp255(c + delta) for c in color)


def rock_background(draw, rng):
    # grain de roche : petits carres de teinte grise legerement variable
    for y in range(0, CELL, 4):
        for x in range(0, CELL, 4):
            n = rng.randint(-10, 10)
            draw.rectangle([x, y, x + 3, y + 3], fill=shade(ROCK_BASE, n))


def draw_metal_cell(img_draw, rng, color):
    rock_background(img_draw, rng)
    # stries metalliques : traits epais inclines dans la couleur du metal
    for _ in range(7):
        cx = rng.randint(0, CELL)
        cy = rng.randint(0, CELL)
        length = rng.randint(30, 70)
        angle = rng.uniform(0, 3.14159)
        dx = length * 0.5 * __import__("math").cos(angle)
        dy = length * 0.5 * __import__("math").sin(angle)
        width = rng.randint(4, 9)
        c = shade(color, rng.randint(-15, 15))
        img_draw.line([cx - dx, cy - dy, cx + dx, cy + dy], fill=c, width=width)
    # reflets metalliques : traits fins plus clairs
    for _ in range(4):
        cx = rng.randint(0, CELL)
        cy = rng.randint(0, CELL)
        length = rng.randint(15, 35)
        angle = rng.uniform(0, 3.14159)
        dx = length * 0.5 * __import__("math").cos(angle)
        dy = length * 0.5 * __import__("math").sin(angle)
        c = shade(color, 70)
        img_draw.line([cx - dx, cy - dy, cx + dx, cy + dy], fill=c, width=2)


def draw_gem_cell(img_draw, rng, color):
    rock_background(img_draw, rng)
    # amas de facettes anguleuses (triangles) au centre de la case
    cx, cy = CELL / 2, CELL / 2
    cluster_r = 40
    for _ in range(6):
        ang = rng.uniform(0, 6.28318)
        px = cx + cluster_r * 0.5 * __import__("math").cos(ang) + rng.randint(-10, 10)
        py = cy + cluster_r * 0.5 * __import__("math").sin(ang) + rng.randint(-10, 10)
        size = rng.randint(18, 34)
        a2 = ang + rng.uniform(0.5, 2.0)
        p1 = (px, py)
        p2 = (px + size * __import__("math").cos(a2), py + size * __import__("math").sin(a2))
        p3 = (px + size * __import__("math").cos(a2 + 2.0), py + size * __import__("math").sin(a2 + 2.0))
        shade_delta = rng.choice([-35, -15, 15, 35])
        img_draw.polygon([p1, p2, p3], fill=shade(color, shade_delta), outline=shade(color, -50))
    # petites etincelles (sparkle) blanches
    for _ in range(2):
        sx = rng.randint(20, CELL - 20)
        sy = rng.randint(20, CELL - 20)
        s = rng.randint(4, 7)
        img_draw.line([sx - s, sy, sx + s, sy], fill=(255, 255, 255), width=2)
        img_draw.line([sx, sy - s, sx, sy + s], fill=(255, 255, 255), width=2)


atlas = Image.new("RGB", (ATLAS, ATLAS), ROCK_BASE)

for idx, (mat_id, category, color) in enumerate(MATERIALS):
    rng = random.Random(mat_id)  # seed deterministe par materiau
    cell_img = Image.new("RGB", (CELL, CELL), ROCK_BASE)
    d = ImageDraw.Draw(cell_img)
    if category == "metal":
        draw_metal_cell(d, rng, color)
    else:
        draw_gem_cell(d, rng, color)

    col = idx % GRID
    row = idx // GRID
    atlas.paste(cell_img, (col * CELL, row * CELL))

atlas.save("/sessions/dazzling-amazing-maxwell/mnt/outputs/vein_atlas.png")
print("OK", atlas.size, "materiaux:", len(MATERIALS))
