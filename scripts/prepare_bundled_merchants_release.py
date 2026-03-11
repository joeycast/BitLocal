#!/usr/bin/env python3

import argparse
import sqlite3
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build_bundled_merchants_sqlite.py"
PROJECT = ROOT / "bitlocal.xcodeproj"
SCHEME = "bitlocal"
DEFAULT_TEST_DESTINATION = "platform=iOS Simulator,id=03C5F5DD-9BA9-4517-9110-867844323DD3"
DEFAULT_OUTPUT = ROOT / "Settings" / "Resources" / "BundledMerchants.sqlite"
REQUIRED_SYNC_KEYS = (
    "incremental_anchor_updated_since",
    "last_successful_sync_at",
    "bundled_generated_at",
    "bundled_source_anchor",
    "schema_version",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild and validate the bundled merchant snapshot before a release archive."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--city-db", type=Path)
    parser.add_argument("--enrichment-json", type=Path)
    parser.add_argument("--skip-tests", action="store_true")
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--scheme", default=SCHEME)
    parser.add_argument("--test-destination", default=DEFAULT_TEST_DESTINATION)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not BUILD_SCRIPT.exists():
        raise SystemExit(f"Missing build script: {BUILD_SCRIPT}")
    if args.enrichment_json is not None and not args.enrichment_json.exists():
        raise SystemExit(f"Missing enrichment JSON: {args.enrichment_json}")
    if args.city_db is not None and not args.city_db.exists():
        raise SystemExit(f"Missing city DB: {args.city_db}")
    if not args.project.exists():
        raise SystemExit(f"Missing Xcode project: {args.project}")

    build_command = [
        sys.executable,
        str(BUILD_SCRIPT),
        "--output",
        str(args.output),
    ]
    if args.city_db is not None:
        build_command.extend(["--city-db", str(args.city_db)])
    if args.enrichment_json is not None:
        build_command.extend(["--enrichment-json", str(args.enrichment_json)])

    run(build_command)
    merchant_count, sync_state = validate_bundle(args.output)

    print(
        "Validated bundled merchant DB:",
        f"{merchant_count} merchants,",
        f"anchor={sync_state['incremental_anchor_updated_since']},",
        f"generated={sync_state['bundled_generated_at']}",
    )

    if not args.skip_tests:
        run(
            [
                "xcodebuild",
                "test",
                "-project",
                str(args.project),
                "-scheme",
                args.scheme,
                "-destination",
                args.test_destination,
            ]
        )

    print(f"Release prep complete: {args.output}")


def validate_bundle(path: Path) -> tuple[int, dict[str, str]]:
    if not path.exists():
        raise SystemExit(f"Bundled merchant DB was not created: {path}")

    connection = sqlite3.connect(path)
    try:
        merchant_count = scalar(connection, "SELECT COUNT(*) FROM merchants")
        if merchant_count <= 0:
            raise SystemExit(f"Bundled merchant DB is empty: {path}")

        sync_state = {
            row[0]: row[1]
            for row in connection.execute("SELECT key, value FROM sync_state")
        }
        missing_keys = [key for key in REQUIRED_SYNC_KEYS if not sync_state.get(key)]
        if missing_keys:
            raise SystemExit(
                "Bundled merchant DB is missing required sync state keys: "
                + ", ".join(missing_keys)
            )
        return merchant_count, sync_state
    finally:
        connection.close()


def scalar(connection: sqlite3.Connection, query: str) -> int:
    row = connection.execute(query).fetchone()
    return 0 if row is None or row[0] is None else int(row[0])


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    subprocess.run(command, check=True, cwd=ROOT)


if __name__ == "__main__":
    main()
