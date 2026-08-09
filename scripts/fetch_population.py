"""
2020年国勢調査（常住地又は従業地・通学地別人口）から、市区町村別の
夜間人口（常住人口）と昼間人口を取得する。

密度の分母には昼間人口を使う。飲食店や小売店が相手にするのは
その市区町村に「昼間いる人」であり、夜間人口を分母にすると
千代田区のようなオフィス街の密度が実態より極端に高く出るため。
夜間人口も昼夜間人口比率の表示用に保持する。

出力: ../data/population_2020.json
  [{"area_code": "13113", "area_name": "渋谷区",
    "night_population": 243883, "day_population": 551344}, ...]
"""
import json
from pathlib import Path

import requests

from estat_utils import APP_ID, build_leaf_areas, fetch_meta, parse_count

STATS_DATA_ID = "0004003060"
CAT_NIGHT = "100"  # 常住地による人口_総数(夜間人口)
CAT_DAY = "180"  # 従業地・通学地による人口_総数(昼間人口)

OUT_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)


def fetch_all_values():
    params = {
        "appId": APP_ID,
        "statsDataId": STATS_DATA_ID,
        "cdCat01": f"{CAT_NIGHT},{CAT_DAY}",
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
    print(f"対象市区町村数: {len(leaf_areas)}")

    values = fetch_all_values()
    print(f"取得件数（フィルタ前）: {len(values)}")

    by_area = {}
    for v in values:
        area_code = v["@area"]
        if area_code not in leaf_areas:
            continue
        entry = by_area.setdefault(
            area_code,
            {
                "area_code": area_code,
                "area_name": leaf_areas[area_code],
                "night_population": None,
                "day_population": None,
            },
        )
        key = "night_population" if v["@cat01"] == CAT_NIGHT else "day_population"
        entry[key] = parse_count(v["$"])

    records = list(by_area.values())
    missing_day = [r["area_name"] for r in records if not r["day_population"]]
    print(f"市区町村レベルとして採用: {len(records)}件")
    print(f"昼間人口が取得できない市区町村: {len(missing_day)}件 {missing_day}")

    out_path = OUT_DIR / "population_2020.json"
    out_path.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"書き出し: {out_path}")

    expected = len(leaf_areas)
    status = "OK" if expected == len(records) else "MISMATCH"
    print(f"期待件数: {expected}  実件数: {len(records)}  {status}")


if __name__ == "__main__":
    main()
