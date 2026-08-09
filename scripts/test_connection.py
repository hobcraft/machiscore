"""e-Stat API 疎通確認スクリプト。
経済センサスの統計表一覧を検索し、appId が有効かどうかを確認する。
"""
import os

import requests
from dotenv import load_dotenv

load_dotenv()

APP_ID = os.environ["ESTAT_APP_ID"]
BASE_URL = "https://api.e-stat.go.jp/rest/3.0/app/json/getStatsList"


def main():
    params = {
        "appId": APP_ID,
        "searchWord": "経済センサス 産業分類 事業所数",
        "limit": 10,
    }
    res = requests.get(BASE_URL, params=params, timeout=30)
    res.raise_for_status()
    data = res.json()

    result = data["GET_STATS_LIST"]["RESULT"]
    print(f"STATUS: {result['STATUS']}  MESSAGE: {result.get('ERROR_MSG', 'OK')}")

    if result["STATUS"] != 0:
        return

    table_inf = data["GET_STATS_LIST"]["DATALIST_INF"]["TABLE_INF"]
    if isinstance(table_inf, dict):
        table_inf = [table_inf]

    print(f"\n該当件数: {len(table_inf)}件\n")
    for t in table_inf:
        print(f"[{t['@id']}] {t['TITLE'].get('$', t['TITLE']) if isinstance(t['TITLE'], dict) else t['TITLE']}")
        print(f"  統計名: {t['STAT_NAME'].get('$', '')}")
        print(f"  公開日: {t.get('OPEN_DATE', '')}\n")


if __name__ == "__main__":
    main()
