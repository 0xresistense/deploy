# ~/.zshrc — interactive shell configuration
#
# Section order is load-bearing:
#   - the p10k instant-prompt block must stay first and produce no output
#   - compinit must run before anything that calls compdef (gcloud, openclaw)
#   - PATH must be built before any `command -v` / $+commands probe
#
# Secrets do NOT live here. Put them in ~/.zsh_secrets (mode 0600).

# ---------------------------------------------------------------- 1. instant prompt
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ---------------------------------------------------------------- 2. history
HISTFILE=~/.zsh_history
HISTSIZE=50000          # events kept in memory (bounds what Ctrl+R can find)
SAVEHIST=50000          # events written to HISTFILE; keep >= HISTSIZE

setopt EXTENDED_HISTORY       # record timestamp + duration
setopt SHARE_HISTORY          # sync history across running shells
setopt HIST_IGNORE_ALL_DUPS   # a repeated command keeps only its newest entry
setopt HIST_IGNORE_SPACE      # a leading space keeps a command out of history
setopt HIST_REDUCE_BLANKS     # tidy whitespace before storing
setopt HIST_VERIFY            # expand a !! into the buffer instead of running it

# ---------------------------------------------------------------- 3. completion
autoload -Uz compinit
zmodload zsh/complist
zstyle ':completion:*' menu select=0
zstyle ':completion:*' format '>>> %d'
compinit
_comp_options+=(globdots)     # hidden files are included

# ---------------------------------------------------------------- 4. PATH
export NVM_DIR="$HOME/.config/nvm"

# Resolve nvm's default version's bin directory, following its alias chain
# (default -> lts/* -> lts/krypton -> v24.20.0) without sourcing nvm itself.
# The lazy stubs in section 9 only shim node/npm/npx/yarn/corepack, so without
# this any OTHER global CLI installed there — playwright, upstash, sitegraf —
# would be "command not found" until something happened to load nvm.
_nvm_default_bin() {
  local v="$NVM_DIR/alias/default" i=0
  [[ -r $v ]] || return
  v="$(<$v)"
  while [[ $v != v[0-9]* && $i -lt 5 ]]; do
    [[ -r "$NVM_DIR/alias/$v" ]] || return
    v="$(<"$NVM_DIR/alias/$v")"; (( i++ ))
  done
  [[ -d "$NVM_DIR/versions/node/$v/bin" ]] && print -r -- "$NVM_DIR/versions/node/$v/bin"
}
# `typeset -U` keeps `path` de-duplicated automatically, including for entries
# appended later by tool init snippets, and makes re-sourcing this file idempotent.
typeset -U path PATH

path=(
  # nvm's default node first: ~/.local/bin also carries node/npm/npx (a Hermes
  # install, v26.8.1), and nvm is meant to be the source of truth for node.
  ${$(_nvm_default_bin):-}

  # user binaries — these win over system copies
  $HOME/.local/bin
  $HOME/bin
  $HOME/.local/share/bin
  $HOME/.cargo/bin

  # language / tool managers
  $HOME/.local/share/pnpm
  $HOME/Development/flutter/bin
  $HOME/Development/go/bin          # created on first `go install`

  # per-tool installers
  $HOME/.opencode/bin
  $HOME/.kimi-code/bin
  $HOME/.resend/bin

  # system
  /usr/local/sbin
  /usr/local/bin
  /usr/bin
  /usr/bin/site_perl
  /usr/bin/vendor_perl
  /usr/bin/core_perl

  # pi
  __HOME__/.bun/bin

  $path
)

# ---------------------------------------------------------------- 5. environment
export EDITOR="nvim"
export TERMINAL=alacritty
export CHROME_EXECUTABLE='/sbin/chromium'


export ANDROID_HOME="$HOME/Development/Android/Sdk"
export CAPACITOR_ANDROID_STUDIO_PATH="/sbin/android-studio"
export GOPATH="$HOME/Development/go"
export PNPM_HOME="$HOME/.local/share/pnpm"

# path to a service-account file, not a credential itself

# keep opencode off the Claude Code setup: ignore ~/.claude/skills and
# ~/.agents/skills so it only loads its own ~/.config/opencode/skill tree
export OPENCODE_DISABLE_EXTERNAL_SKILLS=1

# ---------------------------------------------------------------- 6. secrets
[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets

# ---------------------------------------------------------------- 7. aliases & functions
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
[[ -f ~/.zsh_functions ]] && source ~/.zsh_functions

# ---------------------------------------------------------------- 8. prompt
# $fg/$bg/$reset_color for interactive use and for the fallback prompt below.
autoload -U colors && colors

# Fallback prompt, used only if powerlevel10k is missing. p10k overwrites it.
#   [user@hostname]-[~]
#   >>>
PS1="%{$fg[blue]%}%B[%b%{$fg[cyan]%}%n%{$fg[grey]%}%B@%b%{$fg[cyan]%}%m%{$fg[blue]%}%B]-%b%{$fg[blue]%}%B[%b%{$fg[white]%}%~%{$fg[blue]%}%B]%b
%{$fg[cyan]%}%B>>>%b%{$reset_color%} "

[[ -f /usr/share/powerlevel10k/powerlevel10k.zsh-theme ]] && \
  source /usr/share/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ---------------------------------------------------------------- 9. lazy loaders
# nvm costs ~250ms to source. Define stubs instead; the first call to any node
# tool replaces them with the real thing. The `typeset -f` check is the guard
# against FUNCNEST recursion when _load_nvm is absent (e.g. in tool shells) —
# the stub then removes itself and falls through to the real binary on PATH.
# pnpm is deliberately NOT stubbed: it is installed standalone in $PNPM_HOME.
_load_nvm() {
  unset -f nvm node npm npx yarn corepack 2>/dev/null
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
for _c in nvm node npm npx yarn corepack; do
  eval "${_c}() {
    if typeset -f _load_nvm >/dev/null 2>&1; then
      _load_nvm
    else
      unset -f nvm node npm npx yarn corepack 2>/dev/null
    fi
    ${_c} \"\$@\"
  }"
done
unset _c

# idctl completion is generated by the CLI itself (no hand-written function)
command -v idctl >/dev/null && source <(idctl completion zsh)

# ---------------------------------------------------------------- 10. tool integrations
# Google Cloud SDK: PATH, then shell completion.
[[ -f "$HOME/Development/google-cloud-sdk/path.zsh.inc" ]] && \
  source "$HOME/Development/google-cloud-sdk/path.zsh.inc"
[[ -f "$HOME/Development/google-cloud-sdk/completion.zsh.inc" ]] && \
  source "$HOME/Development/google-cloud-sdk/completion.zsh.inc"

[[ -f "$HOME/.openclaw/completions/openclaw.zsh" ]] && \
  source "$HOME/.openclaw/completions/openclaw.zsh"

# claude-mem: if the memory worker isn't up, warm it in the background (detached)
# so the next Claude Code session avoids the cold-start SessionStart hook errors.
if [[ -o interactive ]] && (( $+commands[curl] )); then
  curl -sf http://localhost:37777/health >/dev/null 2>&1 || \
    (~/.local/share/scripts/claude-mem-warm.sh &) >/dev/null 2>&1
fi

# Kiro terminal shell integration
if [[ "$TERM_PROGRAM" == "kiro" ]] && (( $+commands[kiro] )); then
  source "$(kiro --locate-shell-integration-path zsh)"
fi

# ---------------------------------------------------------------- 11. keybindings
bindkey -e

# Home / End
bindkey '^[[7~' beginning-of-line
bindkey '^[[H'  beginning-of-line
bindkey '^[[1~' beginning-of-line
[[ -n "${terminfo[khome]}" ]] && bindkey "${terminfo[khome]}" beginning-of-line
bindkey '^[[8~' end-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[4~' end-of-line
[[ -n "${terminfo[kend]}" ]] && bindkey "${terminfo[kend]}" end-of-line

# Insert / Delete
bindkey '^[[2~' overwrite-mode
bindkey '^[[3~' delete-char

# char left/right: arrows, Ctrl+H, Ctrl+L
bindkey '^[[D'  backward-char      # Left
bindkey '^[[C'  forward-char       # Right
bindkey '^[OD'  backward-char      # Left  (application-cursor mode)
bindkey '^[OC'  forward-char       # Right (application-cursor mode)
bindkey '^H'    backward-char      # Ctrl+H (Ctrl+Shift+H sends the same byte)
bindkey '^L'    forward-char       # Ctrl+L (Ctrl+Shift+L sends the same byte)

# word left/right: Ctrl+arrows, Ctrl+Shift+arrows
bindkey '^[[1;5D' backward-word    # Ctrl+Left
bindkey '^[[1;5C' forward-word     # Ctrl+Right
bindkey '^[[1;6D' backward-word    # Ctrl+Shift+Left
bindkey '^[[1;6C' forward-word     # Ctrl+Shift+Right

# history / misc
bindkey '^[[5~' history-beginning-search-backward   # PageUp
bindkey '^[[6~' history-beginning-search-forward    # PageDown
bindkey '^[[Z'  undo                                # Shift+Tab
bindkey '^[l'   clear-screen                        # Alt+L, since ^L is taken

# Leave a clean exit status for the startup files.
true

# kilo
export PATH=__HOME__/.kilo/bin:$PATH

export KILO_DISABLE_CLAUDE_CODE=1
export KILO_DISABLE_EXTERNAL_SKILLS=1
