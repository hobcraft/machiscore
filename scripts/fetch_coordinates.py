"""
市区町村ごとの代表点（緯度・経度）を作る。

結果画面に地図のプレビューを出すために要る。以前は「東京都府中市」という
文字列を地図アプリに丸投げして向こうに解決させていたが、アプリ内に描くには
座標が必要になった。

e-Stat の統計表には座標が無いので、Geolonia 住所データ（CC BY 4.0、
国土交通省位置参照情報と国土地理院のデータが元）から作る。
このデータは大字・町丁目ごとの点なので、市区町村コードでまとめて代表点にする。

代表点は平均ではなく中央値にしている。市区町村には飛地や離島が含まれることが
あり（東京都に属する島、合併で細長くなった市など）、平均だと誰も住んでいない
海の上に寄ってしまう。中央値なら点が密集している市街地側に残る。

出力: ../data/coordinates.json
  [{"area_code": "13113", "lat": 35.66, "lon": 139.70, "samples": 312}, ...]
"""
import csv
import io
import json
import statistics
from pathlib import Path

import requests

SOURCE_URL = (
    "https://raw.githubusercontent.com/geolonia/japanese-addresses/master/data/latest.csv"
)

OUT_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)
OUT_PATH = OUT_DIR / "coordinates.json"

# 日本の国土がおさまる範囲。取り違えたデータを読み込んだときに気づけるようにする
LAT_RANGE = (20.0, 46.0)
LON_RANGE = (122.0, 154.0)

# 市区町村の数。極端に少なければ取得か集計が壊れている
EXPECTED_AREA_RANGE = (1700, 1950)

# 元データに大字の登録が無く、代表点を作れない市区町村。
# どちらも役場の所在地を手で入れている。件数が増えるようなら
# 元データ側の変化を疑うこと（compute_density.py が欠落を検出して止まる）。
MANUAL_COORDINATES = {
    "13362": (34.5225, 139.2792),  # 東京都利島村（利島村役場）
    "43506": (32.3372, 130.9903),  # 熊本県湯前町（湯前町役場）
}


def download():
    print(f"取得中: {SOURCE_URL}")
    response = requests.get(SOURCE_URL, timeout=300)
    response.raise_for_status()
    print(f"  {len(response.content) / 1_000_000:.1f}MB")
    return response.content.decode("utf-8")


def collect_points(text):
    """市区町村コードごとに大字の座標を集める。"""
    reader = csv.DictReader(io.StringIO(text))
    required = {"市区町村コード", "緯度", "経度"}
    missing = required - set(reader.fieldnames or [])
    if missing:
        raise SystemExit(f"想定した列がありません: {missing} / 実際: {reader.fieldnames}")

    points = {}
    skipped = 0
    for row in reader:
        code = (row["市区町村コード"] or "").strip()
        lat_raw = (row["緯度"] or "").strip()
        lon_raw = (row["経度"] or "").strip()
        if len(code) != 5 or not lat_raw or not lon_raw:
            skipped += 1
            continue
        try:
            lat, lon = float(lat_raw), float(lon_raw)
        except ValueError:
            skipped += 1
            continue
        if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1]) or not (
            LON_RANGE[0] <= lon <= LON_RANGE[1]
        ):
            skipped += 1
            continue
        points.setdefault(code, []).append((lat, lon))

    print(f"  座標のある行: {sum(len(v) for v in points.values()):,} / 除外: {skipped:,}")
    return points


def to_representative(points):
    """飛地や離島に引っ張られないよう、緯度経度それぞれの中央値を取る。"""
    result = []
    for code, values in sorted(points.items()):
        result.append(
            {
                "area_code": code,
                "lat": round(statistics.median(v[0] for v in values), 6),
                "lon": round(statistics.median(v[1] for v in values), 6),
                "samples": len(values),
            }
        )
    return result


def main():
    points = collect_points(download())
    coordinates = to_representative(points)

    for code, (lat, lon) in sorted(MANUAL_COORDINATES.items()):
        if code in points:
            print(f"  {code} は元データに入ったので MANUAL_COORDINATES から外せます")
            continue
        coordinates.append({"area_code": code, "lat": lat, "lon": lon, "samples": 0})
    coordinates.sort(key=lambda c: c["area_code"])

    count = len(coordinates)
    if not (EXPECTED_AREA_RANGE[0] <= count <= EXPECTED_AREA_RANGE[1]):
        raise SystemExit(
            f"市区町村が{count}件しかありません（想定 {EXPECTED_AREA_RANGE}）。"
            "元データの形式が変わった可能性があります。"
        )

    OUT_PATH.write_text(
        json.dumps(coordinates, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    print(f"代表点: {count}件 -> {OUT_PATH}")


if __name__ == "__main__":
    main()
