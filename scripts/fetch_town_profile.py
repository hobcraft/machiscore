"""
町の性格を補う指標を国勢調査から取得する。

  * 5年間の人口増減率 … 伸びている町か、縮んでいる町か
  * 面積・人口密度     … 都市部か、山間・郊外か
  * 高齢化率           … 65歳以上の割合

事業所の密度だけでは「どういう町か」は分からない。同じスコアでも
人口が増えている町と減っている町では意味が違うので、その文脈を添える。

出力: ../data/town_profile.json
"""
import json
from pathlib import Path

import requests

from estat_utils import APP_ID, build_leaf_areas, fetch_meta, parse_count

# 2025年国勢調査の基本集計。5年間の増減率・面積・人口密度がこの1表に入っている。
PROFILE_STATS_ID = "0004050417"
TAB_CHANGE_RATE = "2025_35"  # 5年間の人口増減率
TAB_AREA = "2025_47"  # 面積（参考）
TAB_DENSITY = "2025_48"  # 人口密度

# 2020年国勢調査の年齢3区分。高齢化率に使う。
AGE_STATS_ID = "0003448299"
AGE_TAB_RATIO = "105"  # 割合
AGE_ELDERLY = "130"  # 65歳以上
AGE_BOTH_SEXES = "100"

OUT_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)


def fetch(stats_id, params):
    query = {"appId": APP_ID, "statsDataId": stats_id, "limit": 100000, **params}
    res = requests.get(
        "https://api.e-stat.go.jp/rest/3.0/app/json/getStatsData", params=query, timeout=180
    )
    res.raise_for_status()
    data = res.json()
    result = data["GET_STATS_DATA"]["RESULT"]
    if result["STATUS"] != 0:
        raise RuntimeError(f"{stats_id}: {result.get('ERROR_MSG')}")
    return data["GET_STATS_DATA"]["STATISTICAL_DATA"]["DATA_INF"]["VALUE"]


def parse_number(raw):
    """小数を含む値を float にする。該当なし・秘匿は None。"""
    if raw is None or raw in ("", "-", "X", "*", "…"):
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def main():
    leaf_areas = build_leaf_areas(fetch_meta(PROFILE_STATS_ID))
    print(f"対象市区町村数: {len(leaf_areas)}")

    profile = {code: {} for code in leaf_areas}

    for tab, key in [
        (TAB_CHANGE_RATE, "population_change_rate"),
        (TAB_AREA, "area_km2"),
        (TAB_DENSITY, "population_density"),
    ]:
        for value in fetch(PROFILE_STATS_ID, {"cdTab": tab}):
            code = value["@area"]
            if code in profile:
                profile[code][key] = parse_number(value["$"])
        print(f"  {key}: 取得")

    for value in fetch(
        AGE_STATS_ID,
        {"cdTab": AGE_TAB_RATIO, "cdCat01": AGE_ELDERLY, "cdCat02": AGE_BOTH_SEXES},
    ):
        code = value["@area"]
        if code in profile:
            profile[code]["elderly_rate"] = parse_number(value["$"])
    print("  elderly_rate: 取得")

    # 欠けている項目の件数を出して、静かに歯抜けにならないようにする
    for key in ["population_change_rate", "area_km2", "population_density", "elderly_rate"]:
        missing = sum(1 for v in profile.values() if v.get(key) is None)
        print(f"  {key}: 欠損 {missing}件 / {len(profile)}件")

    out_path = OUT_DIR / "town_profile.json"
    out_path.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"書き出し: {out_path}")
    for code in ("13113", "01101"):
        if code in profile:
            print(f"  {code}: {profile[code]}")


if __name__ == "__main__":
    main()
