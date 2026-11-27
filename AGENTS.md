## Default Workflow For This Project
- After changes that affect the iOS app runtime or user experience, run the app in the iOS simulator using `mcp__XcodeBuildMCP__build_run_sim` with simulator ID `840CF0E4-5453-4CD9-90A4-89EE18CA9F00` so the user can test immediately.
- If launch fails, report the build/runtime error and stop for instruction.
- Skip auto-run for docs-only, workflow-only, script-only, test-only, configuration-only, or repository-instruction changes unless the user explicitly asks to run the app.
- Also skip auto-run when the user explicitly says "no run".

## Design Guidelines & Feature Verifiability
- Follow [`DESIGN.md`](DESIGN.md) for visual tokens, typography, adaptive iPhone/iPad/iPhone Duo layout, translucent materials, `BitLocalMotion`, and accessibility floors (`>= 44x44pt` hit targets, Dynamic Type, Reduce Motion, VoiceOver labels).
- Every new feature or bug fix should be verifiable: add or update unit tests in `bitlocalTests/` (registered in `bitlocal.xcodeproj/project.pbxproj`), update the Feature Verification Matrix in [`docs/VERIFICATION.md`](docs/VERIFICATION.md), and add or update a Maestro flow in `bitlocal-maestro/` when adding new user journeys.
- Run `./scripts/verify_design_conventions.sh` before finishing code changes to catch SwiftUI/resizability/project-registration regressions early (also enforced in CI).
