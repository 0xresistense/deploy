#!/usr/bin/env bash

# Serialize concurrent invocations. Two login triggers can call this at once
# (i3 `exec_always` + autorandr `postswitch`); the kill+wait guard below is a
# TOCTOU race across concurrent runs, so both would pass the "nothing running"
# check and each spawn a full per-monitor set -> duplicate bars. flock forces
# them to run one-at-a-time; whichever runs last leaves exactly one set.
# NOTE: the launched polybar processes below MUST close this fd (9>&-), else
# they inherit it and hold the lock for their whole lifetime -> the next run
# (hotplug/resume) blocks forever waiting to kill a bar that owns the lock.
exec 9>/tmp/polybar-launch.lock
flock 9

# Terminate any running polybar and WAIT for it to fully exit before relaunch.
# On i3 reload / login a relaunch races the dying instances; without this wait
# you can end up with duplicate or half-started bars. (This used to also matter
# for the systray selection handoff — the tray is gone now, but the clean
# restart guarantee is still worth keeping.)
polybar-msg cmd quit >/dev/null 2>&1
killall -q polybar
while pgrep -x polybar >/dev/null; do sleep 0.2; done

# Launch one bar per connected monitor.
#   - MONITOR env binds each instance to its output (config: monitor=${env:MONITOR:})
#     and pin-workspaces then shows only that output's workspaces.
#   - The primary output gets the full bar; every other output gets the light
#     `bar-secondary` (workspaces + window + clock only).
#   - `-l error` suppresses the flood of harmless "Dropping unmatched character"
#     warnings (braille spinner glyphs in window titles) that previously grew
#     the log to tens of thousands of lines.
#   - Logs are per-monitor and TRUNCATED each launch (>), never appended, so
#     they can't grow without bound.
primary=$(xrandr --query 2>/dev/null | awk '/ connected primary/{print $1}')

if type xrandr >/dev/null 2>&1; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    if [ "$m" = "$primary" ]; then bar=bar; else bar=bar-secondary; fi
    MONITOR=$m polybar -l error "$bar" 9>&- >"/tmp/polybar-$m.log" 2>&1 & disown
  done
else
  polybar -l error bar 9>&- >/tmp/polybar.log 2>&1 & disown
fi

echo "Bar(s) launched..."
