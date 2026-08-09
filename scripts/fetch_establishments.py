"""
2021年経済センサス活動調査（産業小分類・市区町村別）から、
選定した5カテゴリの事業所数を全市区町村分取得する。

出力: ../data/establishments_2021.json
  [{"area_code": "01101", "area_name": "札幌市中央区", "category_code": "767", "category_name": "喫茶店", "count": 123}, ...]

地域は政令指定都市の「区」を優先し、その親である「市」本体の集計行は除外することで、
全国の市区町村を重複なく1粒度に統一する（詳細は estat_utils.build_leaf_areas 参照）。

この統計表は小分類・中分類の両方を含むため、粒度を混在させて指定できる。
喫茶店・美容業・専門料理店は小分類まで絞り、コンビニ等を含む飲食料品小売業と
娯楽業は小分類にすると欠損が多すぎる（例: その他の各種商品小売業は欠損58%）ため
中分類のまま使う。
"""
import json
from pathlib import Path

import requests

from estat_utils import APP_ID, build_leaf_areas, build_prefecture_names, fetch_meta, parse_count

# 産業(小分類)、経営組織別事業所数。経営組織で「民営」に絞れる表を使う。
# 国・地方公共団体を含む「全事業所」ではなく民営に統一する理由は2つ:
#   1. アプリで見せたいのは店舗であって公共施設ではない（娯楽業で3%の差が出る）
#   2. 2016年の統計表が民営のみのため、時系列比較の定義を揃える必要がある
STATS_DATA_ID = "0004005689"
TAB_CODE = "102-2021"  # 事業所数
ORG_PRIVATE = "1"  # 経営組織: うち民営
CATEGORY_CODES = ["767", "783", "762", "58", "80"]

OUT_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)


def build_category_names(class_objs):
    cat_obj = next(o for o in class_objs if o["@id"] == "cat01")
    return {c["@code"]: c["@name"] for c in cat_obj["CLASS"]}


def fetch_all_values():
    params = {
        "appId": APP_ID,
        "statsDataId": STATS_DATA_ID,
        "cdTab": TAB_CODE,
        "cdCat01": ",".join(CATEGORY_CODES),
        "cdCat02": ORG_PRIVATE,
        "limit": 100000,
    }
    res = requests.get(
        "https://api.e-stat.go.jp/rest/3.0/app/json/getStatsData", params=params, timeout=120
    )
    res.raise_for_status()
    data = res.json()
    result = data["GET_STATS_DATA"]["RESULT"]
    if result["STATUS"] != 0:
        raise RuntimeError(result.get("ERROR_MSG"))

    stat_data = data["GET_STATS_DATA"]["STATISTICAL_DATA"]
    total = int(stat_data["RESULT_INF"]["TOTAL_NUMBER"])
    values = stat_data["DATA_INF"]["VALUE"]
    if len(values) != total:
        raise RuntimeError(f"取得件数が一致しません: got={len(values)} expected={total}")
    return values


def main():
    class_objs = fetch_meta(STATS_DATA_ID)
    leaf_areas = build_leaf_areas(class_objs)
    category_names = build_category_names(class_objs)
    print(f"対象市区町村数: {len(leaf_areas)}")

    # 同名市区町村（池田町など）を区別するために都道府県名も保存する
    prefectures = build_prefecture_names(class_objs)
    pref_path = OUT_DIR / "prefectures.json"
    pref_path.write_text(json.dumps(prefectures, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"都道府県マップを書き出し: {pref_path}")

    values = fetch_all_values()
    print(f"取得件数（フィルタ前）: {len(values)}")

    records = []
    skipped = 0
    for v in values:
        area_code = v["@area"]
        if area_code not in leaf_areas:
            skipped += 1
            continue
        cat_code = v["@cat01"]
        records.append(
            {
                "area_code": area_code,
                "area_name": leaf_areas[area_code],
                "category_code": cat_code,
                "category_name": category_names[cat_code],
                "count": parse_count(v["$"]),
            }
        )

    print(f"市区町村レベルとして採用: {len(records)}件（除外: {skipped}件）")

    out_path = OUT_DIR / "establishments_2021.json"
    out_path.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"書き出し: {out_path}")

    # ざっくり検証: 市区町村数 x カテゴリ数 と一致するはず
    expected = len(leaf_areas) * len(CATEGORY_CODES)
    print(f"期待件数: {expected}  実件数: {len(records)}  {'OK' if expected == len(records) else 'MISMATCH'}")


if __name__ == "__main__":
    main()
