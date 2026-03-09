#!/usr/bin/env python3

import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Settings" / "Resources" / "BundledCities.tsv"
DESTINATION = ROOT / "Settings" / "Resources" / "BundledCities.sqlite"


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source file: {SOURCE}")

    if DESTINATION.exists():
        DESTINATION.unlink()

    connection = sqlite3.connect(DESTINATION)
    cursor = connection.cursor()
    cursor.execute("PRAGMA journal_mode=OFF")
    cursor.execute("PRAGMA synchronous=OFF")
    cursor.execute(
        """
        CREATE VIRTUAL TABLE city_search USING fts5(
            city,
            region,
            country,
            city_key UNINDEXED,
            aliases,
            ord UNINDEXED,
            tokenize='unicode61 remove_diacritics 2'
        )
        """
    )

    rows = []
    ordinal = 0
    with SOURCE.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 5:
                continue

            city, region, country, city_key, aliases = parts[:5]
            rows.append((city, region, country, city_key, aliases, ordinal))
            ordinal += 1

            if len(rows) >= 5000:
                cursor.executemany("INSERT INTO city_search VALUES (?,?,?,?,?,?)", rows)
                rows = []

    if rows:
        cursor.executemany("INSERT INTO city_search VALUES (?,?,?,?,?,?)", rows)

    connection.commit()
    cursor.execute("VACUUM")
    connection.close()

    print(f"Created {DESTINATION} with {ordinal} cities")


if __name__ == "__main__":
    main()
