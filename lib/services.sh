#!/usr/bin/env bash
# Enabled-unit manifests. Publishable — this file and the manifests it writes
# are committed to a public repo, so no identity may be spelled out here.
#
# The identity patterns therefore live in lib/guard.sh (private, excluded from
# config.public.conf) as GUARD_IDENTITY_RE, and are reused rather than repeated.
# Writing the employer's unit prefix into this file instead would leak it, and
# guard_identity would correctly refuse the push — verified: with the prefix
# inline, guard_identity flags lib/services.sh in the built public tree.
# services_capture requires GUARD_IDENTITY_RE and fails closed without it, so a
# capture can never quietly record identity-bearing units.

# Units that open remote ingress (sshd, ttyd) or bind the machine to remote
# accounts (tailscale, teamviewer, anydesk). In a malware lab those are
# exfiltration paths and an attack surface, so stealth refuses them regardless
# of what the manifest says. Full mode keeps them. When GUARD_IDENTITY_RE is in
# scope it is appended, so identity units are refused at enable time too; the
# manifests cannot contain any, because services_capture already stripped them.
SERVICES_STEALTH_DENY='(tailscaled|teamviewerd|anydesk|sshd|ttyd)'

# `systemctl --user` must talk to the invoking human's manager, not root's.
# capture.sh and deploy.sh can both run under sudo (EUID 0 with SUDO_USER set),
# where a plain `systemctl --user` would silently read and write root's units —
# capturing an empty manifest or enabling nothing while reporting success.
_services_user_ctl() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" systemctl --user "$@"
    else
        systemctl --user "$@"
    fi
}

# _services_manifest <file> <ctl-command...>
# Writes the identity-filtered enabled unit names to <file>, one per line.
# Returns systemctl's own exit status, captured separately from its output, so
# an empty manifest can only ever mean "nothing was enabled" and never "we
# could not look". stderr is discarded, never folded into the data: systemd
# warns on stderr while exiting 0, and such a line would become a bogus unit.
_services_manifest() {
    local file="$1"; shift
    local out rc
    out=$("$@" list-unit-files --state=enabled --no-pager --no-legend 2>/dev/null); rc=$?
    (( rc == 0 )) || return "$rc"
    # Prove the destination is writable before claiming the capture succeeded;
    # the pipeline below would otherwise fail into a discarded exit status.
    : > "$file" || { error "cannot write $file"; return 1; }
    # `--state=enabled` excludes enabled-runtime, which is transient and must
    # not be persisted. NF drops the blank line an empty $out here-string makes.
    # -i mirrors guard_identity's own matching.
    awk 'NF {print $1}' <<<"$out" | grep -viE "$GUARD_IDENTITY_RE" | sort -u > "$file"
    return 0
}

# services_capture <outdir> — record enabled system and user units.
services_capture() {
    local out="$1"
    # Fail closed: without the pattern this would write identity units into a
    # tree that is about to be published.
    [[ -n "${GUARD_IDENTITY_RE:-}" ]] || {
        error "GUARD_IDENTITY_RE unset — source lib/guard.sh before capturing"; return 1; }
    mkdir -p "$out" || { error "cannot create $out"; return 1; }

    # A missing systemctl needs no separate check: the listing exits 127 and
    # fails closed here, so an empty manifest is never mistaken for success.
    _services_manifest "$out/system.txt" systemctl \
        || { error "could not list enabled system units"; return 1; }

    # A capture run over ssh or inside a container has no user bus. That is a
    # legitimate scenario, so it warns and leaves user.txt empty rather than
    # failing the whole capture — but it is never silent about it.
    _services_manifest "$out/user.txt" _services_user_ctl \
        || { warn "no user systemd bus — user.txt left empty"; : > "$out/user.txt"; }
    return 0
}

# _services_enable_file <manifest> <mode> <dry> <deny-re> <ctl-command...>
_services_enable_file() {
    local file="$1" mode="$2" dry="$3" deny="$4"; shift 4
    [[ -f "$file" ]] || return 0
    local u
    # `|| [[ -n "$u" ]]` keeps the last line of a manifest that has no trailing
    # newline; plain `read` returns 1 there and the unit would be dropped.
    while IFS= read -r u || [[ -n "$u" ]]; do
        [[ -n "$u" ]] || continue
        if [[ "$mode" == stealth ]] && grep -qiE "$deny" <<<"$u"; then
            # info writes to stderr, so refusals stay out of the stdout stream
            # callers parse.
            info "stealth: refusing $u"
            continue
        fi
        if [[ "$dry" == "--dry-run" ]]; then
            printf 'would enable %s\n' "$u"
        else
            # A manifest unit whose package is not installed in this mode is
            # expected, not fatal: deploy.sh runs under `set -e`, so warning
            # per unit beats aborting a deploy over one absent service.
            "$@" enable "$u" >/dev/null 2>&1 || warn "could not enable $u"
        fi
    done < "$file"
}

# services_enable <dir> <mode> [--dry-run]
# No-op returning 0 when the manifests are absent, so a deploy against a tree
# with no services/ does not fail.
services_enable() {
    local dir="$1" mode="$2" dry="${3:-}"
    case "$mode" in
        stealth|full) ;;
        # An unrecognised mode must not fall through to full-mode behaviour:
        # a typo would silently enable tailscaled in a malware lab.
        *) error "unknown mode: $mode"; return 1 ;;
    esac
    [[ -z "$dry" || "$dry" == "--dry-run" ]] || { error "unknown flag: $dry"; return 1; }

    # ERE alternation of two groups; the identity half is only present in the
    # private tree, where guard.sh is sourced.
    local deny="$SERVICES_STEALTH_DENY${GUARD_IDENTITY_RE:+|$GUARD_IDENTITY_RE}"

    # System units need root; $SUDO is deploy.sh's existing convention and is
    # empty when already root. Without it every enable fails on a non-root run
    # and the deploy reports success having enabled nothing.
    local -a sysctl=(systemctl)
    [[ -n "${SUDO:-}" ]] && sysctl=("${SUDO}" systemctl)

    _services_enable_file "$dir/system.txt" "$mode" "$dry" "$deny" "${sysctl[@]}"
    _services_enable_file "$dir/user.txt"   "$mode" "$dry" "$deny" _services_user_ctl
    return 0
}
