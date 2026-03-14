## Default Workflow For This Project
- After any code change, automatically run the app in the iOS simulator using `mcp__XcodeBuildMCP__build_run_sim` with simulator ID `840CF0E4-5453-4CD9-90A4-89EE18CA9F00` so the user can test immediately.
- If launch fails, report the build/runtime error and stop for instruction.
- Skip auto-run only when the user explicitly says "no run" or when changes are docs-only.
