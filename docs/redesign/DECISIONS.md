# Redesign build decisions

Joe asked for the redesign to be built autonomously (2026-11-08): make the calls, record them, and he corrects later.
Every judgment call that the specs in this folder don't settle is logged here with the reason, newest phase last.
To overrule one, say which number and what you want instead.

## Phase 1: foundations

1. **Deployment target stays iOS 18.** The specs disagree (`ui-redesign.md` 3.3 has an iOS 18–25 fallback column and `duo.md` 0 says "stays at iOS 18"; an earlier summary said iOS 26). Keeping 18 changes nothing for current users; iOS 26/27.1 APIs go behind `#available`.
2. **One local package, `Packages/BitLocalKit`, with one module per layer** (`BitLocalDomain`, `BitLocalDesign`; `BitLocalData` and feature modules arrive in later phases) instead of separate packages. One product (`BitLocalKit`) linked by the app. Package tests run with `swift test` on macOS in CI, no simulator.
3. **Swift 6 language mode in the package now; the app target stays Swift 5 until phase 8**, as the spec's migration table says.
4. **`MerchantCategory` is a wrapper around the BTC Map v4 `icon` string**, not an enum. The category catalog (`ElementCategorySymbols`, ~1,000 lines with localized labels) stays in the app for now; the domain only needs identity and `isATM`. Moving the catalog into the package needs its strings moved out of the app's string catalog, which is a phase 7/8 job.
5. **`MerchantSummary.name` is never empty and `hasRealName` says whether it is a real name or the category fallback.** The fallback label is supplied by the app (`MerchantMapper.app`) so it stays localized; search must not treat fallback names as name matches (the same rule `Element.displayName` follows today).
6. **`PaymentMethods` gets a fourth flag, `bitcoinUnspecified`**, for places tagged only `payment:bitcoin=yes` / `currency:XBT=yes`. Today's detail screen shows those as "Accepts Bitcoin", and dropping them would hide real merchants' payment info.
7. **Opening hours stay a raw OSM string on `MerchantSummary` in phase 1.** The existing parser in `BusinessHours.swift` is used by the views; it moves into the domain when the detail screen is rebuilt (phase 5).
8. **The two oranges collapse into `#FC780F`** (`AccentColor` and `MarkerColor` assets now match the `BrandColor.brand` token, all sRGB). The hard-coded Featured gold uses `BrandColor.boost`.
9. **Detail rows lose their orange labels now** (icons `.secondary`, labels `.primary`, link values `brandInk`), ahead of the full detail rebuild in phase 5, because it is low-risk polish the spec lists in build step 1.
10. **CI picks Xcode 27.1+ when the runner image has it, otherwise the newest Xcode 26**, and picks the newest plain iPhone simulator instead of a hard-coded name/OS. The Duo-specific APIs (`reservedRegions`, `toolbarVerticalEdge`) can only compile on Xcode 27.1, so they are added once CI shows that toolchain.
