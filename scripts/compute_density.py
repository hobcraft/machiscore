"""
事業所数(establishments_2021.json)と人口(population_2020.json)を突合し、
昼間人口1万人あたりの事業所数（密度）とカテゴリ別の全国順位を計算する。

分母は昼間人口。飲食店や小売店が相手にするのは「その町に昼間いる人」であり、
夜間人口で割ると千代田区のようなオフィス街が実態とかけ離れた上位に出るため。

出力: ../data/machiscore.json と、アプリ同梱用の ../assets/data/machiscore.json
{
  "categories": [{"code": "76", "name": "飲食店"}, ...],
  "source_note": "...",
  "municipalities": {
    "13113": {
      "name": "渋谷区",
      "prefecture": "東京都",
      "day_population": 551344,
      "night_population": 243883,
      "day_night_ratio": 226.1,
      "categories": {
        "76": {"count": 4026, "density_per_10000": 73.02, "rank": 40, "total_ranked": 1889}
      }
    }
  }
}
"""
import json
import shutil
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
ASSET_PATH = PROJECT_ROOT / "assets" / "data" / "machiscore.json"

# 表示順もこの並び。e-Statの正式名称は硬いので、アプリでの見出しは平易にする。
CATEGORY_NAMES = {
    "762": "専門料理店",
    "767": "喫茶店",
    "58": "食料品店・スーパー",
    "783": "美容室",
    "80": "娯楽施設",
}

# 密度の表示桁数。順位もこの丸め後の値で決めるため、
# 「画面上は同じ数値なのに順位が違う」という矛盾が起きない。
DENSITY_DECIMALS = 2

# ランキングに載せる昼間人口の下限。
# これを下回る自治体は事業所が数件しかなく、1件増減するだけで密度が乱高下する。
# 例: 青ヶ島村は昼間人口205人・事業所2件で、そのままだと飲食店で全国43位に出てしまう。
# 数字の信頼性を保つため順位付けの母集団から外し、事業所数と密度だけ表示する。
RANKING_MIN_DAY_POPULATION = 1000


def rank_by_density(rows):
    """(area_code, count, density) のリストに競争順位(1,2,2,4形式)を付ける。

    同じ密度なら同順位にする。順位の判定には表示上の丸め後の値を使うので、
    アプリ上で同じ数値に見える市区町村は必ず同じ順位になる。
    """
    rows = sorted(rows, key=lambda r: r[2], reverse=True)
    total = len(rows)

    result = {}
    previous_density = None
    previous_rank = 0
    for index, (area_code, count, density) in enumerate(rows, start=1):
        if density == previous_density:
            rank = previous_rank  # 同値なので直前と同順位
        else:
            rank = index  # competition ranking: 同順位が続いた分だけ番号が飛ぶ
            previous_density = density
            previous_rank = rank
        result[area_code] = {
            "count": count,
            "density_per_10000": density,
            "rank": rank,
            "total_ranked": total,
            "score": percentile_score(rank, total),
        }
    return result


def change_rate(count_2016, count_2021):
    """5年間の増減率(%)。比較できない場合は None。

    2016年に0件だった場合は増加率が定義できない（0からの増加は無限大）ため
    比較対象から外す。片方でも欠損していれば同様。
    """
    if count_2016 is None or count_2021 is None or count_2016 == 0:
        return None
    return round((count_2021 - count_2016) / count_2016 * 100, 1)


def average_score(cat_result):
    """カテゴリ別スコアの平均を総合スコアとする。1つも無ければ None。"""
    scores = [c["score"] for c in cat_result.values() if c["score"] is not None]
    if not scores:
        return None
    return round(sum(scores) / len(scores))


def percentile_score(rank, total):
    """順位を0〜100点に変換する（1位=100点、最下位=0点）。

    密度そのものを偏差値にすると、千代田区のような外れ値に引きずられて
    大半の市区町村が低い値に潰れてしまう。順位ベースなら分布の歪みに強く、
    カテゴリごとに母集団サイズが違っても（喫茶店1728件 / 食料品店1863件）
    同じ尺度で比較・平均できる。
    """
    if total <= 1:
        return 100
    return round((total - rank) / (total - 1) * 100)


def main():
    establishments = json.loads((DATA_DIR / "establishments_2021.json").read_text(encoding="utf-8"))
    population = json.loads((DATA_DIR / "population_2020.json").read_text(encoding="utf-8"))
    prefectures = json.loads((DATA_DIR / "prefectures.json").read_text(encoding="utf-8"))

    # 5年前(2016年)の事業所数。定義を揃えるため両年とも民営事業所を使う。
    past = json.loads((DATA_DIR / "establishments_2016.json").read_text(encoding="utf-8"))
    counts_2016 = {}
    for p in past:
        counts_2016.setdefault(p["area_code"], {})[p["category_code"]] = p["count"]

    # 昼間人口が無い / 0 の市区町村は密度を計算できないので除外する
    pop_by_area = {p["area_code"]: p for p in population if p["day_population"]}

    # area_code -> category_code -> count
    counts = {}
    area_names = {}
    for e in establishments:
        area_code = e["area_code"]
        area_names[area_code] = e["area_name"]
        counts.setdefault(area_code, {})[e["category_code"]] = e["count"]

    dropped_no_population = [code for code in counts if code not in pop_by_area]

    # 密度は全市区町村ぶん計算するが、順位付けの母集団には
    # 昼間人口が RANKING_MIN_DAY_POPULATION 以上の自治体だけを入れる。
    densities = {}  # area_code -> cat_code -> density
    ranking_pool = {cat: [] for cat in CATEGORY_NAMES}
    unranked_codes = set()
    for area_code, cat_counts in counts.items():
        pop_entry = pop_by_area.get(area_code)
        if not pop_entry:
            continue
        day_population = pop_entry["day_population"]
        is_ranked = day_population >= RANKING_MIN_DAY_POPULATION
        if not is_ranked:
            unranked_codes.add(area_code)
        for cat_code, count in cat_counts.items():
            if count is None:
                continue
            density = round(count / day_population * 10000, DENSITY_DECIMALS)
            densities.setdefault(area_code, {})[cat_code] = (count, density)
            if is_ranked:
                ranking_pool[cat_code].append((area_code, count, density))

    ranks = {cat: rank_by_density(rows) for cat, rows in ranking_pool.items()}

    municipalities = {}
    for area_code, cat_counts in counts.items():
        pop_entry = pop_by_area.get(area_code)
        if not pop_entry:
            continue
        is_ranked = area_code not in unranked_codes
        cat_result = {}
        for cat_code in CATEGORY_NAMES:
            entry = densities.get(area_code, {}).get(cat_code)
            if entry is None:
                continue
            if is_ranked:
                cat_result[cat_code] = ranks[cat_code][area_code]
            else:
                # 母集団から外しているので順位もスコアも持たせない
                count, density = entry
                cat_result[cat_code] = {
                    "count": count,
                    "density_per_10000": density,
                    "rank": None,
                    "total_ranked": None,
                    "score": None,
                }

        # 5年間の増減はランキング対象かどうかに関わらず出す
        for cat_code, entry in cat_result.items():
            past_count = counts_2016.get(area_code, {}).get(cat_code)
            entry["count_2016"] = past_count
            entry["change_rate"] = change_rate(past_count, entry["count"])

        night_population = pop_entry["night_population"]
        day_population = pop_entry["day_population"]
        municipalities[area_code] = {
            "name": area_names[area_code],
            "prefecture": prefectures[area_code[:2]],
            "day_population": day_population,
            "night_population": night_population,
            # 昼夜間人口比率。100を超えれば昼に人が流入する町。
            "day_night_ratio": (
                round(day_population / night_population * 100, 1) if night_population else None
            ),
            "ranked": is_ranked,
            # 総合マチスコア。各カテゴリのスコアの平均。
            # データが無いカテゴリは0点扱いにせず平均から除く（0点にすると
            # 「秘匿されている」だけの町を不当に低く見せてしまうため）。
            "total_score": average_score(cat_result),
            "scored_category_count": sum(1 for c in cat_result.values() if c["score"] is not None),
            "categories": cat_result,
        }

    output = {
        "categories": [{"code": c, "name": n} for c, n in CATEGORY_NAMES.items()],
        "source_note": "民営事業所数=2021年・2016年経済センサス活動調査、"
        "昼間人口=2020年国勢調査（従業地・通学地集計）",
        "density_basis": "昼間人口1万人あたりの事業所数",
        "ranking_min_day_population": RANKING_MIN_DAY_POPULATION,
        "municipalities": municipalities,
    }

    out_path = DATA_DIR / "machiscore.json"
    out_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    # アプリ同梱用にコピーまで行う。手動コピーだとバッチ再実行時に
    # アプリ側が古いデータのまま取り残されるため、ここで必ず同期する。
    ASSET_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(out_path, ASSET_PATH)

    print(f"人口データが無く除外した地域: {len(dropped_no_population)}件 {dropped_no_population}")
    print(f"最終的な市区町村数: {len(municipalities)}")
    print(
        f"うちランキング対象外（昼間人口{RANKING_MIN_DAY_POPULATION}人未満）: "
        f"{len(unranked_codes)}件"
    )
    print(f"書き出し: {out_path}")
    print(f"アプリ同梱用にコピー: {ASSET_PATH}")


if __name__ == "__main__":
    main()
