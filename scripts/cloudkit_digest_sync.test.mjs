import test from "node:test";
import assert from "node:assert/strict";

import {
  buildDueDigestCandidateForCity,
  digestRecordName,
  formatLocalDate,
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
      cityKey: "honolulu|hi|united states",
      cityDisplayName: "Honolulu, HI, United States",
      timeZoneID: "Pacific/Honolulu",
      merchantID: "1",
      merchantName: "Aloha",
      merchantCreatedAt: new Date("2026-03-09T14:00:00.000Z")
    }
  ];

  const candidate = buildDueDigestCandidateForCity("honolulu|hi|united states", pending, nowUtc);
  assert.equal(candidate, null);
});

test("buildDueDigestCandidateForCity includes merchants before the city-local boundary", () => {
  const nowUtc = new Date("2026-03-09T16:30:00.000Z");
  const pending = [
    {
      recordName: "pending-1",
      cityKey: "show low|az|united states",
      cityDisplayName: "Show Low, AZ, United States",
      timeZoneID: "America/Phoenix",
      merchantID: "1",
      merchantName: "CaveCutz",
      merchantCreatedAt: new Date("2026-03-09T13:00:00.000Z")
    },
    {
      recordName: "pending-2",
      cityKey: "show low|az|united states",
      cityDisplayName: "Show Low, AZ, United States",
      timeZoneID: "America/Phoenix",
      merchantID: "2",
      merchantName: "Salon",
      merchantCreatedAt: new Date("2026-03-09T15:30:00.000Z")
    }
  ];

  const candidate = buildDueDigestCandidateForCity("show low|az|united states", pending, nowUtc);
  assert.ok(candidate);
  assert.equal(candidate.deliveryLocalDate, "2026-03-09");
  assert.equal(candidate.recordName, digestRecordName("show low|az|united states", "2026-03-09"));
  assert.deepEqual(candidate.merchantIDs, ["1"]);
});

test("formatLocalDate reflects timezone-local date parts", () => {
  const parts = zonedDateParts(new Date("2026-03-09T07:30:00.000Z"), "Europe/London");
  assert.equal(formatLocalDate(parts), "2026-03-09");
});
