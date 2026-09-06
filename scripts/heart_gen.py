# Hand-draw the LEFT HALF of a 16-wide x 14-tall heart as ASCII below
# ('#' = lit, '.' = empty), 8 characters per row. The script mirrors it to
# the full 16-wide shape, prints an ASCII preview, saves a PNG preview, and
# emits the SystemVerilog row-constant table for lives_painter.sv.
#
# Edit LEFT_HALF, re-run, check heart_preview.png, repeat until it looks right.

LEFT_HALF = [
    "...###..",
    "..#####.",
    ".#######",
    "########",
    "########",
    "########",
    "########",
    ".#######",
    "..######",
    "...#####",
    "....####",
    ".....###",
    "......##",
    ".......#",
]

ROW_WIDTH = 8


def mirror_row(half: str) -> str:
    half = half.ljust(ROW_WIDTH, ".")[:ROW_WIDTH]
    return half + half[::-1]


def main():
    full_rows = [mirror_row(r) for r in LEFT_HALF]

    print("ASCII preview (16 wide x %d tall):" % len(full_rows))
    for row in full_rows:
        print(row.replace("#", "#").replace(".", "."))

    try:
        import numpy as np
        from PIL import Image
        scale = 20
        h, w = len(full_rows), 16
        img = np.zeros((h * scale, w * scale, 3), dtype=np.uint8)
        for y, row in enumerate(full_rows):
            for x, ch in enumerate(row):
                if ch == "#":
                    img[y*scale:(y+1)*scale, x*scale:(x+1)*scale] = (255, 0, 0)
                else:
                    img[y*scale:(y+1)*scale, x*scale:(x+1)*scale] = (30, 30, 30)
        Image.fromarray(img).save("heart_preview.png")
        print("\nSaved heart_preview.png")
    except ImportError:
        print("\n(install numpy+pillow for a PNG preview - ascii above is still usable)")

    print("\nSystemVerilog row constants:")
    print(f"localparam int HEART_HEIGHT = {len(full_rows)};")
    print("localparam logic [15:0] HEART_ROW [0:%d] = '{" % (len(full_rows) - 1))
    for i, row in enumerate(full_rows):
        bits = row.replace("#", "1").replace(".", "0")
        comma = "," if i < len(full_rows) - 1 else ""
        print(f"    16'b{bits}{comma}")
    print("};")


if __name__ == "__main__":
    main()
