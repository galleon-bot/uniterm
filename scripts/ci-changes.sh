#!/usr/bin/env bash
set -euo pipefail

build_required=true
event="${GITHUB_EVENT_NAME:-}"
base="${BASE_SHA:-}"
head="${HEAD_SHA:-}"

# Unknown or unavailable history must never suppress the build.
if [[ "$event" == pull_request || "$event" == push ]] &&
  [[ "$base" =~ ^[[:xdigit:]]{40}$ && "$head" =~ ^[[:xdigit:]]{40}$ ]] &&
  [[ "$base" != 0000000000000000000000000000000000000000 ]]; then
  revisions=("$base" "$head")
  if [[ "$event" == pull_request ]]; then
    revisions=("$base...$head")
  fi

  changed_paths="$(mktemp)"
  trap 'rm -f "$changed_paths"' EXIT

  # Treat a rename as a deletion and an addition so code renamed to Markdown still builds.
  if git diff --no-ext-diff --no-textconv --no-renames --name-only -z \
    "${revisions[@]}" -- >"$changed_paths"; then
    saw_change=false
    only_docs=true

    while IFS= read -r -d '' path; do
      saw_change=true
      # Markdown in app resources or bundled licenses remains a build input.
      if [[ "$path" == spec/*.md ]] || [[ "$path" != */* && "$path" == *.md ]]; then
        continue
      fi

      only_docs=false
      break
    done <"$changed_paths"

    if [[ "$saw_change" == true && "$only_docs" == true ]]; then
      build_required=false
    fi
  else
    echo "Could not compare revisions; running full CI." >&2
  fi
fi

echo "build_required=$build_required"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'build_required=%s\n' "$build_required" >>"$GITHUB_OUTPUT"
fi
