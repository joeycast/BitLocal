#!/usr/bin/env python3

import io
import sqlite3
import unicodedata
import urllib.request
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Settings" / "Resources" / "BundledCities.sqlite"

GEONAMES_CITIES_URL = "https://download.geonames.org/export/dump/cities1000.zip"
GEONAMES_COUNTRIES_URL = "https://download.geonames.org/export/dump/countryInfo.txt"
GEONAMES_ADMIN1_URL = "https://download.geonames.org/export/dump/admin1CodesASCII.txt"


def main() -> None:
    cities_data = download_cities()
    country_info = download_text(GEONAMES_COUNTRIES_URL)
    admin1_info = download_text(GEONAMES_ADMIN1_URL)

    country_names = load_country_names(country_info)
    admin1_names = load_admin1_names(admin1_info)

    if DESTINATION.exists():
        DESTINATION.unlink()

    connection = sqlite3.connect(DESTINATION)
    cursor = connection.cursor()
    cursor.execute("PRAGMA journal_mode=OFF")
    cursor.execute("PRAGMA synchronous=OFF")
    cursor.execute(
        """
        CREATE VIRTUAL TABLE city_search USING fts5(
            location_id UNINDEXED,
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
    cursor.execute(
        """
        CREATE TABLE city_metadata(
            location_id TEXT PRIMARY KEY,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            population INTEGER NOT NULL,
            time_zone_id TEXT NOT NULL
        )
        """
    )

    rows: list[tuple[str, str, str, str, str, str, int]] = []
    metadata_rows: list[tuple[str, float, float, int, str]] = []
    for raw_line in cities_data.splitlines():
        if not raw_line:
            continue

        columns = raw_line.split("\t")
        if len(columns) < 18:
            continue

        geoname_id = columns[0].strip()
        city = compact_whitespace(columns[2] or columns[1])
        if not geoname_id or not city:
            continue

        country_code = columns[8].strip()
        admin1_code = columns[10].strip()
        region = admin1_names.get(f"{country_code}.{admin1_code}", admin1_code)
        country = country_names.get(country_code, country_code)
        population = int(columns[14] or "0")
        latitude = float(columns[4])
        longitude = float(columns[5])
        time_zone_id = columns[17].strip() or "Etc/UTC"

        aliases = build_aliases(
            city=city,
            ascii_name=columns[2].strip(),
            alternate_names=columns[3].strip(),
            region=region,
            country=country
        )

        rows.append(
            (
                f"geonames:{geoname_id}",
                city,
                region,
                country,
                normalize_city_key(city, region, country),
                aliases,
                population
            )
        )
        metadata_rows.append((f"geonames:{geoname_id}", latitude, longitude, population, time_zone_id))

    rows.sort(
        key=lambda row: (
            -row[6],
            normalize_search_text(row[1]),
            normalize_search_text(row[2]),
            normalize_search_text(row[3]),
        )
    )

    batched_rows = []
    for ordinal, row in enumerate(rows):
        batched_rows.append((*row[:6], ordinal))
        if len(batched_rows) >= 5000:
            cursor.executemany("INSERT INTO city_search VALUES (?,?,?,?,?,?,?)", batched_rows)
            batched_rows = []

    if batched_rows:
        cursor.executemany("INSERT INTO city_search VALUES (?,?,?,?,?,?,?)", batched_rows)

    cursor.executemany("INSERT INTO city_metadata VALUES (?,?,?,?,?)", metadata_rows)

    connection.commit()
    cursor.execute("VACUUM")
    connection.close()

    print(f"Created {DESTINATION} with {len(rows)} cities")


def download_cities() -> str:
    data = download_bytes(GEONAMES_CITIES_URL)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        with archive.open("cities1000.txt") as handle:
            return handle.read().decode("utf-8")


def download_text(url: str) -> str:
    return download_bytes(url).decode("utf-8")


def download_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url) as response:
        return response.read()


def load_country_names(raw: str) -> dict[str, str]:
    names: dict[str, str] = {}
    for line in raw.splitlines():
        if not line or line.startswith("#"):
            continue

        columns = line.split("\t")
        if len(columns) < 5:
            continue

        names[columns[0].strip()] = compact_whitespace(columns[4])

    return names


def load_admin1_names(raw: str) -> dict[str, str]:
    names: dict[str, str] = {}
    for line in raw.splitlines():
        if not line or line.startswith("#"):
            continue

        columns = line.split("\t")
        if len(columns) < 2:
            continue

        names[columns[0].strip()] = compact_whitespace(columns[1])

    return names


def build_aliases(*, city: str, ascii_name: str, alternate_names: str, region: str, country: str) -> str:
    aliases: list[str] = []
    seen: set[str] = set()

    def append(value: str) -> None:
        normalized = normalize_search_text(value)
        if normalized and normalized not in seen:
            aliases.append(normalized)
            seen.add(normalized)

    append(city)
    append(ascii_name)
    append(region)
    append(country)

    for name in alternate_names.split(","):
        append(name)

    return "|".join(aliases)


def normalize_city_key(city: str, region: str, country: str) -> str:
    return "|".join([
        normalize_search_text(city),
        normalize_search_text(canonical_region(region, country)),
        normalize_search_text(country),
    ])


def canonical_region(region: str, country: str) -> str:
    normalized_country = normalize_search_text(country)
    normalized_region = normalize_search_text(region)
    if normalized_country in {"united states", "usa", "us"}:
        return UNITED_STATES_REGION_ALIASES.get(normalized_region, compact_whitespace(region))
    return compact_whitespace(region)


def normalize_search_text(value: str) -> str:
    compacted = compact_whitespace(value)
    folded = unicodedata.normalize("NFKD", compacted)
    without_marks = "".join(character for character in folded if not unicodedata.combining(character))
    return without_marks.casefold()


def compact_whitespace(value: str) -> str:
    return " ".join(value.split()).strip()


UNITED_STATES_REGION_ALIASES = {
    "al": "Alabama",
    "ak": "Alaska",
    "az": "Arizona",
    "ar": "Arkansas",
    "ca": "California",
    "co": "Colorado",
    "ct": "Connecticut",
    "de": "Delaware",
    "dc": "District of Columbia",
    "fl": "Florida",
    "ga": "Georgia",
    "hi": "Hawaii",
    "id": "Idaho",
    "il": "Illinois",
    "in": "Indiana",
    "ia": "Iowa",
    "ks": "Kansas",
    "ky": "Kentucky",
    "la": "Louisiana",
    "me": "Maine",
    "md": "Maryland",
    "ma": "Massachusetts",
    "mi": "Michigan",
    "mn": "Minnesota",
    "ms": "Mississippi",
    "mo": "Missouri",
    "mt": "Montana",
    "ne": "Nebraska",
    "nv": "Nevada",
    "nh": "New Hampshire",
    "nj": "New Jersey",
    "nm": "New Mexico",
    "ny": "New York",
    "nc": "North Carolina",
    "nd": "North Dakota",
    "oh": "Ohio",
    "ok": "Oklahoma",
    "or": "Oregon",
    "pa": "Pennsylvania",
    "ri": "Rhode Island",
    "sc": "South Carolina",
    "sd": "South Dakota",
    "tn": "Tennessee",
    "tx": "Texas",
    "ut": "Utah",
    "vt": "Vermont",
    "va": "Virginia",
    "wa": "Washington",
    "wv": "West Virginia",
    "wi": "Wisconsin",
    "wy": "Wyoming",
}


if __name__ == "__main__":
    main()
