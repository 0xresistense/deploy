#!/usr/bin/env bash
# Profile overlays. Publishable — must contain no identity.
# Requires lib/common.sh (warn) to be sourced first.
#
# overlay_apply <profile_dir> <target_home>
#   A plain file in the profile replaces its counterpart under target_home.
#   A NAME.patch file is a `sed -E` script applied in place to NAME; the .patch
#   file itself is never copied into the deployed tree, and neither is the
#   profile's own top-level README.md.
#
# Returns non-zero if the profile is missing or any entry failed to apply,
# INCLUDING a patch that matched nothing. These patches exist to strip binds
# and modules that point at packages the lab tier does not install, so a
# no-op patch is a silent failure that ships a config calling an absent
# binary. Loud is the only safe default here.

overlay_apply() {
    local prof="${1%/}" home="${2%/}" rc=0 f rel target tmpf
    [[ -d "$prof" ]] || { warn "overlay: no such profile: $prof"; return 1; }
    [[ -d "$home" ]] || { warn "overlay: no such target home: $home"; return 1; }
    tmpf=$(mktemp) || { warn "overlay: mktemp failed"; return 1; }

    while IFS= read -r -d '' f; do
        rel="${f#"$prof"/}"
        # The profile's own documentation is not overlay content.
        if [[ "$rel" == "README.md" ]]; then
            continue
        elif [[ "$rel" == *.patch ]]; then
            target="$home/${rel%.patch}"
            if [[ ! -f "$target" ]]; then
                warn "overlay: patch target missing: ${rel%.patch}"; rc=1; continue
            fi
            if ! sed -E -f "$f" "$target" >"$tmpf"; then
                warn "overlay: sed failed: $rel"; rc=1; continue
            fi
            if cmp -s "$tmpf" "$target"; then
                warn "overlay: patch changed nothing: $rel"; rc=1; continue
            fi
            # Write through the existing file: keeps the target's mode.
            if ! cat "$tmpf" >"$target"; then
                warn "overlay: write failed: ${rel%.patch}"; rc=1
            fi
        else
            if ! { mkdir -p "$home/$(dirname "$rel")" && cp -a "$f" "$home/$rel"; }; then
                warn "overlay: copy failed: $rel"; rc=1
            fi
        fi
    done < <(find "$prof" -type f -print0)

    rm -f "$tmpf"
    return "$rc"
}
