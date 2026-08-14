"""
起動画面に置くピンマークの画像を作る。

Flutter の初期状態では LaunchImage が 1x1 の透明画像で、起動時に
真っ白な画面が一瞬出る。ダークモードだと白い板が光って見えて具合が悪い。

マークは lib/widgets/machiscore_logo.dart の MachiscoreMark と同じ
座標系（アイコンSVGの x:242-782, y:160-890）で描く。バーは塗らずに
くり抜いて背景を透かすので、明暗どちらの背景でも同じ形に見える。

ピンの色は明背景・暗背景のどちらでもコントラストが足りる中間の青を使う。
画像は1枚しか持てないため、明暗で色を変えられないので。

出力: ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{,@2x,@3x}.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"

# アイコンSVGの描画範囲。app_theme のマークと合わせる
SRC_X0, SRC_X1 = 242, 782
SRC_Y0, SRC_Y1 = 160, 890
SRC_W = SRC_X1 - SRC_X0
SRC_H = SRC_Y1 - SRC_Y0

# 表示サイズ（ポイント）。contentMode=center で原寸表示される
POINT_HEIGHT = 96
POINT_WIDTH = round(POINT_HEIGHT * SRC_W / SRC_H)

# 明暗どちらの地でも読める中間の青
PIN = (46, 123, 214)

# 背景（コントラスト検証用）
LIGHT_BG = (250, 250, 248)
DARK_BG = (19, 19, 18)

# アンチエイリアス用の拡大率
SUPERSAMPLE = 4


def relative_luminance(rgb):
    def channel(value):
        v = value / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = relative_luminance(a), relative_luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def draw_mark(width, height):
    """ピンを描き、バーは透明にくり抜く。"""
    scale = SUPERSAMPLE
    canvas = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    sx = width * scale / SRC_W
    sy = height * scale / SRC_H

    def x(v):
        return (v - SRC_X0) * sx

    def y(v):
        return (v - SRC_Y0) * sy

    # 頭の円
    r = 270 * sx
    draw.ellipse(
        [x(512) - r, y(430) - r * sy / sx, x(512) + r, y(430) + r * sy / sx],
        fill=PIN + (255,),
    )
    # 下の三角
    draw.polygon(
        [(x(280), y(565)), (x(512), y(890)), (x(744), y(565))],
        fill=PIN + (255,),
    )

    # バーは地の色を透かす。塗ると青地に青が乗って消えるため
    bars = [(364.0, 500.0, 115.0), (478.0, 432.0, 183.0), (592.0, 364.0, 251.0)]
    for left, top, bar_height in bars:
        draw.rounded_rectangle(
            [x(left), y(top), x(left + 68), y(top + bar_height)],
            radius=16 * sx,
            fill=(0, 0, 0, 0),
        )

    return canvas.resize((width, height), Image.LANCZOS)


def main():
    for bg, name in ((LIGHT_BG, "明背景"), (DARK_BG, "暗背景")):
        ratio = contrast(PIN, bg)
        mark = "OK" if ratio >= 3.0 else "★不足"
        print(f"  {name}とのコントラスト: {ratio:.2f}:1  {mark}")
        if ratio < 3.0:
            raise SystemExit("ピンの色が背景に埋もれる。PIN を調整すること。")

    for scale in (1, 2, 3):
        image = draw_mark(POINT_WIDTH * scale, POINT_HEIGHT * scale)
        suffix = "" if scale == 1 else f"@{scale}x"
        path = OUT_DIR / f"LaunchImage{suffix}.png"
        image.save(path)
        print(f"  {path.name}: {image.width}x{image.height}")


if __name__ == "__main__":
    main()
