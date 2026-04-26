## Default Workflow For This Project
- After changes that affect the iOS app runtime or user experience, run the app in the iOS simulator using `mcp__XcodeBuildMCP__build_run_sim` with simulator ID `840CF0E4-5453-4CD9-90A4-89EE18CA9F00` so the user can test immediately.
- If launch fails, report the build/runtime error and stop for instruction.
- Skip auto-run for docs-only, workflow-only, script-only, test-only, configuration-only, or repository-instruction changes unless the user explicitly asks to run the app.
- Also skip auto-run when the user explicitly says "no run".
