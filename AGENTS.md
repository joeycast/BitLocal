## Default Workflow For This Project
- After any code change, automatically run the app in the iOS simulator using `mcp__XcodeBuildMCP__build_run_sim` with simulator ID `03C5F5DD-9BA9-4517-9110-867844323DD3` so the user can test immediately.
- If launch fails, report the build/runtime error and stop for instruction.
- Skip auto-run only when the user explicitly says "no run" or when changes are docs-only.
