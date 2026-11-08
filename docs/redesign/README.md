# BitLocal Redesign

Design and planning package for the combined UI + architecture redesign of BitLocal. **Approved by Joe on 2026-11-08** ("go with your recommendations"). No app code changed.

- [ui-redesign.md](ui-redesign.md): what people see and feel: layout system (bottom sheet / sidebar / inspector by width), map and merchant card, motion, every screen, accessibility. Section 11 records the 6 visible decisions, all approved.
- [architecture-redesign.md](architecture-redesign.md): what it's built from: v4-only Merchant model, SQLite store with R-tree + FTS5, clustering, single navigation model, small @Observable feature models, Swift 6, performance budgets, 8-phase migration plan. Removing the BTC Map v2 fallback is approved (section 15).
- [duo.md](duo.md): iPhone Duo optimization (written with /swiftui-pro, building on PR #51): folded/unfolded postures and seamless fold transitions, the fold as a layout boundary, upright vs sideways layouts, the folded swipeable card row, tap-a-card pin reveal, exact detection APIs with fallbacks, and 21 simulator test cases.

Both were written with the /emil-design-eng skill (Emil Kowalski's design-engineering philosophy). Events are out of scope.

Build progress and every judgment call made while building: [DECISIONS.md](DECISIONS.md).
