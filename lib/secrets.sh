#!/usr/bin/env bash
# Credential bundle. Publishable: contains path names only, no identity.

SECRETS_PATHS=(
    .ssh
    .gnupg
    .aws
    .npmrc
    .zsh_secrets
    .docker/config.json
    .config/gh/hosts.yml
    .config/rclone
    .local/share/opencode/auth.json
    .hermes/auth.json
    .boto
    .instagram_session.json
    .oidc_enc_key
    .oidc_rotate.env
    .oculus_identity_cs
    .oculus_oidc_client
)
# gcloud: credentials only, never the multi-megabyte cache.
SECRETS_GLOBS=(
    '.config/gcloud/*.json'
    '.config/gcloud/credentials.db'
    '.config/gcloud/*/*.json'
    # per-context git identity includes; the glob names no one
    '.gitconfig-*'
)

secrets_pack() {
    local home="$1" out="$2" passphrase_file="$3" tmp p
    local old_umask cleanup_code
    old_umask=$(umask)
    umask 077
    tmp=$(mktemp -d) || { umask "$old_umask"; return 1; }
    # Build cleanup code: first remove tmp and restore umask
    cleanup_code="rm -rf '$tmp'; umask $old_umask"
    # Then add any existing trap handlers back (if they exist, eval them; else remove the handler)
    if [[ -n "$(trap -p EXIT 2>/dev/null)" ]]; then
        local orig_exit; orig_exit=$(trap -p EXIT)
        cleanup_code="$cleanup_code; $orig_exit"
    else
        cleanup_code="$cleanup_code; trap - EXIT"
    fi
    if [[ -n "$(trap -p HUP 2>/dev/null)" ]]; then
        local orig_hup; orig_hup=$(trap -p HUP)
        cleanup_code="$cleanup_code; $orig_hup"
    else
        cleanup_code="$cleanup_code; trap - HUP"
    fi
    if [[ -n "$(trap -p INT 2>/dev/null)" ]]; then
        local orig_int; orig_int=$(trap -p INT)
        cleanup_code="$cleanup_code; $orig_int"
    else
        cleanup_code="$cleanup_code; trap - INT"
    fi
    if [[ -n "$(trap -p TERM 2>/dev/null)" ]]; then
        local orig_term; orig_term=$(trap -p TERM)
        cleanup_code="$cleanup_code; $orig_term"
    else
        cleanup_code="$cleanup_code; trap - TERM"
    fi
    # Use RETURN for function-level cleanup, disarm trap after running so it doesn't persist
    cleanup_code="$cleanup_code; trap - RETURN"
    trap "$cleanup_code" RETURN EXIT HUP INT TERM
    local list="$tmp/list"; : > "$list"
    for p in "${SECRETS_PATHS[@]}"; do
        [[ -e "$home/$p" ]] && printf '%s\n' "$p" >> "$list"
    done
    for p in "${SECRETS_GLOBS[@]}"; do
        while read -r f; do
            [[ -e "$home/$f" ]] && printf '%s\n' "$f" >> "$list"
        done < <( cd "$home" && compgen -G "$p" 2>/dev/null )
    done
    [[ -s "$list" ]] || { error "nothing to pack"; return 1; }
    tar -C "$home" --numeric-owner -czf "$tmp/b.tgz" -T "$list" || return 1
    gpg --batch --yes --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
        --passphrase-file "$passphrase_file" --output "$out" "$tmp/b.tgz" || return 1
    [[ -f "$out" ]] || return 1
}

secrets_unpack() {
    local in="$1" home="$2" passphrase_file="$3" tmp cleanup_code
    local old_umask
    [[ -f "$in" ]] || { error "no secrets bundle at $in"; return 1; }
    old_umask=$(umask)
    umask 077
    tmp=$(mktemp -d) || { umask "$old_umask"; return 1; }
    # Build cleanup code: first remove tmp and restore umask
    cleanup_code="rm -rf '$tmp'; umask $old_umask"
    # Then add any existing trap handlers back
    if [[ -n "$(trap -p EXIT 2>/dev/null)" ]]; then
        local orig_exit; orig_exit=$(trap -p EXIT)
        cleanup_code="$cleanup_code; $orig_exit"
    else
        cleanup_code="$cleanup_code; trap - EXIT"
    fi
    if [[ -n "$(trap -p HUP 2>/dev/null)" ]]; then
        local orig_hup; orig_hup=$(trap -p HUP)
        cleanup_code="$cleanup_code; $orig_hup"
    else
        cleanup_code="$cleanup_code; trap - HUP"
    fi
    if [[ -n "$(trap -p INT 2>/dev/null)" ]]; then
        local orig_int; orig_int=$(trap -p INT)
        cleanup_code="$cleanup_code; $orig_int"
    else
        cleanup_code="$cleanup_code; trap - INT"
    fi
    if [[ -n "$(trap -p TERM 2>/dev/null)" ]]; then
        local orig_term; orig_term=$(trap -p TERM)
        cleanup_code="$cleanup_code; $orig_term"
    else
        cleanup_code="$cleanup_code; trap - TERM"
    fi
    # Use RETURN for function-level cleanup, disarm trap after running so it doesn't persist
    cleanup_code="$cleanup_code; trap - RETURN"
    trap "$cleanup_code" RETURN EXIT HUP INT TERM
    gpg --batch --yes --quiet --decrypt --passphrase-file "$passphrase_file" \
        --output "$tmp/b.tgz" "$in" || { error "decryption failed (wrong passphrase?)"; return 1; }
    mkdir -p "$home"
    tar -C "$home" -xzf "$tmp/b.tgz" || return 1
    local d
    for d in .ssh .gnupg .aws; do
        [[ -d "$home/$d" ]] || continue
        chmod 700 "$home/$d"
        find "$home/$d" -type f -exec chmod 600 {} +
    done
    [[ -f "$home/.zsh_secrets" ]] && chmod 600 "$home/.zsh_secrets"
    return 0
}
