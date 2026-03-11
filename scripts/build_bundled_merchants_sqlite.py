#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import json
import sqlite3
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Settings" / "Resources" / "BundledMerchants.sqlite"
CITY_DB = ROOT / "Settings" / "Resources" / "BundledCities.sqlite"
SNAPSHOT_URL = "https://cdn.static.btcmap.org/api/v4/places.json"
API_BASE = "https://api.btcmap.org/v4"

SYNC_FIELDS = [
    "id", "lat", "lon", "icon", "name", "display_name", "address",
    "opening_hours", "comments", "created_at", "updated_at", "deleted_at",
    "verified_at", "osm_id", "osm_url", "phone", "website", "email",
    "twitter", "facebook", "instagram", "telegram", "line",
    "boosted_until", "required_app_url", "description", "image", "payment_provider",
    "osm:payment:bitcoin", "osm:currency:XBT", "osm:payment:onchain",
    "osm:payment:lightning", "osm:payment:lightning_contactless",
    "osm:addr:housenumber", "osm:addr:street", "osm:addr:city",
    "osm:addr:country", "osm:addr:state", "osm:addr:postcode",
    "osm:operator", "osm:brand", "osm:brand:wikidata",
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DESTINATION)
    parser.add_argument("--city-db", type=Path, default=CITY_DB)
    parser.add_argument("--enrichment-json", type=Path)
    parser.add_argument("--empty", action="store_true")
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    connection = sqlite3.connect(args.output)
    try:
        create_schema(connection)

        if args.empty:
            persist_sync_state(
                connection,
                {
                    "schema_version": "5",
                },
            )
            connection.commit()
            print(f"Created empty merchant bundle at {args.output}")
            return

        records, snapshot_anchor, snapshot_last_modified = fetch_current_records()
        enrichment = load_enrichment(args.enrichment_json)
        city_lookup = CityLookup(args.city_db if args.city_db.exists() else None)
        generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

        for record in records:
            if record.get("deleted_at"):
                continue
            source_address = source_address_from_record(record)
            merged_address = merge_addresses(source_address, enrichment.get(str(record["id"])))
            city_location_id, city_key = resolve_city_linkage(city_lookup, merged_address)
            insert_merchant(connection, record, source_address, merged_address, city_location_id, city_key)

        persist_sync_state(
            connection,
            {
                "snapshot_last_modified_rfc1123": snapshot_last_modified or "",
                "incremental_anchor_updated_since": snapshot_anchor,
                "last_successful_sync_at": generated_at,
                "bundled_generated_at": generated_at,
                "bundled_source_anchor": snapshot_anchor,
                "schema_version": "5",
            },
        )
        connection.commit()
        print(f"Created {args.output} with {len(records)} merchants")
    finally:
        connection.close()


def create_schema(connection: sqlite3.Connection) -> None:
    cursor = connection.cursor()
    cursor.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;

        CREATE TABLE merchants (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT,
            deleted_at TEXT,
            lat REAL,
            lon REAL,
            osm_json BLOB,
            tags_json BLOB,
            v4_metadata_json BLOB,
            raw_address TEXT,
            source_street_number TEXT,
            source_street_name TEXT,
            source_city TEXT,
            source_postal_code TEXT,
            source_region TEXT,
            source_country TEXT,
            source_country_code TEXT,
            merged_street_number TEXT,
            merged_street_name TEXT,
            merged_city TEXT,
            merged_postal_code TEXT,
            merged_region TEXT,
            merged_country TEXT,
            merged_country_code TEXT,
            city_location_id TEXT,
            city_key TEXT
        );

        CREATE TABLE sync_state (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE address_enrichment_jobs (
            merchant_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT,
            retry_after TEXT,
            last_error_code TEXT
        );

        CREATE INDEX merchants_updated_at_idx ON merchants(updated_at);
        CREATE INDEX merchants_city_location_id_idx ON merchants(city_location_id);
        CREATE INDEX merchants_city_key_idx ON merchants(city_key);
        CREATE INDEX address_enrichment_jobs_schedule_idx ON address_enrichment_jobs(status, priority DESC, retry_after, last_attempt_at);
        PRAGMA user_version = 1;
        """
    )


def fetch_current_records() -> tuple[list[dict], str, str | None]:
    snapshot, snapshot_last_modified = fetch_json(SNAPSHOT_URL, include_last_modified=True)
    anchor = "1970-01-01T00:00:00Z"
    by_id: dict[int, dict] = {}
    next_anchor = anchor

    while True:
        query = urllib.parse.urlencode(
            {
                "fields": ",".join(SYNC_FIELDS),
                "updated_since": next_anchor,
                "include_deleted": "true",
                "limit": "5000",
            }
        )
        records = fetch_json(f"{API_BASE}/places?{query}")
        if not records:
            break

        for record in records:
            by_id[int(record["id"])] = record
        next_anchor = records[-1].get("updated_at") or next_anchor
        if len(records) < 5000:
            break

    if not by_id:
        for snapshot_record in snapshot:
            by_id[int(snapshot_record["id"])] = snapshot_record

    return list(by_id.values()), next_anchor, snapshot_last_modified


def fetch_json(url: str, include_last_modified: bool = False):
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request) as response:
        payload = json.loads(response.read().decode("utf-8"))
        if include_last_modified:
            return payload, response.headers.get("Last-Modified")
        return payload


def load_enrichment(path: Path | None) -> dict[str, dict]:
    if path is None or not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, dict):
        return payload
    raise ValueError("enrichment JSON must be an object keyed by merchant id")


def source_address_from_record(record: dict) -> dict | None:
    country = normalize_country(record.get("osm:addr:country"))
    address = {
        "street_number": compact(record.get("osm:addr:housenumber")),
        "street_name": compact(record.get("osm:addr:street")),
        "city": compact(record.get("osm:addr:city")),
        "postal_code": compact(record.get("osm:addr:postcode")),
        "region": compact(record.get("osm:addr:state")),
        "country": country["country_name"],
        "country_code": country["country_code"],
    }
    if any(value for value in address.values()):
        return address
    return None


def merge_addresses(source: dict | None, enrichment: dict | None) -> dict | None:
    if source is None and enrichment is None:
        return None
    source = source or {}
    enrichment = enrichment or {}
    return {
        "street_number": source.get("street_number") or compact(enrichment.get("street_number")),
        "street_name": source.get("street_name") or compact(enrichment.get("street_name")),
        "city": source.get("city") or compact(enrichment.get("city")),
        "postal_code": source.get("postal_code") or compact(enrichment.get("postal_code")),
        "region": source.get("region") or compact(enrichment.get("region")),
        "country": source.get("country") or compact(enrichment.get("country")),
        "country_code": source.get("country_code") or normalize_country_code(enrichment.get("country_code")),
    }


def insert_merchant(
    connection: sqlite3.Connection,
    record: dict,
    source_address: dict | None,
    merged_address: dict | None,
    city_location_id: str | None,
    city_key: str | None,
) -> None:
    osm_json = json.dumps(
        {
            "lat": record.get("lat"),
            "lon": record.get("lon"),
            "timestamp": record.get("updated_at") or record.get("created_at"),
            "type": "node",
            "tags": osm_tags_from_record(record),
        },
        separators=(",", ":"),
    ).encode("utf-8")
    tags_json = json.dumps(
        {
            "icon:android": record.get("icon"),
            "boost:expires": record.get("boosted_until"),
            "payment:provider": record.get("payment_provider"),
        },
        separators=(",", ":"),
    ).encode("utf-8")
    metadata_json = json.dumps(
        {
            "icon": record.get("icon"),
            "commentsCount": record.get("comments"),
            "verifiedAt": record.get("verified_at"),
            "boostedUntil": record.get("boosted_until"),
            "osmID": record.get("osm_id"),
            "osmURL": record.get("osm_url"),
            "email": record.get("email"),
            "twitter": record.get("twitter"),
            "facebook": record.get("facebook"),
            "instagram": record.get("instagram"),
            "telegram": record.get("telegram"),
            "line": record.get("line"),
            "requiredAppURL": record.get("required_app_url"),
            "imageURL": record.get("image"),
            "paymentProvider": record.get("payment_provider"),
            "rawAddress": compact(record.get("address")),
        },
        separators=(",", ":"),
    ).encode("utf-8")

    source_values = [
        (source_address or {}).get(key)
        for key in (
            "street_number",
            "street_name",
            "city",
            "postal_code",
            "region",
            "country",
            "country_code",
        )
    ]
    merged_values = [
        (merged_address or {}).get(key)
        for key in (
            "street_number",
            "street_name",
            "city",
            "postal_code",
            "region",
            "country",
            "country_code",
        )
    ]
    parameters = [
        str(record["id"]),
        record.get("created_at") or record.get("updated_at") or "1970-01-01T00:00:00Z",
        record.get("updated_at"),
        record.get("deleted_at"),
        record.get("lat"),
        record.get("lon"),
        osm_json,
        tags_json,
        metadata_json,
        compact(record.get("address")),
        *source_values,
        *merged_values,
        city_location_id,
        city_key,
    ]

    connection.execute(
        """
        INSERT OR REPLACE INTO merchants (
            id, created_at, updated_at, deleted_at, lat, lon, osm_json, tags_json, v4_metadata_json,
            raw_address,
            source_street_number, source_street_name, source_city, source_postal_code, source_region, source_country, source_country_code,
            merged_street_number, merged_street_name, merged_city, merged_postal_code, merged_region, merged_country, merged_country_code,
            city_location_id, city_key
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        parameters,
    )


def osm_tags_from_record(record: dict) -> dict:
    tags = {
        "name": compact(record.get("name")) or f"BTC Map Place #{record['id']}",
        "operator": compact(record.get("osm:operator")),
        "brand": compact(record.get("osm:brand")),
        "brand:wikidata": compact(record.get("osm:brand:wikidata")),
        "description": compact(record.get("description")),
        "website": compact(record.get("website")),
        "phone": compact(record.get("phone")),
        "opening_hours": compact(record.get("opening_hours")),
        "payment:bitcoin": compact(record.get("osm:payment:bitcoin")),
        "currency:XBT": compact(record.get("osm:currency:XBT")),
        "payment:onchain": compact(record.get("osm:payment:onchain")),
        "payment:lightning": compact(record.get("osm:payment:lightning")),
        "payment:lightning_contactless": compact(record.get("osm:payment:lightning_contactless")),
        "addr:housenumber": compact(record.get("osm:addr:housenumber")),
        "addr:street": compact(record.get("osm:addr:street")),
        "addr:city": compact(record.get("osm:addr:city")),
        "addr:country": compact(record.get("osm:addr:country")),
        "addr:state": compact(record.get("osm:addr:state")),
        "addr:postcode": compact(record.get("osm:addr:postcode")),
    }
    return {key: value for key, value in tags.items() if value}


def persist_sync_state(connection: sqlite3.Connection, values: dict[str, str]) -> None:
    connection.executemany(
        "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
        values.items(),
    )


def resolve_city_linkage(city_lookup: "CityLookup", address: dict | None) -> tuple[str | None, str | None]:
    if address is None:
        return None, None
    city = compact(address.get("city"))
    country = compact(address.get("country")) or compact(address.get("country_code"))
    if not city or not country:
        return None, None
    region = compact(address.get("region"))
    city_key = normalize_city_key(city, region, country)
    location_id = city_lookup.location_id_for_city_key(city_key)
    return location_id, city_key


class CityLookup:
    def __init__(self, db_path: Path | None) -> None:
        self.connection = sqlite3.connect(db_path) if db_path else None

    def location_id_for_city_key(self, city_key: str) -> str | None:
        if self.connection is None:
            return None
        cursor = self.connection.execute(
            "SELECT location_id FROM city_search WHERE city_key = ? LIMIT 1",
            (city_key,),
        )
        row = cursor.fetchone()
        return None if row is None else row[0]


def normalize_city_key(city: str, region: str | None, country: str) -> str:
    return "|".join(
        normalize_component(value)
        for value in (city, canonical_region(region, country), country)
    )


def normalize_component(value: str | None) -> str:
    if value is None:
        return ""
    return " ".join(value.split()).strip().lower()


def canonical_region(region: str | None, country: str) -> str:
    region = region or ""
    normalized_country = normalize_component(country)
    normalized_region = normalize_component(region)
    if normalized_country in {"united states", "usa", "us"}:
        return UNITED_STATES_REGION_ALIASES.get(normalized_region, region)
    return region


def compact(value: str | None) -> str | None:
    if value is None:
        return None
    value = " ".join(str(value).split()).strip()
    return value or None


def normalize_country(raw_country: str | None) -> dict:
    if raw_country is None:
        return {"country_name": None, "country_code": None}
    raw_country = compact(raw_country)
    if raw_country is None:
        return {"country_name": None, "country_code": None}
    if len(raw_country) == 2 and raw_country.isalpha():
        return {"country_name": None, "country_code": raw_country.upper()}
    return {"country_name": raw_country, "country_code": None}


def normalize_country_code(value: str | None) -> str | None:
    value = compact(value)
    if value and len(value) == 2 and value.isalpha():
        return value.upper()
    return None


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
