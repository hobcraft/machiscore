"""
2016年経済センサス活動調査（産業小分類・市区町村別・民営事業所）から、
2021年と同じ5カテゴリの事業所数を取得する。5年間の増減を出すために使う。

出力: ../data/establishments_2016.json

2021年との突き合わせで注意した点:
  * 分類コードの体系が違う。2016年は連番(15390など)で、JSICコードは名前側に
    埋め込まれている。CATEGORY_CODE_2016 で明示的に対応付ける。
  * この統計表には全国行(00000)が無く、都道府県から始まる。
  * 平成の大合併後も一部で市町村コードが変わっている（富谷町→富谷市など）。
    RENAMED_AREAS で2021年のコードに寄せる。
  * 双葉町は2016年当時、避難指示区域で調査対象外のためデータが存在しない。
"""
import json
from pathlib import Path

import requests

from estat_utils import APP_ID, fetch_meta, parse_count

STATS_DATA_ID = "0003218645"
TAB_CODE = "832"  # 事業所数
ORG_TOTAL = "000"  # 経営組織: 総数（この表は民営事業所のみを集計している）
SIZE_TOTAL = "000"  # 従業者規模: 総数

# 2021年のJSICコード -> 2016年表での分類コード
CATEGORY_CODE_2016 = {
    "762": "15390",  # 専門料理店
    "767": "15580",  # 喫茶店
    "58": "12280",  # 飲食料品小売業
    "783": "15880",  # 美容業
    "80": "16280",  # 娯楽業
}

# 2016年 -> 2021年 で市区町村コードが変わったもの
RENAMED_AREAS = {
    "04423": "04216",  # 黒川郡富谷町 -> 富谷市
    "40305": "40231",  # 筑紫郡那珂川町 -> 那珂川市
}

OUT_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)


def fetch_all_values():
    params = {
        "appId": APP_ID,
        "statsDataId": STATS_DATA_ID,
        "cdTab": TAB_CODE,
        "cdCat01": ORG_TOTAL,
        "cdCat02": SIZE_TOTAL,
        "cdCat03": ",".join(CATEGORY_CODE_2016.values()),
        "limit": 100000,
    }
    res = requests.get(
        "https://api.e-stat.go.jp/rest/3.0/app/json/getStatsData", params=params, timeout=180
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
    # 2016年表は分類コードの対応付けが要になるので、名前で裏取りしておく
    class_objs = fetch_meta(STATS_DATA_ID)
    cat_names = {
        c["@code"]: c["@name"]
        for c in next(o for o in class_objs if o["@id"] == "cat03")["CLASS"]
    }
    for jsic, code_2016 in CATEGORY_CODE_2016.items():
        name = cat_names.get(code_2016, "")
        if not name.startswith(jsic):
            raise RuntimeError(
                f"分類コードの対応が崩れています: 2016年の{code_2016}は「{name}」で、"
                f"JSIC {jsic} と一致しません"
            )
    print("分類コードの対応を確認しました")

    code_to_jsic = {v: k for k, v in CATEGORY_CODE_2016.items()}
    values = fetch_all_values()
    print(f"取得件数（フィルタ前）: {len(values)}")

    records = []
    for v in values:
        area_code = v["@area"]
        # 都道府県計・政令市本体などの集計行はここでは落とさず、
        # 2021年側の市区町村コードと突き合わせる段階で自然に除外される
        area_code = RENAMED_AREAS.get(area_code, area_code)
        records.append(
            {
                "area_code": area_code,
                "category_code": code_to_jsic[v["@cat03"]],
                "count": parse_count(v["$"]),
            }
        )

    out_path = OUT_DIR / "establishments_2016.json"
    out_path.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"書き出し: {out_path} ({len(records)}件)")


if __name__ == "__main__":
    main()
