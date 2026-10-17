#!/usr/bin/env bash
# tdaconf deploy — bootstrap a fresh Arch Linux install
# Usage: git clone <repo> /tmp/tdaconf && /tmp/tdaconf/deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$SCRIPT_DIR/home"

# Detect actual user home even when run with sudo
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    REAL_USER="$(whoami)"
    REAL_HOME="$HOME"
fi
TARGET_HOME="${TARGET_HOME:-$REAL_HOME}"

# Logging comes from lib/common.sh and is NOT redefined here. Its info/warn/
# error write to stderr on purpose: lib/services.sh prints its dry-run plan on
# stdout and relies on log lines staying out of that stream.
LIB="$SCRIPT_DIR/lib"
source "$LIB/common.sh"
source "$LIB/packages.sh"
source "$LIB/hwprobe.sh"
source "$LIB/secrets.sh"
source "$LIB/overlay.sh"
source "$LIB/services.sh"

_BOLD=$'\033[1m'
header() { printf '\n%s%s==> %s%s\n' "$_BOLD" "$_BLU" "$1" "$_NC"; }

MODE=stealth
TIERS=""
DRY=""
SECRETS_BUNDLE="${SECRETS_BUNDLE:-$SCRIPT_DIR/secrets.tar.gz.gpg}"

usage() {
    cat <<'EOF'
deploy.sh - Arch Linux bootstrapper

  --stealth        no credentials, no identity, lab tier only (DEFAULT)
  --full           restore credentials from the encrypted bundle
  --tiers a,b      extra package tiers (lab desktop dev media sec personal)
  --dry-run        print what would happen, change nothing
  --help

Stealth is the default: the mode that writes credentials is the one you
must ask for. Stealth never installs the personal tier and refuses to
enable remote-access or network-identity services.

WARNING: the `sec` tier includes wine. A Windows sample run under wine
executes on THIS host as you, not inside a guest. Do not add `sec` to a
lab unless that is what you intend.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)    MODE=full;    shift ;;
            --stealth) MODE=stealth; shift ;;
            --tiers)
                [[ $# -ge 2 ]] || { error "--tiers needs a comma-separated value"; exit 1; }
                TIERS="$2"; shift 2 ;;
            --dry-run) DRY=1;        shift ;;
            --help|-h) usage; exit 0 ;;
            *) error "unknown argument: $1"; usage >&2; exit 1 ;;
        esac
    done
}

# Tier selection applies to BOTH modes. Stealth's floor is lab alone; full adds
# desktop. Anything named with --tiers is appended to that floor, so
# `--tiers sec` on a stealth run is possible but never accidental.
resolve_tiers() {
    local t="lab" x
    [[ "$MODE" == full ]] && t="lab,desktop"
    [[ -n "$TIERS" ]] && t="$t,$TIERS"
    # The personal tier is accounts, browsers and remote-access clients - the
    # identity stealth exists to leave behind. --tiers reaching it would make
    # "stealth never installs personal" a claim the flags can quietly break,
    # so it is refused outright rather than honoured.
    for x in ${t//,/ }; do
        if [[ "$x" == personal && "$MODE" == stealth ]]; then
            error "stealth mode will not install the personal tier - use --full"
            return 1
        fi
    done
    printf '%s' "$t"
}

# Full mode must abort rather than half-succeed: a public clone has no bundle,
# and a "full" deploy that silently skipped the credentials would look like it
# worked. Checked before the dry-run short-circuit so --dry-run reports it too.
restore_secrets() {
    if [[ ! -f "$SECRETS_BUNDLE" ]]; then
        error "no secrets bundle at $SECRETS_BUNDLE - full mode needs the private repo"
        return 1
    fi
    if [[ -n "$DRY" ]]; then
        info "would decrypt the secrets bundle into $TARGET_HOME"
        return 0
    fi

    header "Restoring credentials"
    local pass rc=0
    read -r -s -p "passphrase: " pass || { error "no passphrase given"; return 1; }
    printf '\n' >&2
    # Process substitution, not a temp file: the passphrase never touches disk.
    secrets_unpack "$SECRETS_BUNDLE" "$TARGET_HOME" <(printf '%s' "$pass") || rc=$?
    pass=""
    (( rc == 0 )) || return "$rc"

    # Unpacked as root under sudo, these land root-owned and ssh/gpg refuse
    # them. deploy_configs' chown ran earlier and cannot cover this.
    if [[ -n "${SUDO_USER:-}" ]]; then
        local p
        for p in "${SECRETS_PATHS[@]}" "${SECRETS_GLOBS[@]%/*}"; do
            if [[ -e "$TARGET_HOME/$p" ]]; then
                chown -R "$REAL_USER:$REAL_USER" "$TARGET_HOME/$p" || warn "could not chown $p"
            fi
        done
    fi
    success "credentials restored"
}

# Check we're on Arch
check_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        error "this script is for Arch Linux only"
        exit 1
    fi
}

# Check sudo access
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            info "running via sudo — deploying configs to $TARGET_HOME (user: $REAL_USER)"
        else
            warn "running as root directly — configs will deploy to $TARGET_HOME"
        fi
        SUDO=""
    else
        if ! sudo -v 2>/dev/null; then
            error "need sudo access to install packages"
            exit 1
        fi
        SUDO="sudo"
    fi
}

# Install yay (AUR helper)
install_yay() {
    header "Installing yay"

    if command -v yay &>/dev/null; then
        info "yay already installed"
        return 0
    fi

    info "building yay from AUR..."
    local yay_dir="/tmp/yay-install"
    rm -rf "$yay_dir"

    # makepkg can't run as root — must run as the actual user
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$REAL_USER" bash -c "
            git clone https://aur.archlinux.org/yay.git '$yay_dir' &&
            cd '$yay_dir' &&
            makepkg -si --noconfirm
        "
    else
        git clone https://aur.archlinux.org/yay.git "$yay_dir"
        cd "$yay_dir" && makepkg -si --noconfirm
        cd "$SCRIPT_DIR"
    fi

    rm -rf "$yay_dir"

    if command -v yay &>/dev/null; then
        success "yay installed"
    else
        warn "yay installation failed — AUR packages will be skipped"
    fi
}

# Install the resolved package list. The flat package manifest this used to
# read is gone; the list now arrives as one newline-separated argument built
# by packages_resolve plus the hardware probe.
# yay is used when present because the desktop/dev/personal tiers contain AUR
# packages; stealth's lab tier is entirely official, so pacman alone suffices.
install_tiers() {
    header "Installing packages"

    local packages=()
    # awk 'NF' first: a here-string of an empty list yields one EMPTY element,
    # so the count guard below would pass and pacman would be handed ''.
    mapfile -t packages < <(printf '%s\n' "$1" | awk 'NF')
    [[ ${#packages[@]} -gt 0 ]] || { error "no packages resolved"; exit 1; }

    info "installing ${#packages[@]} packages..."

    if command -v yay &>/dev/null; then
        # yay handles both official repos and AUR, and must not run as root.
        if [[ $EUID -eq 0 ]]; then
            sudo -u "$REAL_USER" yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake --ask 4 "${packages[@]}" \
                || warn "some packages failed"
        else
            yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake --ask 4 "${packages[@]}" \
                || warn "some packages failed"
        fi
    else
        $SUDO pacman -S --needed --noconfirm "${packages[@]}" \
            || warn "some packages failed - AUR packages need yay"
    fi

    success "packages installed"
}

# Install powerlevel10k
# Always git clone to /usr/share/powerlevel10k/ — the Arch pacman package
# installs to a different path that doesn't match .zshrc's source line
install_p10k() {
    header "Installing powerlevel10k"

    local p10k_dir="/usr/share/powerlevel10k"

    if [[ -d "$p10k_dir" ]]; then
        info "powerlevel10k already installed at $p10k_dir"
        return 0
    fi

    info "cloning powerlevel10k..."
    $SUDO git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"

    success "powerlevel10k installed"
}

# Deploy config files
deploy_configs() {
    header "Deploying configs"

    if [[ ! -d "$HOME_DIR" ]]; then
        error "home/ directory not found — run capture.sh first"
        exit 1
    fi

    # Backup existing configs
    local backup_dir="$TARGET_HOME/.tdaconf-backup-$(date +%Y%m%d-%H%M%S)"
    info "backing up existing configs to $backup_dir"
    mkdir -p "$backup_dir"

    # Find what would be overwritten and back it up
    while IFS= read -r -d '' file; do
        local rel="${file#$HOME_DIR/}"
        local target="$TARGET_HOME/$rel"
        if [[ -e "$target" ]]; then
            local backup_path="$backup_dir/$rel"
            mkdir -p "$(dirname "$backup_path")"
            cp -a "$target" "$backup_path"
        fi
    done < <(find "$HOME_DIR" -type f -print0)

    # Check if backup is empty (nothing to back up)
    if [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        rmdir "$backup_dir" 2>/dev/null || true
        info "no existing configs to back up"
    else
        success "backup saved to $backup_dir"
    fi

    # Deploy with rsync
    rsync -a --checksum "$HOME_DIR/" "$TARGET_HOME/"

    # Fix ownership if run via sudo (rsync as root makes files root-owned)
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "$REAL_USER:$REAL_USER" "$TARGET_HOME/.config" "$TARGET_HOME/.local" \
            "$TARGET_HOME/.zshrc" "$TARGET_HOME/.zsh_aliases" "$TARGET_HOME/.zsh_functions" \
            "$TARGET_HOME/.profile" "$TARGET_HOME/.xprofile" "$TARGET_HOME/.xinitrc" \
            "$TARGET_HOME/.tmux.conf" "$TARGET_HOME/.p10k.zsh" "$TARGET_HOME/.gitconfig" 2>/dev/null || true
        info "fixed file ownership for $REAL_USER"
    fi

    success "configs deployed to $TARGET_HOME"
}

# Expand __HOME__ placeholder in all deployed files
expand_placeholders() {
    header "Expanding placeholders"

    local count=0
    while IFS= read -r -d '' file; do
        # Skip binary files
        if file "$file" | grep -qv text; then
            continue
        fi

        if grep -q '__HOME__' "$file" 2>/dev/null; then
            sed -i "s|__HOME__|$TARGET_HOME|g" "$file"
            count=$((count + 1))
        fi
    done < <(find "$TARGET_HOME/.config" "$TARGET_HOME/.local" \
        "$TARGET_HOME/.zshrc" "$TARGET_HOME/.zsh_aliases" \
        "$TARGET_HOME/.zsh_functions" "$TARGET_HOME/.profile" \
        "$TARGET_HOME/.xprofile" "$TARGET_HOME/.xinitrc" \
        "$TARGET_HOME/.tmux.conf" "$TARGET_HOME/.p10k.zsh" \
        "$TARGET_HOME/.gitconfig" \
        -type f -print0 2>/dev/null)

    info "expanded placeholders in $count files"
}

# Set zsh as default shell
set_default_shell() {
    header "Setting default shell"

    local zsh_path
    zsh_path="$(which zsh 2>/dev/null || echo /usr/bin/zsh)"

    if [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" == "$zsh_path" ]]; then
        info "zsh is already the default shell for $REAL_USER"
        return 0
    fi

    chsh -s "$zsh_path" "$REAL_USER"
    success "default shell set to zsh for $REAL_USER"
}

# Make scripts executable
fix_permissions() {
    header "Fixing permissions"

    local script_dirs=(
        "$TARGET_HOME/.local/share/scripts"
        "$TARGET_HOME/.local/share/bin"
        "$TARGET_HOME/bin"
    )

    for dir in "${script_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            chmod +x "$dir"/* 2>/dev/null || true
            info "made scripts executable in $dir"
        fi
    done
}

# Install VPN leak protection (NM dispatcher script)
install_vpn_leakguard() {
    header "Installing VPN leak guard"

    local src="$SCRIPT_DIR/system/99-vpn-leakguard"
    local dest="/etc/NetworkManager/dispatcher.d/99-vpn-leakguard"

    if [[ ! -f "$src" ]]; then
        warn "vpn-leakguard script not found — skipping"
        return 0
    fi

    $SUDO cp "$src" "$dest"
    $SUDO chmod 755 "$dest"
    $SUDO chown root:root "$dest"

    success "VPN leak guard installed (DNS + IPv6 + kill switch)"
}

# Print summary
print_summary() {
    printf '\n%s%s=== Deploy complete (%s) ===%s\n\n' "$_BOLD" "$_GRN" "$MODE" "$_NC"
    echo "  Configs deployed to $TARGET_HOME; anything overwritten was backed up first."
    if [[ "$MODE" == stealth ]]; then
        echo "  Lab tier: no credentials written, no identity, no remote-access services."
    else
        echo "  Credentials restored from the encrypted bundle."
    fi
    echo
    echo "  Next:"
    echo "    1. Log out and back in (or run: exec zsh)"
    echo "    2. Open nvim - lazy.nvim will auto-install plugins"
    if [[ "$MODE" == stealth ]]; then
        echo "    3. Set a git identity only if you actually want one on this box"
    else
        echo "    3. Set up VPN: $SCRIPT_DIR/vpn-setup.sh <ovpn-user> <ovpn-pass>"
    fi
    echo
}

# Main
main() {
    parse_args "$@"
    info "mode: $MODE"

    # Fail before touching anything. restore_secrets checks this too, but it
    # runs after packages and configs are already written, and a --full run
    # against a public clone aborting there is exactly the half-success this
    # mode must never produce.
    if [[ "$MODE" == full && ! -f "$SECRETS_BUNDLE" ]]; then
        error "no secrets bundle at $SECRETS_BUNDLE - full mode needs the private repo"
        exit 1
    fi

    local tiers pkgs gpu hwfile
    tiers=$(resolve_tiers) || exit 1
    info "tiers: $tiers"
    pkgs=$(packages_resolve "$tiers") || exit 1

    gpu=$(hw_tier)
    hwfile="$SCRIPT_DIR/packages/hw/$gpu.txt"
    if [[ -n "$gpu" && -f "$hwfile" ]]; then
        info "hardware tier: $gpu"
        pkgs+=$'\n'"$(grep -vE '^[[:space:]]*(#|$)' "$hwfile")"
    else
        info "hardware tier: none detected"
    fi
    pkgs+=$'\n'"$(hw_ucode)"
    # awk 'NF', not grep -v: an absent hw tier or microcode leaves a blank line,
    # and grep exits 1 on an all-blank input, which pipefail would turn into a
    # silent abort.
    pkgs=$(printf '%s\n' "$pkgs" | awk 'NF' | sort -u)

    if [[ -n "$DRY" ]]; then
        info "would install $(printf '%s\n' "$pkgs" | wc -l) packages:"
        printf '%s\n' "$pkgs" | tr '\n' ' '; echo
        if [[ "$MODE" == full ]]; then restore_secrets || exit 1; fi
        info "would deploy configs to $TARGET_HOME"
        if [[ "$MODE" == stealth ]]; then info "would apply the profiles/lab overlay"; fi
        services_enable "$SCRIPT_DIR/services" "$MODE" --dry-run
        exit 0
    fi

    check_arch
    check_sudo
    if [[ "$MODE" == full ]]; then install_yay; fi
    install_tiers "$pkgs"
    install_p10k
    deploy_configs
    expand_placeholders
    if [[ "$MODE" == stealth ]]; then
        header "Applying lab overlay"
        # overlay_apply fails on a patch that matched nothing. That is not
        # pedantry: the overlay exists to unbind configs from packages the lab
        # tier does not install, so a no-op means a deployed config still calls
        # an absent binary.
        overlay_apply "$SCRIPT_DIR/profiles/lab" "$TARGET_HOME" || {
            error "lab overlay failed - deployed config may reference packages the lab tier does not install"
            exit 1
        }
        success "lab overlay applied"
    fi
    if [[ "$MODE" == full ]]; then restore_secrets || exit 1; fi
    set_default_shell
    fix_permissions
    if [[ "$MODE" == full ]]; then install_vpn_leakguard; fi
    services_enable "$SCRIPT_DIR/services" "$MODE"
    print_summary
}

main "$@"
