import crypto from "node:crypto";
import fs from "node:fs/promises";

const SYNC_STATE_RECORD_NAME = "sync-state";
const DIGEST_RECORD_TYPE = "CityDigest";
const MERCHANT_RECORD_TYPE = "Merchant";
const SYNC_STATE_RECORD_TYPE = "SyncState";

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

const environment = {
  containerId: requireEnv("CLOUDKIT_CONTAINER_ID"),
  environment: process.env.CLOUDKIT_ENVIRONMENT || "development",
  database: (process.env.CLOUDKIT_DATABASE || "public").toLowerCase(),
  serverKeyId: requireEnv("CLOUDKIT_SERVER_KEY_ID"),
  serverPrivateKey: createSigningKey(requireEnv("CLOUDKIT_SERVER_PRIVATE_KEY")),
  initialUpdatedSince: process.env.OVERRIDE_UPDATED_SINCE || process.env.BTCMAP_INITIAL_UPDATED_SINCE || "1970-01-01T00:00:00Z",
  digestWindowHours: Number.parseInt(process.env.DIGEST_WINDOW_HOURS || "24", 10),
  geoNamesCitiesFile: process.env.GEONAMES_CITIES_FILE || "",
  geoNamesCountriesFile: process.env.GEONAMES_COUNTRIES_FILE || "",
  geoNamesAdmin1File: process.env.GEONAMES_ADMIN1_FILE || ""
};

async function main() {
  const reverseGeocoder = await loadReverseGeocoder();
  const syncState = await loadSyncState();
  const updatedSince = syncState?.incrementalAnchorUpdatedSince || environment.initialUpdatedSince;
  const changes = await fetchBTCMapChanges(updatedSince);

  console.log(`Fetched ${changes.length} BTC Map place changes since ${updatedSince}.`);

  if (!syncState) {
    console.log("No CloudKit sync state found. Bootstrapping merchant records without creating digests.");
  }

  for (const place of changes) {
    await upsertMerchant(place, reverseGeocoder);
  }

  const latestAnchor = latestUpdatedAt(changes) || updatedSince;
  const digestWindowEnd = new Date();
  const digestWindowStart = new Date(digestWindowEnd.getTime() - (environment.digestWindowHours * 60 * 60 * 1000));

  if (syncState) {
    const digestCandidates = changes.filter((place) => {
      if (place.deleted_at) {
        return false;
      }

      const createdAt = parseDate(place.created_at);
      return createdAt && createdAt > digestWindowStart;
    });

    const cityDigests = buildCityDigests(digestCandidates, digestWindowStart, digestWindowEnd, reverseGeocoder);
    console.log(`Prepared ${cityDigests.length} city digest record(s).`);

    for (const digest of cityDigests) {
      await upsertCityDigest(digest);
    }
  }

  await upsertSyncState({
    incrementalAnchorUpdatedSince: latestAnchor,
    lastSuccessfulSyncAt: digestWindowEnd.toISOString(),
    lastProcessedDigestWindow: digestWindowEnd.toISOString(),
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
  try {
    const response = await lookupRecord(SYNC_STATE_RECORD_NAME);
    return decodeSyncStateRecord(response.fields);
  } catch (error) {
    if (isCloudKitNotFound(error)) {
      return null;
    }
    throw error;
  }
}

async function upsertMerchant(place, reverseGeocoder) {
  const recordName = `merchant-${place.id}`;
  const normalized = normalizePlace(place, reverseGeocoder);

  await upsertRecord({
    recordName,
    recordType: MERCHANT_RECORD_TYPE,
    fields: {
      placeID: stringField(String(place.id)),
      cityKey: stringField(normalized.cityKey),
      cityDisplayName: stringField(normalized.cityDisplayName),
      displayName: stringField(normalized.displayName),
      createdAt: safeTimestampField(place.created_at),
      updatedAt: safeTimestampField(place.updated_at),
      deletedAt: safeTimestampField(place.deleted_at),
      sourceHash: stringField(hashObject(place))
    }
  });
}

async function upsertCityDigest(digest) {
  await upsertRecord({
    recordName: digest.recordName,
    recordType: DIGEST_RECORD_TYPE,
    fields: {
      cityKey: stringField(digest.cityKey),
      cityDisplayName: stringField(digest.cityDisplayName),
      digestWindowStart: safeTimestampField(digest.digestWindowStart),
      digestWindowEnd: safeTimestampField(digest.digestWindowEnd),
      merchantCount: int64Field(digest.merchantCount),
      merchantIDs: stringListField(digest.merchantIDs),
      topMerchantNames: stringListField(digest.topMerchantNames)
    }
  });
}

async function upsertSyncState(state) {
  await upsertRecord({
    recordName: SYNC_STATE_RECORD_NAME,
    recordType: SYNC_STATE_RECORD_TYPE,
    fields: {
      incrementalAnchorUpdatedSince: stringField(state.incrementalAnchorUpdatedSince),
      lastSuccessfulSyncAt: safeTimestampField(state.lastSuccessfulSyncAt),
      lastProcessedDigestWindow: safeTimestampField(state.lastProcessedDigestWindow),
      bootstrapCompleted: stringField(state.bootstrapCompleted ? "true" : "false")
    }
  });
}

async function upsertRecord({ recordName, recordType, fields }) {
  const sanitizedFields = Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== null && value !== undefined)
  );

  const existing = await lookupRecord(recordName).catch((error) => {
    if (isCloudKitNotFound(error)) {
      return null;
    }
    throw error;
  });

  const operationType = existing ? "forceUpdate" : "create";
  const record = {
    recordName,
    recordType,
    fields: sanitizedFields
  };

  const body = {
    atomic: false,
    operations: [
      {
        operationType,
        record
      }
    ]
  };

  const response = await cloudKitRequest("/records/modify", body);
  const result = response.records?.[0];
  if (!result || result.serverErrorCode) {
    console.error("CloudKit upsert failed:", JSON.stringify({ operationType, record }, null, 2));
    throw new Error(JSON.stringify(result || response));
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

function decodeSyncStateRecord(fields) {
  return {
    incrementalAnchorUpdatedSince: unwrapStringField(fields.incrementalAnchorUpdatedSince),
    lastSuccessfulSyncAt: unwrapTimestampField(fields.lastSuccessfulSyncAt),
    lastProcessedDigestWindow: unwrapTimestampField(fields.lastProcessedDigestWindow),
    bootstrapCompleted: unwrapStringField(fields.bootstrapCompleted) === "true"
  };
}

function buildCityDigests(changes, digestWindowStart, digestWindowEnd, reverseGeocoder) {
  const grouped = new Map();

  for (const place of changes) {
    const normalized = normalizePlace(place, reverseGeocoder);
    if (!normalized.cityKey) {
      continue;
    }

    const current = grouped.get(normalized.cityKey) || {
      cityKey: normalized.cityKey,
      cityDisplayName: normalized.cityDisplayName,
      digestWindowStart,
      digestWindowEnd,
      merchantIDs: [],
      topMerchantNames: []
    };

    current.merchantIDs.push(String(place.id));
    if (normalized.displayName && current.topMerchantNames.length < 5) {
      current.topMerchantNames.push(normalized.displayName);
    }

    grouped.set(normalized.cityKey, current);
  }

  return Array.from(grouped.values()).map((digest) => ({
    ...digest,
    merchantCount: digest.merchantIDs.length,
    topMerchantNames: Array.from(new Set(digest.topMerchantNames)).slice(0, 5),
    recordName: `city-digest-${hashString(`${digest.cityKey}|${digestWindowStart.toISOString()}`)}`
  }));
}

function normalizePlace(place, reverseGeocoder) {
  const rawCity = place["osm:addr:city"] || "";
  const rawRegion = place["osm:addr:state"] || "";
  const rawCountry = place["osm:addr:country"] || "";
  const fallback = inferPlaceComponents(place, reverseGeocoder);
  const city = compactWhitespace(rawCity || fallback.city);
  const region = compactWhitespace(rawRegion || fallback.region);
  const country = compactWhitespace(normalizeCountry(rawCountry, fallback.country));
  const displayName = compactWhitespace(place.display_name || place.name || `BTC Map Merchant ${place.id}`);

  return {
    cityKey: normalizeCityKey(city, region, country),
    cityDisplayName: [city, region, country].filter(Boolean).join(", "),
    displayName
  };
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
  const date = new Date(value);
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

function unwrapStringField(field) {
  return typeof field?.value === "string" ? field.value : "";
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

function stringField(value) {
  return {
    value
  };
}

function int64Field(value) {
  return {
    value
  };
}

function timestampField(value) {
  const date = value instanceof Date ? value : new Date(value);
  return {
    value: date.getTime()
  };
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
  return {
    value: values
  };
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
        `Unable to parse CLOUDKIT_SERVER_PRIVATE_KEY as an unencrypted PEM key. ` +
        `Primary parser failed with: ${primaryError.message}. ` +
        `Fallback parser failed with: ${fallbackError.message}.`
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
  const rows = citiesRaw.split("\n");
  let inserted = 0;

  for (const line of rows) {
    if (!line) {
      continue;
    }

    const columns = line.split("\t");
    if (columns.length < 15) {
      continue;
    }

    const latitude = Number.parseFloat(columns[4]);
    const longitude = Number.parseFloat(columns[5]);
    if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
      continue;
    }

    const countryCode = columns[8];
    const admin1Code = columns[10];
    const cityName = columns[2] || columns[1];
    const regionName = admin1Names.get(`${countryCode}.${admin1Code}`) || admin1Code;
    const countryName = countryNames.get(countryCode) || countryCode;

    const bucketKey = geoBucketKey(latitude, longitude);
    const bucket = buckets.get(bucketKey) || [];
    bucket.push({
      city: cityName,
      region: regionName,
      country: countryName,
      latitude,
      longitude,
      population: Number.parseInt(columns[14], 10) || 0
    });
    buckets.set(bucketKey, bucket);
    inserted += 1;
  }

  console.log(`Loaded GeoNames reverse-geocoding index with ${inserted} cities across ${buckets.size} buckets.`);
  return {
    lookup(lat, lon) {
      return lookupNearestCity(buckets, lat, lon);
    }
  };
}

function inferPlaceComponents(place, reverseGeocoder) {
  if (!reverseGeocoder) {
    return { city: "", region: "", country: "" };
  }

  const latitude = Number.parseFloat(place.lat);
  const longitude = Number.parseFloat(place.lon);
  if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
    return { city: "", region: "", country: "" };
  }

  return reverseGeocoder.lookup(latitude, longitude) || { city: "", region: "", country: "" };
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
          city: candidate.city,
          region: candidate.region,
          country: candidate.country,
          distance,
          population: candidate.population
        };
      }
    }

    if (best) {
      return {
        city: best.city,
        region: best.region,
        country: best.country
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

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
