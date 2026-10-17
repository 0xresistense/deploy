#!/usr/bin/env bash
# Shared logging. Published — must contain no identity.
_RED=$'\033[0;31m'; _GRN=$'\033[0;32m'; _YEL=$'\033[0;33m'; _BLU=$'\033[0;34m'; _NC=$'\033[0m'

_log() {
    local level="$1" color="$2" msg="$3" fd="$4"
    if [[ -t $fd ]]; then
        printf '%s::%s %s\n' "$color" "$_NC" "$msg" >&$fd
    else
        printf '%s: %s\n' "$level" "$msg" >&$fd
    fi
}

info()    { _log "INFO" "$_BLU" "$1" 2; }
warn()    { _log "WARN" "$_YEL" "$1" 2; }
error()   { _log "ERROR" "$_RED" "$1" 2; }
success() { _log "SUCCESS" "$_GRN" "$1" 1; }
die()     { error "$1"; return 1; }
