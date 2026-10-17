# lab profile

Applied by `deploy.sh` in stealth mode on top of the base `home/` tree.

The `lab` package tier (`packages/lab.txt`) omits `thunar`, `rofimoji`,
`redshift` and the ProtonVPN tooling, so the captured configs would otherwise
bind keys and bar modules to binaries the target does not have.

| file | what it fixes |
|------|---------------|
| `.config/i3/config.patch` | `$mod+1` repointed from `thunar` to `alacritty -e ranger` (both in the lab tier, and already the idiom used by the `F8` bind); the `$mod+period` `rofimoji` bind deleted |
| `.config/polybar/config.ini.patch` | ` ss protonvpn` and ` ss redshift` removed from `modules-right` |

On redshift: `capture.sh` already strips ` ss redshift` from the bar while
building `home/`, so the tree this overlay is applied to does not currently
contain it and that rule matches nothing today. It is kept because the strip
belongs here, not in `capture.sh` — a tier-specific fix has no business
mutating the captured tree for every mode. **These two mechanisms are
redundant; the one in `capture.sh:152` should go.**

Not patched, deliberately:

- **pulseaudio** — `pipewire`, `pipewire-pulse` and `wireplumber` are all in the
  lab tier, and `pipewire-pulse` provides the PulseAudio API polybar's
  `internal/pulseaudio` module talks to, so `[module/pulseaudio]` stays.

## Mechanism

`NAME.patch` is a `sed -E` script applied in place to `NAME` under the target
home. A plain file replaces its counterpart outright. The `.patch` file itself
is never copied into the deployed tree, and neither is this README.

A patch whose target is missing, or that matches nothing, makes
`overlay_apply` return non-zero rather than pass quietly: the whole point of
this overlay is that the deployed config must not reference absent binaries, so
drift in the base tree has to fail loudly instead of silently shipping a broken
bind.
