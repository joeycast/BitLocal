import crypto from "node:crypto";
import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";

const SYNC_STATE_RECORD_NAME = "sync-state";
const DIGEST_RECORD_TYPE = "CityDigest";
const DIGEST_PENDING_RECORD_TYPE = "CityDigestPending";
const MERCHANT_RECORD_TYPE = "Merchant";
const SYNC_STATE_RECORD_TYPE = "SyncState";
const DELIVERY_HOUR_LOCAL = 8;
const QUERY_PAGE_SIZE = 200;
const CLOUDKIT_DEFAULT_ZONE = "_defaultZone";
const UNITED_STATES_REGION_ALIASES = {
  al: "Alabama",
  ak: "Alaska",
  az: "Arizona",
  ar: "Arkansas",
  ca: "California",
  co: "Colorado",
  ct: "Connecticut",
  de: "Delaware",
  dc: "District of Columbia",
  fl: "Florida",
  ga: "Georgia",
  hi: "Hawaii",
  id: "Idaho",
  il: "Illinois",
  in: "Indiana",
  ia: "Iowa",
  ks: "Kansas",
  ky: "Kentucky",
  la: "Louisiana",
  me: "Maine",
  md: "Maryland",
  ma: "Massachusetts",
  mi: "Michigan",
  mn: "Minnesota",
  ms: "Mississippi",
  mo: "Missouri",
  mt: "Montana",
  ne: "Nebraska",
  nv: "Nevada",
  nh: "New Hampshire",
  nj: "New Jersey",
  nm: "New Mexico",
  ny: "New York",
  nc: "North Carolina",
  nd: "North Dakota",
  oh: "Ohio",
  ok: "Oklahoma",
  or: "Oregon",
  pa: "Pennsylvania",
  ri: "Rhode Island",
  sc: "South Carolina",
  sd: "South Dakota",
  tn: "Tennessee",
  tx: "Texas",
  ut: "Utah",
  vt: "Vermont",
  va: "Virginia",
  wa: "Washington",
  wv: "West Virginia",
  wi: "Wisconsin",
  wy: "Wyoming"
};

const SYNC_FIELDS = [
  "id",
  "name",
  "display_name",
  "created_at",
  "updated_at",
  "deleted_at",
  "lat",
  "lon",
  "address",
  "osm:addr:city",
  "osm:addr:state",
  "osm:addr:country"
];

const environment = createEnvironment();

async function main() {
  if (!environment) {
    throw new Error("CloudKit digest sync requires configured environment variables.");
  }

  const reverseGeocoder = await loadReverseGeocoder();
  const runStartedAt = new Date();
  const deliveryNowUtc = parseDate(environment.nowUtcOverride) || runStartedAt;
  const syncState = await loadSyncState();
  const updatedSince = environment.updatedSinceOverride || syncState?.incrementalAnchorUpdatedSince || environment.initialUpdatedSince;
  const changes = await fetchBTCMapChanges(updatedSince);

  console.log(`Fetched ${changes.length} BTC Map place changes since ${updatedSince}.`);

  const shouldQueuePending = Boolean(syncState) || Boolean(environment.updatedSinceOverride);
  const forceReplayPending = Boolean(environment.updatedSinceOverride);
  if (!syncState) {
    console.log("No CloudKit sync state found. Bootstrapping merchant records without queueing digests.");
  }

  for (const place of changes) {
    await syncMerchant(place, reverseGeocoder, { shouldQueuePending, forceReplayPending });
  }

  const pendingRecords = await queryPendingRecords(environment.cityKeyFilter);
  const digestCandidates = buildDueDigestCandidates(pendingRecords, deliveryNowUtc);
  console.log(`Prepared ${digestCandidates.length} city digest record(s).`);

  for (const candidate of digestCandidates) {
    await processDigestCandidate(candidate);
  }

  const latestAnchor = latestUpdatedAt(changes) || updatedSince;
  await upsertSyncState({
    incrementalAnchorUpdatedSince: latestAnchor,
    lastSuccessfulSyncAt: runStartedAt.toISOString(),
    lastProcessedDigestWindow: runStartedAt.toISOString(),
    bootstrapCompleted: true
  });

  console.log("CloudKit digest sync finished.");
}

async function fetchBTCMapChanges(updatedSince) {
  const url = new URL("https://api.btcmap.org/v4/places");
  url.searchParams.set("fields", SYNC_FIELDS.join(","));
  url.searchParams.set("updated_since", updatedSince);
  url.searchParams.set("include_deleted", "true");
  url.searchParams.set("limit", "5000");

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`BTC Map sync failed with HTTP ${response.status}`);
  }

  return response.json();
}

async function loadSyncState() {
  const record = await loadRecordOrNull(SYNC_STATE_RECORD_NAME);
  return record ? decodeSyncStateRecord(record.fields) : null;
}

async function syncMerchant(place, reverseGeocoder, options) {
  const merchantRecordName = merchantRecordNameForPlace(place.id);
  const existingRecord = await loadRecordOrNull(merchantRecordName);
  const existingMerchant = existingRecord ? decodeMerchantRecord(existingRecord.fields) : null;
  const normalized = normalizePlace(place, reverseGeocoder);

  await saveRecord({
    recordName: merchantRecordName,
    recordType: MERCHANT_RECORD_TYPE,
    fields: {
      placeID: stringField(String(place.id)),
      locationID: stringField(normalized.locationID),
      cityKey: stringField(normalized.cityKey),
      cityDisplayName: stringField(normalized.cityDisplayName),
      displayName: stringField(normalized.displayName),
      createdAt: safeTimestampField(normalized.merchantCreatedAt),
      updatedAt: safeTimestampField(place.updated_at),
      deletedAt: safeTimestampField(place.deleted_at),
      sourceHash: stringField(hashObject(place)),
    timeZoneID: stringField(normalized.timeZoneID)
    },
    existingRecord
  });

  const priorPendingRecordName = existingMerchant?.locationID
    ? pendingRecordName(existingMerchant.locationID, place.id)
    : null;
  const priorPendingRecord = priorPendingRecordName ? await loadRecordOrNull(priorPendingRecordName) : null;

  if (place.deleted_at) {
    if (priorPendingRecordName && priorPendingRecord) {
      await deleteRecords([priorPendingRecordName]);
    }
    return;
  }

  if (!options.shouldQueuePending || !normalized.locationID || !normalized.merchantCreatedAt) {
    if (priorPendingRecordName
      && priorPendingRecord
      && existingMerchant?.locationID
      && existingMerchant.locationID != normalized.locationID) {
      await deleteRecords([priorPendingRecordName]);
    }
    return;
  }

  const shouldMaintainPending = !existingMerchant || priorPendingRecord || options.forceReplayPending;
  if (!shouldMaintainPending) {
    return;
  }

  const nextPendingRecordName = pendingRecordName(normalized.locationID, place.id);
  if (priorPendingRecordName && priorPendingRecordName !== nextPendingRecordName && priorPendingRecord) {
    await deleteRecords([priorPendingRecordName]);
  }

  const nextPendingExisting = priorPendingRecordName === nextPendingRecordName
    ? priorPendingRecord
    : await loadRecordOrNull(nextPendingRecordName);

  await saveRecord({
    recordName: nextPendingRecordName,
    recordType: DIGEST_PENDING_RECORD_TYPE,
    fields: {
      locationID: stringField(normalized.locationID),
      cityKey: stringField(normalized.cityKey),
      cityDisplayName: stringField(normalized.cityDisplayName),
      timeZoneID: stringField(normalized.timeZoneID),
      merchantID: stringField(String(place.id)),
      merchantName: stringField(normalized.displayName),
      merchantCreatedAt: safeTimestampField(normalized.merchantCreatedAt)
    },
    existingRecord: nextPendingExisting
  });
}

async function processDigestCandidate(candidate) {
  const existingDigestRecord = await loadRecordOrNull(candidate.recordName);
  if (existingDigestRecord) {
    const existingDigest = decodeDigestRecord(existingDigestRecord);
    const overlappingPending = candidate.pendingRecords
      .filter((pending) => existingDigest.merchantIDs.includes(pending.merchantID))
      .map((pending) => pending.recordName);

    if (overlappingPending.length) {
      await deleteRecords(overlappingPending);
    }
    return;
  }

  await saveRecord({
    recordName: candidate.recordName,
    recordType: DIGEST_RECORD_TYPE,
    fields: {
      locationID: stringField(candidate.locationID),
      cityKey: stringField(candidate.cityKey),
      cityDisplayName: stringField(candidate.cityDisplayName),
      digestWindowStart: safeTimestampField(candidate.digestWindowStart),
      digestWindowEnd: safeTimestampField(candidate.digestWindowEnd),
      merchantCount: int64Field(candidate.merchantCount),
      merchantIDs: stringListField(candidate.merchantIDs),
      topMerchantNames: stringListField(candidate.topMerchantNames),
      timeZoneID: stringField(candidate.timeZoneID),
      deliveryLocalDate: stringField(candidate.deliveryLocalDate)
    },
    existingRecord: null
  });

  await deleteRecords(candidate.pendingRecords.map((pending) => pending.recordName));
}

async function upsertSyncState(state) {
  const existingRecord = await loadRecordOrNull(SYNC_STATE_RECORD_NAME);

  await saveRecord({
    recordName: SYNC_STATE_RECORD_NAME,
    recordType: SYNC_STATE_RECORD_TYPE,
    fields: {
      incrementalAnchorUpdatedSince: stringField(state.incrementalAnchorUpdatedSince),
      lastSuccessfulSyncAt: safeTimestampField(state.lastSuccessfulSyncAt),
      lastProcessedDigestWindow: safeTimestampField(state.lastProcessedDigestWindow),
      bootstrapCompleted: stringField(state.bootstrapCompleted ? "true" : "false")
    },
    existingRecord
  });
}

async function saveRecord({ recordName, recordType, fields, existingRecord }) {
  const sanitizedFields = Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== null && value !== undefined)
  );

  const operationType = existingRecord ? "forceUpdate" : "create";
  const record = {
    recordName,
    recordType,
    fields: sanitizedFields
  };

  const response = await cloudKitModify([
    {
      operationType,
      record
    }
  ]);

  const result = response.records?.[0];
  if (!result || result.serverErrorCode) {
    console.error("CloudKit upsert failed:", JSON.stringify({ operationType, record }, null, 2));
    throw new Error(JSON.stringify(result || response));
  }

  return result;
}

async function deleteRecords(recordNames) {
  if (!recordNames.length) {
    return;
  }

  const uniqueRecordNames = Array.from(new Set(recordNames));
  for (const chunk of chunkArray(uniqueRecordNames, QUERY_PAGE_SIZE)) {
    const response = await cloudKitModify(
      chunk.map((recordName) => ({
        operationType: "forceDelete",
        record: { recordName }
      }))
    );

    for (const result of response.records || []) {
      if (result.serverErrorCode) {
        throw new Error(JSON.stringify(result));
      }
    }
  }
}

async function loadRecordOrNull(recordName) {
  try {
    return await lookupRecord(recordName);
  } catch (error) {
    if (isCloudKitNotFound(error)) {
      return null;
    }
    throw error;
  }
}

async function lookupRecord(recordName) {
  const response = await cloudKitRequest("/records/lookup", {
    records: [
      {
        recordName
      }
    ]
  });

  const match = response.records?.[0];
  if (!match || match.serverErrorCode) {
    throw new Error(JSON.stringify(match || response));
  }

  return match;
}

async function queryPendingRecords(cityKeyFilter = "") {
  const filterBy = [];
  if (cityKeyFilter) {
    filterBy.push({
      fieldName: "cityKey",
      comparator: "EQUALS",
      fieldValue: stringField(cityKeyFilter)
    });
  }

  const records = await queryRecords({
    recordType: DIGEST_PENDING_RECORD_TYPE,
    desiredKeys: [
      "cityKey",
      "locationID",
      "cityDisplayName",
      "timeZoneID",
      "merchantID",
      "merchantName",
      "merchantCreatedAt"
    ],
    filterBy,
    sortBy: [
      {
        fieldName: "merchantCreatedAt",
        ascending: true
      }
    ]
  });

  return records
    .map(decodePendingRecord)
    .filter((record) => !cityKeyFilter || record.cityKey === cityKeyFilter);
}

async function queryRecords({ recordType, desiredKeys = [], filterBy = [], sortBy = [] }) {
  const records = [];
  let continuationMarker = null;

  do {
    const body = {
      query: {
        recordType
      },
      zoneID: {
        zoneName: CLOUDKIT_DEFAULT_ZONE
      },
      resultsLimit: QUERY_PAGE_SIZE
    };

    if (desiredKeys.length) {
      body.desiredKeys = desiredKeys;
    }

    if (filterBy.length) {
      body.query.filterBy = filterBy;
    }

    if (sortBy.length) {
      body.query.sortBy = sortBy;
    }

    if (continuationMarker) {
      body.continuationMarker = continuationMarker;
    }

    const response = await cloudKitRequest("/records/query", body);
    for (const record of response.records || []) {
      if (!record.serverErrorCode) {
        records.push(record);
      }
    }
    continuationMarker = response.continuationMarker || null;
  } while (continuationMarker);

  return records;
}

function decodeSyncStateRecord(fields) {
  return {
    incrementalAnchorUpdatedSince: unwrapStringField(fields.incrementalAnchorUpdatedSince),
    lastSuccessfulSyncAt: unwrapTimestampField(fields.lastSuccessfulSyncAt),
    lastProcessedDigestWindow: unwrapTimestampField(fields.lastProcessedDigestWindow),
    bootstrapCompleted: unwrapStringField(fields.bootstrapCompleted) === "true"
  };
}

function decodeMerchantRecord(fields) {
  return {
    locationID: unwrapStringField(fields.locationID) || unwrapStringField(fields.cityKey),
    cityKey: unwrapStringField(fields.cityKey),
    timeZoneID: unwrapStringField(fields.timeZoneID)
  };
}

function decodeDigestRecord(record) {
  return {
    merchantIDs: unwrapStringListField(record.fields?.merchantIDs)
  };
}

function decodePendingRecord(record) {
  return {
    recordName: record.recordName,
    locationID: unwrapStringField(record.fields.locationID) || unwrapStringField(record.fields.cityKey),
    cityKey: unwrapStringField(record.fields.cityKey),
    cityDisplayName: unwrapStringField(record.fields.cityDisplayName),
    timeZoneID: validTimeZoneID(unwrapStringField(record.fields.timeZoneID)),
    merchantID: unwrapStringField(record.fields.merchantID),
    merchantName: unwrapStringField(record.fields.merchantName),
    merchantCreatedAt: parseDate(unwrapTimestampField(record.fields.merchantCreatedAt))
  };
}

function buildDueDigestCandidates(pendingRecords, nowUtc) {
  const grouped = new Map();

  for (const record of pendingRecords) {
    if (!record.locationID || !record.merchantCreatedAt) {
      continue;
    }

    const bucket = grouped.get(record.locationID) || [];
    bucket.push(record);
    grouped.set(record.locationID, bucket);
  }

  const candidates = [];
  for (const [locationID, records] of grouped.entries()) {
    const candidate = buildDueDigestCandidateForCity(locationID, records, nowUtc);
    if (candidate) {
      candidates.push(candidate);
    }
  }

  return candidates.sort((lhs, rhs) => lhs.locationID.localeCompare(rhs.locationID));
}

function buildDueDigestCandidateForCity(locationID, records, nowUtc) {
  const timeZoneID = validTimeZoneID(records.find((record) => record.timeZoneID)?.timeZoneID || "Etc/UTC");
  const localNow = zonedDateParts(nowUtc, timeZoneID);
  if (localNow.hour < DELIVERY_HOUR_LOCAL) {
    return null;
  }

  const deliveryLocalDate = formatLocalDate(localNow);
  const digestBoundaryUtc = zonedLocalDateTimeToUtc(deliveryLocalDate, DELIVERY_HOUR_LOCAL, 0, 0, timeZoneID);
  const eligiblePending = records
    .filter((record) => record.merchantCreatedAt && record.merchantCreatedAt.getTime() <= digestBoundaryUtc.getTime())
    .sort((lhs, rhs) => lhs.merchantCreatedAt - rhs.merchantCreatedAt);

  if (!eligiblePending.length) {
    return null;
  }

  const merchantIDs = eligiblePending.map((record) => record.merchantID);
  const topMerchantNames = Array.from(
    new Set(
      eligiblePending
        .map((record) => record.merchantName)
        .filter(Boolean)
    )
  ).slice(0, 5);

  return {
    recordName: digestRecordName(locationID, deliveryLocalDate),
    locationID,
    cityKey: eligiblePending[0].cityKey,
    cityDisplayName: eligiblePending[0].cityDisplayName,
    digestWindowStart: eligiblePending[0].merchantCreatedAt,
    digestWindowEnd: digestBoundaryUtc,
    merchantCount: merchantIDs.length,
    merchantIDs,
    topMerchantNames,
    timeZoneID,
    deliveryLocalDate,
    pendingRecords: eligiblePending
  };
}

function normalizePlace(place, reverseGeocoder) {
  const rawCity = place["osm:addr:city"] || "";
  const rawRegion = place["osm:addr:state"] || "";
  const rawCountry = place["osm:addr:country"] || "";
  const fallback = inferPlaceComponents(place, reverseGeocoder);
  const city = compactWhitespace(rawCity || fallback.city);
  const country = compactWhitespace(normalizeCountry(rawCountry, fallback.country));
  const region = compactWhitespace(normalizeRegion(rawRegion || fallback.region, country));
  const displayName = compactWhitespace(place.display_name || place.name || `BTC Map Merchant ${place.id}`);
  const timeZoneID = validTimeZoneID(fallback.timeZoneID || "Etc/UTC");

  return {
    locationID: fallback.locationID || inferLocationID(city, region, country, reverseGeocoder),
    cityKey: normalizeCityKey(city, region, country),
    cityDisplayName: [city, region, country].filter(Boolean).join(", "),
    displayName,
    merchantCreatedAt: parseDate(place.created_at),
    timeZoneID
  };
}

function inferLocationID(city, region, country, reverseGeocoder) {
  const cityKey = normalizeCityKey(city, region, country);
  if (!cityKey) {
    return "";
  }

  const matched = reverseGeocoder?.lookupByCityKey?.(cityKey);
  if (matched?.locationID) {
    return matched.locationID;
  }

  return `legacy:${cityKey}`;
}

function normalizeCityKey(city, region, country) {
  const normalizedCity = normalizeKeyComponent(city);
  if (!normalizedCity) {
    return "";
  }

  return [normalizedCity, normalizeKeyComponent(region), normalizeKeyComponent(country)].join("|");
}

function compactWhitespace(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function normalizeKeyComponent(value) {
  return compactWhitespace(value)
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function parseDate(value) {
  if (!value) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function latestUpdatedAt(records) {
  return records
    .map((record) => record.updated_at)
    .filter(Boolean)
    .sort()
    .at(-1);
}

function hashObject(value) {
  return hashString(JSON.stringify(value));
}

function hashString(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function merchantRecordNameForPlace(placeID) {
  return `merchant-${placeID}`;
}

function pendingRecordName(locationID, merchantID) {
  return `city-digest-pending-${hashString(`${locationID}|${merchantID}`)}`;
}

function digestRecordName(locationID, deliveryLocalDate) {
  return `city-digest-${hashString(`${locationID}|${deliveryLocalDate}`)}`;
}

function unwrapStringField(field) {
  return typeof field?.value === "string" ? field.value : "";
}

function unwrapStringListField(field) {
  return Array.isArray(field?.value) ? field.value.filter((value) => typeof value === "string") : [];
}

function unwrapTimestampField(field) {
  const value = field?.value;
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "number") {
    return new Date(value).toISOString();
  }
  return typeof value === "string" ? value : "";
}

function requireEnv(key) {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function createEnvironment() {
  if (!process.env.CLOUDKIT_CONTAINER_ID) {
    return null;
  }

  return {
    containerId: requireEnv("CLOUDKIT_CONTAINER_ID"),
    environment: process.env.CLOUDKIT_ENVIRONMENT || "development",
    database: (process.env.CLOUDKIT_DATABASE || "public").toLowerCase(),
    serverKeyId: requireEnv("CLOUDKIT_SERVER_KEY_ID"),
    serverPrivateKey: createSigningKey(requireEnv("CLOUDKIT_SERVER_PRIVATE_KEY")),
    initialUpdatedSince: process.env.BTCMAP_INITIAL_UPDATED_SINCE || "1970-01-01T00:00:00Z",
    geoNamesCitiesFile: process.env.GEONAMES_CITIES_FILE || "",
    geoNamesCountriesFile: process.env.GEONAMES_COUNTRIES_FILE || "",
    geoNamesAdmin1File: process.env.GEONAMES_ADMIN1_FILE || "",
    updatedSinceOverride: process.env.OVERRIDE_UPDATED_SINCE || "",
    nowUtcOverride: process.env.OVERRIDE_NOW_UTC || "",
    cityKeyFilter: process.env.CITY_KEY_FILTER || ""
  };
}

function stringField(value) {
  return { value };
}

function int64Field(value) {
  return { value };
}

function timestampField(value) {
  const date = value instanceof Date ? value : new Date(value);
  return { value: date.getTime() };
}

function safeTimestampField(value) {
  if (!value) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return timestampField(date);
}

function stringListField(values) {
  return { value: values };
}

function normalizePem(value) {
  return value
    .trim()
    .replace(/^['"]|['"]$/g, "")
    .replace(/\\n/g, "\n");
}

function createSigningKey(value) {
  const pem = normalizePem(value);
  const type = pem.includes("BEGIN EC PRIVATE KEY") ? "sec1" : "pkcs8";

  try {
    return crypto.createPrivateKey({
      key: pem,
      format: "pem",
      type
    });
  } catch (primaryError) {
    try {
      return crypto.createPrivateKey(pem);
    } catch (fallbackError) {
      throw new Error(
        `Unable to parse CLOUDKIT_SERVER_PRIVATE_KEY as an unencrypted PEM key. `
        + `Primary parser failed with: ${primaryError.message}. `
        + `Fallback parser failed with: ${fallbackError.message}.`
      );
    }
  }
}

function isoDateWithoutMilliseconds(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function base64Sha256(body) {
  return crypto.createHash("sha256").update(body).digest("base64");
}

function signMessage(message) {
  return crypto.sign("sha256", Buffer.from(message, "utf8"), environment.serverPrivateKey).toString("base64");
}

function cloudKitPath(subpath) {
  return `/database/1/${environment.containerId}/${environment.environment}/${environment.database}${subpath}`;
}

async function cloudKitModify(operations) {
  return cloudKitRequest("/records/modify", {
    atomic: false,
    operations
  });
}

async function cloudKitRequest(subpath, body) {
  const path = cloudKitPath(subpath);
  const bodyString = JSON.stringify(body);
  const isoDate = isoDateWithoutMilliseconds();
  const bodyHash = base64Sha256(bodyString);
  const signature = signMessage(`${isoDate}:${bodyHash}:${path}`);

  const response = await fetch(`https://api.apple-cloudkit.com${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Apple-CloudKit-Request-KeyID": environment.serverKeyId,
      "X-Apple-CloudKit-Request-ISO8601Date": isoDate,
      "X-Apple-CloudKit-Request-SignatureV1": signature
    },
    body: bodyString
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};

  if (!response.ok) {
    throw new Error(`CloudKit ${response.status}: ${JSON.stringify(payload)}`);
  }

  return payload;
}

function isCloudKitNotFound(error) {
  return /UNKNOWN_ITEM|NOT_FOUND|404|does not exist/i.test(String(error));
}

async function loadReverseGeocoder() {
  if (!environment.geoNamesCitiesFile || !environment.geoNamesCountriesFile || !environment.geoNamesAdmin1File) {
    console.log("GeoNames fallback disabled; city inference will use source address fields only.");
    return null;
  }

  const [citiesRaw, countriesRaw, admin1Raw] = await Promise.all([
    fs.readFile(environment.geoNamesCitiesFile, "utf8"),
    fs.readFile(environment.geoNamesCountriesFile, "utf8"),
    fs.readFile(environment.geoNamesAdmin1File, "utf8")
  ]);

  const countryNames = new Map();
  for (const line of countriesRaw.split("\n")) {
    if (!line || line.startsWith("#")) {
      continue;
    }

    const columns = line.split("\t");
    if (columns.length < 5) {
      continue;
    }

    countryNames.set(columns[0], columns[4]);
  }

  const admin1Names = new Map();
  for (const line of admin1Raw.split("\n")) {
    if (!line || line.startsWith("#")) {
      continue;
    }

    const columns = line.split("\t");
    if (columns.length < 2) {
      continue;
    }

    admin1Names.set(columns[0], columns[1]);
  }

  const buckets = new Map();
  const byCityKey = new Map();
  let inserted = 0;

  for (const line of citiesRaw.split("\n")) {
    if (!line) {
      continue;
    }

    const columns = line.split("\t");
    if (columns.length < 18) {
      continue;
    }

    const latitude = Number.parseFloat(columns[4]);
    const longitude = Number.parseFloat(columns[5]);
    if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
      continue;
    }

    const countryCode = columns[8];
    const admin1Code = columns[10];
    const geonameId = columns[0];
    const cityName = columns[2] || columns[1];
    const regionName = admin1Names.get(`${countryCode}.${admin1Code}`) || admin1Code;
    const countryName = countryNames.get(countryCode) || countryCode;
    const timeZoneID = validTimeZoneID(columns[17] || "Etc/UTC");
    const locationID = geonameId ? `geonames:${geonameId}` : "";
    const cityKey = normalizeCityKey(cityName, regionName, countryName);
    const population = Number.parseInt(columns[14], 10) || 0;

    const bucketKey = geoBucketKey(latitude, longitude);
    const bucket = buckets.get(bucketKey) || [];
    bucket.push({
      locationID,
      cityKey,
      city: cityName,
      region: regionName,
      country: countryName,
      latitude,
      longitude,
      population,
      timeZoneID
    });
    buckets.set(bucketKey, bucket);

    if (cityKey) {
      const existing = byCityKey.get(cityKey);
      if (!existing || population > existing.population) {
        byCityKey.set(cityKey, {
          locationID,
          cityKey,
          city: cityName,
          region: regionName,
          country: countryName,
          timeZoneID,
          population
        });
      }
    }
    inserted += 1;
  }

  console.log(`Loaded GeoNames reverse-geocoding index with ${inserted} cities across ${buckets.size} buckets.`);
  return {
    lookup(lat, lon) {
      return lookupNearestCity(buckets, lat, lon);
    },
    lookupByCityKey(cityKey) {
      return byCityKey.get(cityKey) || null;
    }
  };
}

function inferPlaceComponents(place, reverseGeocoder) {
  if (!reverseGeocoder) {
    return { locationID: "", city: "", region: "", country: "", timeZoneID: "Etc/UTC" };
  }

  const latitude = Number.parseFloat(place.lat);
  const longitude = Number.parseFloat(place.lon);
  if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
    return { locationID: "", city: "", region: "", country: "", timeZoneID: "Etc/UTC" };
  }

  return reverseGeocoder.lookup(latitude, longitude) || {
    locationID: "",
    city: "",
    region: "",
    country: "",
    timeZoneID: "Etc/UTC"
  };
}

function normalizeCountry(rawCountry, fallbackCountry) {
  const country = compactWhitespace(rawCountry);
  if (!country) {
    return fallbackCountry;
  }

  if (country.length === 2 && fallbackCountry) {
    return fallbackCountry;
  }

  return country;
}

function normalizeRegion(rawRegion, country) {
  const region = compactWhitespace(rawRegion);
  if (!region) {
    return region;
  }

  const normalizedCountry = normalizeKeyComponent(country);
  if (normalizedCountry === "united states" || normalizedCountry === "usa" || normalizedCountry === "us") {
    const alias = UNITED_STATES_REGION_ALIASES[normalizeKeyComponent(region)];
    if (alias) {
      return alias;
    }
  }

  return region;
}

function geoBucketKey(lat, lon) {
  return `${Math.floor(lat)}:${Math.floor(lon)}`;
}

function lookupNearestCity(buckets, lat, lon) {
  let best = null;

  for (let radius = 0; radius <= 2; radius += 1) {
    const candidates = [];

    for (let latOffset = -radius; latOffset <= radius; latOffset += 1) {
      for (let lonOffset = -radius; lonOffset <= radius; lonOffset += 1) {
        const key = `${Math.floor(lat) + latOffset}:${Math.floor(lon) + lonOffset}`;
        const bucket = buckets.get(key);
        if (bucket) {
          candidates.push(...bucket);
        }
      }
    }

    if (!candidates.length) {
      continue;
    }

    for (const candidate of candidates) {
      const distance = haversineKilometers(lat, lon, candidate.latitude, candidate.longitude);
      if (!best || distance < best.distance || (distance === best.distance && candidate.population > best.population)) {
        best = {
          locationID: candidate.locationID,
          city: candidate.city,
          region: candidate.region,
          country: candidate.country,
          timeZoneID: candidate.timeZoneID,
          distance,
          population: candidate.population
        };
      }
    }

    if (best) {
      return {
        locationID: best.locationID,
        city: best.city,
        region: best.region,
        country: best.country,
        timeZoneID: best.timeZoneID
      };
    }
  }

  return null;
}

function haversineKilometers(lat1, lon1, lat2, lon2) {
  const toRadians = (value) => value * (Math.PI / 180);
  const earthRadiusKm = 6371;
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function validTimeZoneID(candidate) {
  const timeZoneID = compactWhitespace(candidate);
  if (!timeZoneID) {
    return "Etc/UTC";
  }

  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timeZoneID }).format(new Date());
    return timeZoneID;
  } catch {
    return "Etc/UTC";
  }
}

function zonedDateParts(date, timeZoneID) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timeZoneID,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23"
  });

  const parts = Object.fromEntries(
    formatter
      .formatToParts(date)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value])
  );

  return {
    year: Number.parseInt(parts.year, 10),
    month: Number.parseInt(parts.month, 10),
    day: Number.parseInt(parts.day, 10),
    hour: Number.parseInt(parts.hour, 10),
    minute: Number.parseInt(parts.minute, 10),
    second: Number.parseInt(parts.second, 10)
  };
}

function formatLocalDate(parts) {
  return `${parts.year.toString().padStart(4, "0")}-${parts.month.toString().padStart(2, "0")}-${parts.day.toString().padStart(2, "0")}`;
}

function zonedLocalDateTimeToUtc(localDate, hour, minute, second, timeZoneID) {
  const [year, month, day] = localDate.split("-").map((value) => Number.parseInt(value, 10));
  let guess = Date.UTC(year, month - 1, day, hour, minute, second);

  for (let attempt = 0; attempt < 6; attempt += 1) {
    const actual = zonedDateParts(new Date(guess), timeZoneID);
    const desired = Date.UTC(year, month - 1, day, hour, minute, second);
    const actualAsUtc = Date.UTC(actual.year, actual.month - 1, actual.day, actual.hour, actual.minute, actual.second);
    const delta = actualAsUtc - desired;

    if (delta === 0) {
      return new Date(guess);
    }

    guess -= delta;
  }

  return new Date(guess);
}

function chunkArray(values, chunkSize) {
  const chunks = [];
  for (let index = 0; index < values.length; index += chunkSize) {
    chunks.push(values.slice(index, index + chunkSize));
  }
  return chunks;
}

export {
  buildDueDigestCandidateForCity,
  buildDueDigestCandidates,
  digestRecordName,
  formatLocalDate,
  normalizePlace,
  pendingRecordName,
  validTimeZoneID,
  zonedDateParts,
  zonedLocalDateTimeToUtc
};

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
