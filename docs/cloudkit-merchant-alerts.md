# CloudKit Merchant Alerts

BitLocal’s phase 2 merchant alerts use three moving parts:

- The iOS app creates a `CKQuerySubscription` for `CityDigest` records in CloudKit.
- An hourly GitHub Actions workflow runs `scripts/cloudkit_digest_sync.mjs`.
- An external Mac mini keepalive job updates `.github/keepalive.md` once a month so GitHub keeps the scheduled workflow active.

## CloudKit setup

1. In Apple Developer, enable `iCloud` and `Push Notifications` for bundle ID `app.bitlocal.bitlocal`.
2. Create or reuse the container `iCloud.app.bitlocal.bitlocal`.
3. In CloudKit Dashboard, create these public-database record types:
   - `Merchant`
   - `CityDigest`
   - `CityDigestPending`
   - `SyncState`
4. Add queryable fields:
   - `Merchant.locationID`
   - `Merchant.cityKey`
   - `Merchant.createdAt`
   - `Merchant.updatedAt`
   - `CityDigestPending.locationID`
   - `CityDigestPending.cityKey`
   - `CityDigestPending.merchantCreatedAt`
   - `CityDigestPending.timeZoneID`
   - `CityDigest.locationID`
   - `CityDigest.cityKey`
   - `CityDigest.digestWindowEnd`
5. Add these fields:

| Record type | Field | Type |
|---|---|---|
| `Merchant` | `placeID` | String |
| `Merchant` | `locationID` | String |
| `Merchant` | `cityKey` | String |
| `Merchant` | `cityDisplayName` | String |
| `Merchant` | `displayName` | String |
| `Merchant` | `createdAt` | Timestamp |
| `Merchant` | `updatedAt` | Timestamp |
| `Merchant` | `deletedAt` | Timestamp |
| `Merchant` | `sourceHash` | String |
| `Merchant` | `timeZoneID` | String |
| `CityDigest` | `locationID` | String |
| `CityDigest` | `cityKey` | String |
| `CityDigest` | `cityDisplayName` | String |
| `CityDigest` | `deliveryLocalDate` | String |
| `CityDigest` | `digestWindowStart` | Timestamp |
| `CityDigest` | `digestWindowEnd` | Timestamp |
| `CityDigest` | `merchantCount` | Int(64) |
| `CityDigest` | `merchantIDs` | List<String> |
| `CityDigest` | `timeZoneID` | String |
| `CityDigest` | `topMerchantNames` | List<String> |
| `CityDigestPending` | `locationID` | String |
| `CityDigestPending` | `cityKey` | String |
| `CityDigestPending` | `cityDisplayName` | String |
| `CityDigestPending` | `timeZoneID` | String |
| `CityDigestPending` | `merchantID` | String |
| `CityDigestPending` | `merchantName` | String |
| `CityDigestPending` | `merchantCreatedAt` | Timestamp |
| `SyncState` | `incrementalAnchorUpdatedSince` | String |
| `SyncState` | `lastSuccessfulSyncAt` | Timestamp |
| `SyncState` | `lastProcessedDigestWindow` | Timestamp |
| `SyncState` | `bootstrapCompleted` | String |

## GitHub setup

Create these repository secrets:

| Secret | Required | Notes |
|---|---|---|
| `CLOUDKIT_CONTAINER_ID` | Yes | Example: `iCloud.app.bitlocal.bitlocal` |
| `CLOUDKIT_ENVIRONMENT` | Yes | `development` or `production` |
| `CLOUDKIT_DATABASE` | Yes | Use `public` |
| `CLOUDKIT_SERVER_KEY_ID` | Yes | The Key ID shown after creating the CloudKit server-to-server key |
| `CLOUDKIT_SERVER_PRIVATE_KEY` | Yes | The full PEM private key created locally for that server-to-server key |
| `BTCMAP_INITIAL_UPDATED_SINCE` | No | Bootstrap anchor for the very first sync |

The workflow lives at `.github/workflows/cloudkit-digest-sync.yml`. It runs hourly at `:17`, supports manual dispatch with `updated_since`, `override_now_utc`, and `city_key_filter`, and keeps concurrency to one sync at a time.

## Server-to-server key setup

For the GitHub sync job, use a CloudKit **server-to-server key**, not an API token. Apple’s web-services docs describe server-to-server keys as the right auth model for scripts that access the public database directly.

1. Generate a private key locally:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out eckey.pem
```

2. Output the corresponding public key:

```bash
openssl ec -in eckey.pem -pubout
```

3. In CloudKit Console, create a **Server-to-Server Key** for `iCloud.app.bitlocal.bitlocal`.
4. Paste only the public-key payload between `BEGIN PUBLIC KEY` and `END PUBLIC KEY`.
5. Save the key and copy the resulting **Key ID**.
6. Add the GitHub secrets:
   - `CLOUDKIT_SERVER_KEY_ID`
   - `CLOUDKIT_SERVER_PRIVATE_KEY` as the full contents of `eckey.pem`

## Mac mini keepalive

The keepalive script lives at `scripts/repo_keepalive.sh`. The sample `launchd` agent is `scripts/com.bitlocal.repo-keepalive.plist`.

Suggested install steps on the always-on Mac mini:

1. Copy the plist into `~/Library/LaunchAgents/com.bitlocal.repo-keepalive.plist`.
2. Update the sample plist so the script path and repo path point at your local clone, then ensure that clone has push access to `origin`.
3. Load the job with:

```bash
launchctl unload ~/Library/LaunchAgents/com.bitlocal.repo-keepalive.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.bitlocal.repo-keepalive.plist
```

The job runs immediately on load, then every 30 days. It updates `.github/keepalive.md`, commits the timestamp, and pushes to `main`.

## Notes

- The first GitHub sync bootstraps merchant records and sync state without queueing digests.
- Subsequent runs queue newly created merchants into `CityDigestPending` and only create `CityDigest` records once the subscribed city reaches its 8:00 AM local delivery window.
- `locationID` is the canonical join key between the app picker, subscriptions, pending records, and digests. `cityKey` remains as human-readable/debug metadata.
- The iOS app reads those digest records directly from CloudKit when a subscription notification arrives.
