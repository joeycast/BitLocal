# Telemetry decision

**Issue:** [#27](https://github.com/joeycast/BitLocal/issues/27)  
**Date:** 2026-07-16  
**Decision:** **Do not ship product telemetry** for now (no third-party SDKs, no first-party analytics pipeline).

## Context

BitLocal is intentionally:

- Zero external dependencies  
- Privacy-first (When In Use location only)  
- Offline-capable merchant discovery with local caching  

Issue #27 proposed lightweight metrics (cold start, sync success/failure, search zero-result rate) without PII.

## Options

| Option | Pros | Cons |
|--------|------|------|
| **A. None (chosen)** | No privacy/App Store surface area; keeps zero deps; no backend to operate | No production funnel metrics |
| **B. First-party counters** (future) | Controlled schema; can stay on-device or opt-in | Needs careful design, retention, and review |
| **C. Third-party analytics** | Dashboards quickly | Violates zero-deps ethos; privacy nutrition labels; ATT risk if identifiers used |

## Decision

**Ship none.** Rely on:

- Local DEBUG timing (`Debug.logTiming`) for development  
- App Store Connect crash/performance reports for production health  
- User feedback / TestFlight notes for qualitative issues  

Revisit only if a concrete product question cannot be answered without aggregate metrics (e.g. “is cold start >2s for 10% of users?”) **and** we are willing to:

1. Keep zero third-party SDKs  
2. Document data collection in privacy policy / App Privacy labels  
3. Prefer on-device aggregates or explicit opt-in  

## Explicit non-goals (current)

- No query text, merchant IDs, or precise location in any future metric  
- No advertising identifiers  
- No always-on network analytics  

## Follow-up (optional, later)

If metrics become necessary, prefer:

1. DEBUG-only in-app diagnostics export (user-initiated)  
2. Then opt-in first-party counters with documented retention  

Until then, **close #27 as decided: no telemetry.**
