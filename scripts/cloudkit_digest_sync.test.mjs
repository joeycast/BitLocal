import test from "node:test";
import assert from "node:assert/strict";

import {
  buildDueDigestCandidateForCity,
  digestRecordName,
  formatLocalDate,
  normalizePlace,
  wasCreatedAfterAnchor,
  zonedDateParts,
  zonedLocalDateTimeToUtc
} from "./cloudkit_digest_sync.mjs";

test("zonedLocalDateTimeToUtc converts a city-local morning boundary", () => {
  const utcDate = zonedLocalDateTimeToUtc("2026-03-09", 8, 0, 0, "America/Chicago");
  assert.equal(utcDate.toISOString(), "2026-03-09T13:00:00.000Z");
});

test("buildDueDigestCandidateForCity waits until local morning", () => {
  const nowUtc = new Date("2026-03-09T12:00:00.000Z");
  const pending = [
    {
      recordName: "pending-1",
      locationID: "geonames:1234",
      cityKey: "honolulu|hi|united states",
      cityDisplayName: "Honolulu, HI, United States",
      timeZoneID: "Pacific/Honolulu",
      merchantID: "1",
      merchantName: "Aloha",
      merchantCreatedAt: new Date("2026-03-09T14:00:00.000Z")
    }
  ];

  const candidate = buildDueDigestCandidateForCity("geonames:1234", pending, nowUtc);
  assert.equal(candidate, null);
});

test("buildDueDigestCandidateForCity includes merchants before the city-local boundary", () => {
  const nowUtc = new Date("2026-03-09T16:30:00.000Z");
  const pending = [
    {
      recordName: "pending-1",
      locationID: "geonames:1",
      cityKey: "show low|az|united states",
      cityDisplayName: "Show Low, AZ, United States",
      timeZoneID: "America/Phoenix",
      merchantID: "1",
      merchantName: "CaveCutz",
      merchantCreatedAt: new Date("2026-03-09T13:00:00.000Z")
    },
    {
      recordName: "pending-2",
      locationID: "geonames:1",
      cityKey: "show low|az|united states",
      cityDisplayName: "Show Low, AZ, United States",
      timeZoneID: "America/Phoenix",
      merchantID: "2",
      merchantName: "Salon",
      merchantCreatedAt: new Date("2026-03-09T15:30:00.000Z")
    }
  ];

  const candidate = buildDueDigestCandidateForCity("geonames:1", pending, nowUtc);
  assert.ok(candidate);
  assert.equal(candidate.deliveryLocalDate, "2026-03-09");
  assert.equal(candidate.recordName, digestRecordName("geonames:1", "2026-03-09"));
  assert.deepEqual(candidate.merchantIDs, ["1"]);
});

test("formatLocalDate reflects timezone-local date parts", () => {
  const parts = zonedDateParts(new Date("2026-03-09T07:30:00.000Z"), "Europe/London");
  assert.equal(formatLocalDate(parts), "2026-03-09");
});

test("normalizePlace canonicalizes united states region abbreviations", () => {
  const normalized = normalizePlace({
    id: 1,
    name: "D.R Hair Oceanside",
    display_name: "D.R Hair Oceanside",
    created_at: "2026-03-09T23:34:40.170Z",
    updated_at: "2026-03-09T23:34:40.174Z",
    lat: "33.1959",
    lon: "-117.3795",
    "osm:addr:city": "Oceanside",
    "osm:addr:state": "CA",
    "osm:addr:country": "United States"
  }, null);

  assert.equal(normalized.locationID, "legacy:oceanside|california|united states");
  assert.equal(normalized.cityKey, "oceanside|california|united states");
  assert.equal(normalized.cityDisplayName, "Oceanside, California, United States");
});

test("normalizePlace prefers address-based location ID over nearest-city fallback", () => {
  const reverseGeocoder = {
    lookup() {
      return {
        locationID: "geonames:5139614",
        city: "Astoria",
        region: "New York",
        country: "United States",
        timeZoneID: "America/New_York"
      };
    },
    lookupByCityKey(cityKey) {
      if (cityKey === "astoria|new york|united states") {
        return {
          locationID: "geonames:5107464",
          city: "Astoria",
          region: "New York",
          country: "United States",
          timeZoneID: "America/New_York",
          population: 0
        };
      }
      return null;
    }
  };

  const normalized = normalizePlace({
    id: 1,
    name: "Bitcoin ATM",
    display_name: "Bitcoin ATM",
    created_at: "2026-03-09T23:34:40.170Z",
    updated_at: "2026-03-09T23:34:40.174Z",
    lat: "40.7643",
    lon: "-73.9235",
    "osm:addr:city": "Astoria",
    "osm:addr:state": "New York",
    "osm:addr:country": "United States"
  }, reverseGeocoder);

  assert.equal(normalized.locationID, "geonames:5107464");
});

test("wasCreatedAfterAnchor only accepts merchants created after the sync anchor", () => {
  assert.equal(
    wasCreatedAfterAnchor(new Date("2025-06-18T14:11:57.765Z"), new Date("2026-03-20T23:44:08.715Z")),
    false
  );
  assert.equal(
    wasCreatedAfterAnchor(new Date("2026-03-21T00:14:33.640Z"), new Date("2026-03-20T23:44:08.715Z")),
    true
  );
});

test("wasCreatedAfterAnchor allows bootstrap-style runs without a parsed anchor date", () => {
  assert.equal(wasCreatedAfterAnchor(new Date("2025-06-18T14:11:57.765Z"), null), true);
  assert.equal(wasCreatedAfterAnchor(null, new Date("2026-03-20T23:44:08.715Z")), false);
});
