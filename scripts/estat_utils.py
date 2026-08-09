"""e-Stat API 共通ユーティリティ。"""
import os

import requests
from dotenv import load_dotenv

load_dotenv()

APP_ID = os.environ["ESTAT_APP_ID"]


def parse_count(raw):
    """e-Statの値を整数にする。

    e-Statの表記では「-」は該当数値なし、つまり事業所が1軒も無いことを指す
    （秘匿は「X」で、こちらは別物）。「-」を欠損として平均から外すと、
    店が無い町ほど総合スコアが上がるという逆転が起きるため、0として扱う。
    「X」など判別できない値だけを None にする。
    """
    if raw == "-":
        return 0
    if raw is None or raw in ("", "X", "*", "…", "***"):
        return None
    return int(raw)


def fetch_meta(stats_data_id):
    params = {"appId": APP_ID, "statsDataId": stats_data_id}
    res = requests.get(
        "https://api.e-stat.go.jp/rest/3.0/app/json/getMetaInfo", params=params, timeout=60
    )
    res.raise_for_status()
    data = res.json()
    result = data["GET_META_INFO"]["RESULT"]
    if result["STATUS"] != 0:
        raise RuntimeError(result.get("ERROR_MSG"))
    return data["GET_META_INFO"]["METADATA_INF"]["CLASS_INF"]["CLASS_OBJ"]


# 市区町村数の妥当性チェック用。全国1741市区町村のうち政令指定都市20市を
# その区(175区)に置き換えた数(=1896)を基準とし、統計表ごとの差異(境界未定地域など)を許容する。
EXPECTED_LEAF_AREA_RANGE = (1850, 1950)


def _get_area_class(class_objs):
    area_obj = next(o for o in class_objs if "area" in o["@id"] or o["@name"].endswith("市区町村"))
    areas = area_obj["CLASS"]
    return [areas] if isinstance(areas, dict) else areas


def build_leaf_areas(class_objs):
    """市区町村（政令指定都市は区単位）のみを、level番号に依存せず抽出する。

    どの統計表でも「他の地域の親(parentCode)になっていないコード」が
    末端の行政区画（市区町村 or 政令市の区）になる、という性質を利用する。
    e-Stat側のメタデータ構造が変わって推定が破綻した場合に黙って
    誤ったデータを吐かないよう、件数の妥当性を検証する。
    """
    areas = _get_area_class(class_objs)
    parent_codes = {a["@parentCode"] for a in areas if a.get("@parentCode")}

    leaf_areas = {}
    for a in areas:
        code = a["@code"]
        if code == "00000":
            continue  # 全国合計（統計表によってはparentCodeで辿れないため明示的に除外）
        if code in parent_codes:
            continue  # 誰かの親 = 集計行なので除外
        leaf_areas[code] = a["@name"]

    low, high = EXPECTED_LEAF_AREA_RANGE
    if not low <= len(leaf_areas) <= high:
        raise RuntimeError(
            f"市区町村の抽出結果が想定外です: {len(leaf_areas)}件 (想定 {low}〜{high}件)。"
            "e-Statのメタデータ構造が変わった可能性があるため、build_leaf_areas を見直すこと。"
        )
    return leaf_areas


def build_prefecture_names(class_objs):
    """都道府県コード2桁 -> 都道府県名 のマップを作る。

    市区町村コードの上2桁が都道府県コードにあたるため、同名の市区町村
    （例: 池田町が4件）を区別する用途に使う。
    """
    prefectures = {}
    for a in _get_area_class(class_objs):
        code = a["@code"]
        if code != "00000" and code.endswith("000"):
            prefectures[code[:2]] = a["@name"]

    if len(prefectures) != 47:
        raise RuntimeError(f"都道府県が47件になりません: {len(prefectures)}件")
    return prefectures
