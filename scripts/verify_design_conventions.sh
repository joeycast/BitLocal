#!/usr/bin/env bash
set -euo pipefail

# BitLocal Design & SwiftUI Convention Guardrails
# Runs fast (<1s) locally and in GitHub Actions to catch design/architecture regressions.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

root = Path(".").resolve()
errors: list[str] = []

excluded_dirs = {".git", ".swiftpm", ".build", ".impeccable", "build", "DerivedData", "bitlocalTests"}

def iter_app_swift_files():
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in excluded_dirs]
        for fname in sorted(filenames):
            if fname.endswith(".swift"):
                yield Path(dirpath) / fname

def strip_comments(line: str, in_block: bool) -> tuple[str, bool]:
    """Strip // and /* */ comments while preserving string literals roughly enough for guardrails."""
    out = []
    i = 0
    n = len(line)
    in_str = False
    while i < n:
        c = line[i]
        nxt = line[i + 1] if i + 1 < n else ""
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 2
            else:
                i += 1
            continue
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(nxt)
                i += 2
            elif c == "\"":
                in_str = False
                i += 1
            else:
                i += 1
            continue
        if c == "/" and nxt == "/":
            break
        if c == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if c == "\"":
            in_str = True
        out.append(c)
        i += 1
    return "".join(out), in_block

# Pattern rules applied to non-comment app Swift code
rules = [
    (
        "no-uiscreen-main",
        re.compile(r"\bUIScreen\.main\b"),
        "Do not use UIScreen.main (breaks iPhone Duo dual displays & iPad resizing). Use container geometry / @Environment(\\.displayScale).",
    ),
    (
        "no-user-interface-idiom",
        re.compile(r"\buserInterfaceIdiom\b"),
        "Do not branch layout on UIDevice.current.userInterfaceIdiom. Use AppLayoutMode / horizontalSizeClass & verticalSizeClass.",
    ),
    (
        "no-view-if-helper",
        re.compile(r"\bfunc\s+if\s*<"),
        "Do not introduce View.if() conditional modifier helpers (creates _ConditionalContent and resets view identity).",
    ),
    (
        "no-dispatch-semaphore",
        re.compile(r"\bDispatchSemaphore\b"),
        "Do not use DispatchSemaphore (main-thread deadlock risk). Use Swift Concurrency (async/await, TaskGroup, actors).",
    ),
    (
        "no-dispatch-queue-main",
        re.compile(r"\bDispatchQueue\.main\b"),
        "Use Task { @MainActor in } / Task.sleep(for:) / RunLoop.main instead of DispatchQueue.main.",
    ),
    (
        "no-dispatch-work-item",
        re.compile(r"\bDispatchWorkItem\b"),
        "Use cancellable Task<Void, Never>? + Task.sleep(for:) instead of DispatchWorkItem.",
    ),
    (
        "no-foreground-color",
        re.compile(r"\.foregroundColor\s*\("),
        "Use .foregroundStyle(...) instead of deprecated .foregroundColor(...).",
    ),
    (
        "no-corner-radius",
        re.compile(r"\.cornerRadius\s*\("),
        "Use .clipShape(.rect(cornerRadius:)) or .background(..., in: .rect(cornerRadius:)) instead of deprecated .cornerRadius(...).",
    ),
    (
        "no-legacy-autocapitalization",
        re.compile(r"\.autocapitalization\s*\("),
        "Use .textInputAutocapitalization(...) instead of deprecated .autocapitalization(...).",
    ),
    (
        "no-legacy-scroll-indicators",
        re.compile(r"showsIndicators\s*:\s*false"),
        "Use .scrollIndicators(.hidden) instead of ScrollView(..., showsIndicators: false).",
    ),
    (
        "no-preview-provider",
        re.compile(r"\bPreviewProvider\b"),
        "Use #Preview macro instead of legacy PreviewProvider.",
    ),
    (
        "no-task-sleep-nanoseconds",
        re.compile(r"Task\.sleep\s*\(\s*nanoseconds\s*:"),
        "Use Task.sleep(for:) with Duration instead of Task.sleep(nanoseconds:).",
    ),
    (
        "no-navigation-view",
        re.compile(r"\bNavigationView\b"),
        "Use NavigationStack or NavigationSplitView instead of deprecated NavigationView.",
    ),
    (
        "no-legacy-toolbar-visibility",
        re.compile(r"\.(toolbar|toolbarBackground)\s*\(\s*\.(hidden|visible)\s*,\s*for\s*:"),
        "Use .toolbarVisibility(_:for:) / .toolbarBackgroundVisibility(_:for:) (iOS 18+) instead of soft-deprecated visibility overloads.",
    ),
    (
        "no-observable-object",
        re.compile(r"\bObservableObject\b|@Published\b|@StateObject\b|@ObservedObject\b|@EnvironmentObject\b|\.environmentObject\s*\("),
        "Use @Observable, @State, @Environment(Type.self), and @Bindable instead of legacy ObservableObject / @Published / @StateObject / @ObservedObject / @EnvironmentObject.",
    ),
]

# Value-based navigation files must not reintroduce destination-closure NavigationLink
value_nav_files = {
    "Businesses/Views/BottomSheetContentView.swift",
    "Businesses/Views/CommunitiesListView.swift",
    "Businesses/Views/CommunityDetailView.swift",
    "Businesses/Views/BusinessDetailView.swift",
    "Businesses/Views/PlaceDescriptionAndReviewsViews.swift",
    "Businesses/Views/EventsDiscoverySection.swift",
}
nav_closure_re = re.compile(r"\bNavigationLink\s*\{")
string_localized_inflect_re = re.compile(r'\bString\s*\(\s*localized\s*:\s*"[^"\n]*inflect\s*:', re.DOTALL)
max_swift_file_lines = 1000

for path in iter_app_swift_files():
    rel = path.relative_to(root).as_posix()
    in_block = False
    line_count = 0
    stripped_lines: list[str] = []
    with path.open("r", encoding="utf-8") as fh:
        for lineno, raw_line in enumerate(fh, start=1):
            line_count = lineno
            code, in_block = strip_comments(raw_line, in_block)
            stripped_lines.append(code)
            if not code.strip():
                continue
            for rule_id, pattern, message in rules:
                if pattern.search(code):
                    errors.append(f"[{rule_id}] {rel}:{lineno}: {message}")
            if rel in value_nav_files and nav_closure_re.search(code):
                errors.append(
                    f"[no-mixed-navigation-link] {rel}:{lineno}: Do not mix NavigationLink {{ ... }} with NavigationStack(path:); use NavigationLink(value: BitLocalNavigationRoute...)."
                )
    joined_code = "".join(stripped_lines)
    for match in string_localized_inflect_re.finditer(joined_code):
        lineno = joined_code.count("\n", 0, match.start()) + 1
        errors.append(
            f"[no-string-localized-inflect] {rel}:{lineno}: String(localized:) does not evaluate ^[...](inflect: true). Use String(AttributedString(localized: ...).characters) or SwiftUI Text(...)."
        )
    if line_count > max_swift_file_lines:
        errors.append(
            f"[no-giant-files] {rel}: {line_count} lines exceeds {max_swift_file_lines}-line ceiling. Split along natural type/extension seams."
        )

# Check Info.plist resizability & launch screen invariants
info_plist = (root / "Info.plist").read_text(encoding="utf-8")
if "<key>UILaunchScreen</key>" not in info_plist:
    errors.append("[info-plist-launch-screen] Info.plist must declare UILaunchScreen.")
if "<key>UIRequiresFullScreen</key>" in info_plist:
    errors.append("[info-plist-resizable] Info.plist must not declare UIRequiresFullScreen (breaks iPhone Duo / iPad multitasking).")

# Check every Swift file in app & bitlocalTests is registered in project.pbxproj
pbxproj = (root / "bitlocal.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
for folder_excluded in [excluded_dirs - {"bitlocalTests"}]:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in folder_excluded]
        for fname in sorted(filenames):
            if fname.endswith(".swift"):
                rel = (Path(dirpath) / fname).relative_to(root).as_posix()
                # Look for filename in PBXFileReference / PBXBuildFile entries
                if fname not in pbxproj:
                    errors.append(
                        f"[pbxproj-unregistered] {rel}: Swift file is not referenced in bitlocal.xcodeproj/project.pbxproj."
                    )

if errors:
    print(f"❌ Design & convention verification failed with {len(errors)} issue(s):\n", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)

print("✅ BitLocal design & convention guardrails passed (0 violations).")
PY
