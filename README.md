# tdaconf

Arch Linux bootstrapper — i3, zsh, neovim, polybar — in two modes.

Stealth is the **default**. The mode that writes credentials to disk is the one
you have to ask for by name.

```
deploy.sh [--stealth|--full] [--tiers a,b] [--dry-run] [--help]
```

Nothing is installed until you drop `--dry-run`; with it, `deploy.sh` prints the
exact package list, the overlay it would apply and the units it would enable,
and changes nothing.

## Stealth (default)

For labs, throwaway VMs, and machines that are not yours. No credentials, no
identity, no remote-access services. Needs no authentication — the public repo
is public.

```bash
git clone --depth 1 https://github.com/0xresistense/deploy /tmp/d
sudo /tmp/d/deploy.sh
cd / && rm -rf /tmp/d
startx
```

Installs the `lab` tier — 66 packages, all from the official Arch repositories,
so no AUR helper is built and `yay` is never installed. On top of it, the
`profiles/lab/` overlay repoints the captured config at binaries the lab tier
actually ships (`$mod+1` runs `alacritty -e ranger` rather than `thunar`, the
`rofimoji` bind is dropped, dead polybar modules are stripped). A patch that
matches nothing aborts the deploy rather than shipping a keybind that calls a
missing binary.

Stealth also refuses to enable units that open remote ingress or bind the box to
a remote account — `sshd`, `ttyd`, `tailscaled`, `teamviewerd`, `anydesk` — even
if the captured service manifest lists them. It never installs the `personal`
tier under any combination of flags.

## Full

For your own machines. Same tree plus the `desktop` tier, and it decrypts the
credential bundle into `$HOME`.

```bash
git clone <the private repo> /tmp/t
sudo /tmp/t/deploy.sh --full --tiers dev,media
```

`--full` needs `secrets.tar.gz.gpg`, which only exists in the private repo. If
it is missing, the deploy aborts up front, before a single package is
installed — a `--full` run against a public clone fails loudly instead of
quietly producing a half-configured machine with no credentials.

## Tiers

`--tiers` adds to whatever the mode already installs. Stealth's floor is `lab`;
full's is `lab,desktop`.

| tier | contents |
|------|----------|
| `lab` | the whole lab environment: i3, polybar, alacritty, neovim, zsh, librewolf, and the analysis tools |
| `desktop` | the personal rice on top of `lab` — fonts, themes, bluetooth, thunar |
| `dev` | toolchains, containers, cloud CLIs |
| `media` | vlc, gimp, obs |
| `sec` | burpsuite, john, **wine** — opt in deliberately, see below |
| `personal` | accounts and browsers. Never reachable in stealth mode |

Graphics drivers and CPU microcode are not a tier you pick. `deploy.sh` probes
the target with `lspci` and `/proc/cpuinfo` and adds the matching
`packages/hw/` list itself, so the same command works on an NVIDIA desktop and
an Intel laptop.

## Updating from the source machine

```bash
./capture.sh
```

Captures at full fidelity, encrypts the credential stores, then builds and
pushes the scrubbed public tree.

## Warning: the `sec` tier includes wine

A Windows sample run under wine executes on the **host**, as the invoking user,
with that user's filesystem, network and credentials. Wine is a compatibility
layer, not a guest — there is no VM and no isolation boundary between the
sample and the machine you are sitting at.

Do not add `sec` to a lab you intend to detonate samples in unless that is
exactly what you mean to do. For detonation, use a real VM whose disk you can
roll back.
