#!/usr/bin/env bash
# Fork-only: unlock Pro unconditionally in self-built AltTab.
#
# AltTab is GPL, which grants the right to build and run your own copy. Upstream
# gates Pro behind a purchased license + server validation in
# LicenseManager.computeState(). This rewrites that method's *entire body* to
# just `return .pro`, so the self-built fork is always Pro.
#
# Replacing the whole body (rather than inserting an early return) matters: the
# project builds with SWIFT_TREAT_WARNINGS_AS_ERRORS=YES, so leaving the old
# statements after a `return` would be "code will never be executed" -> a hard
# error. This way there is no dead code.
#
# Applied at build time (see .github/workflows/build-dmg.yml) so master stays a
# clean mirror of upstream and the daily sync never conflicts. It edits the
# working tree only; nothing is committed.
#
# Targets the method by signature + brace matching, not a fixed line range, so
# it survives upstream edits elsewhere. If upstream renames/removes
# computeState(), it fails loudly so the build breaks visibly rather than
# silently shipping a locked app.

set -euo pipefail

file="src/pro/license/LicenseManager.swift"
marker="// fork: Pro unlocked unconditionally (GPL self-build)"

if [[ ! -f "$file" ]]; then
  echo "::error::$file not found; upstream may have moved the license code." >&2
  exit 1
fi

if grep -qF "$marker" "$file"; then
  echo "Pro unlock already applied; nothing to do."
  exit 0
fi

if ! grep -qE '^\s*func computeState\(\) -> LicenseState \{' "$file"; then
  echo "::error::Could not find 'func computeState() -> LicenseState {' in $file." >&2
  echo "::error::Upstream likely restructured licensing; update scripts/fork/apply_pro_unlock.sh." >&2
  exit 1
fi

# Replace the body of computeState() with `return .pro`, using brace matching to
# find the method's closing brace (the body contains nested braces).
tmp="$(mktemp)"
awk -v marker="$marker" '
  state == 0 && /^[[:space:]]*func computeState\(\) -> LicenseState \{/ {
    print
    print "        " marker
    print "        return .pro"
    # Count braces from this line onward to find the matching close.
    depth = gsub(/\{/, "{") - gsub(/\}/, "}")
    state = 1
    next
  }
  state == 1 {
    depth += gsub(/\{/, "{") - gsub(/\}/, "}")
    if (depth <= 0) {
      print "    }"   # emit the method close brace, drop everything before it
      state = 2
    }
    next
  }
  { print }
' "$file" > "$tmp"

# Sanity: ensure we actually produced the replacement and didnt mangle the file.
if ! grep -qF "$marker" "$tmp"; then
  echo "::error::Pro unlock transform produced no change; aborting." >&2
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$file"

echo "Applied Pro unlock to $file:"
grep -n -A2 'func computeState() -> LicenseState' "$file"
