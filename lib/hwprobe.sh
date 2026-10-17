#!/usr/bin/env bash
# Pick a hardware tier from the target's actual hardware. Publishable.
hw_tier() {
    command -v lspci >/dev/null 2>&1 || return 0
    if   lspci | grep -qi 'vga.*nvidia';     then printf 'nvidia-580xx'
    elif lspci | grep -qiE 'vga.*(amd|ati)'; then printf 'amd'
    elif lspci | grep -qi 'vga.*intel';      then printf 'intel'
    fi
}

hw_ucode() {
    if   grep -q GenuineIntel /proc/cpuinfo; then printf 'intel-ucode'
    elif grep -q AuthenticAMD /proc/cpuinfo; then printf 'amd-ucode'
    fi
}
