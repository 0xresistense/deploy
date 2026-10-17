#!/usr/bin/env bash
# Tier resolution. Publishable.
PACKAGES_DIR="${PACKAGES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages}"

packages_resolve() {
    local tiers="$1" t
    for t in ${tiers//,/ }; do
        [[ -f "$PACKAGES_DIR/$t.txt" ]] || { error "unknown tier: $t"; return 1; }
    done
    for t in ${tiers//,/ }; do
        grep -vE '^[[:space:]]*(#|$)' "$PACKAGES_DIR/$t.txt"
    done | sort -u
}

packages_verify() {
    local dir="$1" all classified dupes missing rc=0
    # Capture pacman output without merging stderr, check its exit status
    local raw_all
    raw_all=$(pacman -Qqe 2>/dev/null) || { error "pacman -Qqe failed"; return 1; }
    all=$(printf '%s\n' "$raw_all" | sort -u)
    # Union top-level tiers with hw/ tiers; hw/ files don't create cross-tier duplicates
    # Only include hw/ files if directory exists
    local raw_classified
    if [[ -d "$dir/hw" ]]; then
        raw_classified=$(cat "$dir"/*.txt "$dir"/hw/*.txt 2>/dev/null) || { error "failed to read tier files"; return 1; }
    else
        raw_classified=$(cat "$dir"/*.txt 2>/dev/null) || { error "failed to read tier files"; return 1; }
    fi
    classified=$(printf '%s\n' "$raw_classified" | grep -vE '^[[:space:]]*(#|$)' | sort)
    # Check for duplicates only within top-level tiers (hw/ duplicates like mesa are acceptable)
    local raw_dupes
    raw_dupes=$(cat "$dir"/*.txt 2>/dev/null) || { error "failed to read tier files"; return 1; }
    dupes=$(printf '%s\n' "$raw_dupes" | grep -vE '^[[:space:]]*(#|$)' | sort | uniq -d)
    [[ -n "$dupes" ]] && { error "in more than one tier: $(tr '\n' ' ' <<<"$dupes")"; rc=1; }
    missing=$(comm -13 <(sort -u <<<"$classified") <(printf '%s\n' "$all"))
    [[ -n "$missing" ]] && { error "installed but unclassified: $(tr '\n' ' ' <<<"$missing")"; rc=1; }
    return $rc
}

packages_lab_is_official() {
    local dir="$1" aur bad rc err_file
    [[ -f "$dir/lab.txt" ]] || { error "lab.txt not found"; return 1; }
    # Capture pacman output and stderr separately to distinguish "no results" from "error"
    err_file=$(mktemp) || return 1
    local raw_aur
    raw_aur=$(pacman -Qqm 2>"$err_file"); rc=$?
    # If exit non-zero AND stderr has content, it's a real error
    if (( rc != 0 )) && [[ -s "$err_file" ]]; then
        error "pacman -Qqm failed: $(cat "$err_file")"; rm -f "$err_file"; return 1
    fi
    rm -f "$err_file"
    # Exit 1 with empty stderr means no foreign packages (legitimate), treat as success
    aur=$(printf '%s\n' "$raw_aur" | sort -u)
    [[ -z "$aur" ]] && return 0
    bad=$(comm -12 <(sort -u <"$dir/lab.txt") <(printf '%s\n' "$aur")) || { error "failed to compare AUR packages"; return 1; }
    [[ -z "$bad" ]] && return 0
    error "lab tier requires AUR packages: $(tr '\n' ' ' <<<"$bad")"; return 1
}
