# dp-wake

Auto-fix for DisplayPort outputs that go missing after a cold boot on a
laptop + Thunderbolt-dock combo.

## The problem

After a full power-off and back on (not suspend — actual `shutdown` followed
by power-up), external monitors plugged through a Thunderbolt dock are gone:

- The desktop only shows the internal laptop panel.
- `xrandr` doesn't list the external outputs at all.
- The monitors themselves remain in sleep mode and never wake.

Looking at the kernel side:

```
$ for c in /sys/class/drm/card*-DP-*; do
    echo "$(basename $c): $(cat $c/status)"
  done
card0-DP-1: disconnected
card0-DP-2: disconnected
```

The kernel sees the DisplayPort connectors exist but reports them as
**disconnected** — even though the monitors are physically plugged in and
were working fine before the reboot.

## Why it happens

DisplayPort uses **hot-plug detect (HPD)** — a signal asserted by the
attached sink (monitor or dock) to tell the GPU "something is here". When
the laptop powers off, the dock can drop the DP link to its downstream
monitors. On power-up, the dock doesn't always re-assert HPD until
something forces it (replugging the cable, replugging the dock, or
explicitly telling the kernel to re-probe).

Mechanically: the laptop's `+5V_AUX` and dock-power-rail sequencing on cold
boot is different from what happens on resume-from-suspend, and on some
laptop/dock pairs the dock ends up in a state where the DP TX side is up
but it never sends a new HPD pulse to the host.

This was observed on:

- **Laptop:** MSI GS66 Stealth 10SF (NVIDIA RTX 2070 Max-Q, hybrid GPU)
- **Dock:** Lenovo ThinkPad Thunderbolt 3 Dock (40AN)
- **OS:** Ubuntu 24.04, kernel 7.0.0-15-generic, NVIDIA 595.58.03, GNOME on Wayland

But the underlying mechanism is generic to DP + TBT docks and the fix
applies broadly.

## The fix

Write `detect` into the connector's sysfs status file. That asks the DRM
layer to re-run hot-plug detection on the connector. If the cable is in
fact attached, EDID is read fresh and the connector flips to `connected`:

```bash
echo detect | sudo tee /sys/class/drm/card0-DP-1/status /sys/class/drm/card0-DP-2/status
```

That's the entire fix. The connector wakes, EDID negotiation completes,
the compositor sees a new output, and the monitors come back on.

## What this repo installs

A tiny systemd setup that runs the poke automatically:

| File | Purpose |
|---|---|
| `dp-wake.sh` | Iterates every `card*-DP-*` connector; pokes any that are `disconnected`. |
| `dp-wake.service` | systemd oneshot, wired into `graphical.target` — runs once per boot. |
| `dp-wake-resume` | `system-sleep` hook — also runs on resume from suspend, just in case. |
| `install.sh` / `uninstall.sh` | Idempotent installer. |

The script is **non-destructive**: writing `detect` only triggers a
re-probe. If nothing is plugged in, the connector stays `disconnected`
and no fake output appears.

## Install

```bash
git clone <this repo> ~/Code/dp-wake
cd ~/Code/dp-wake
sudo ./install.sh
```

Verify:

```bash
systemctl status dp-wake.service
journalctl -t dp-wake -n 20
```

You should see lines like:

```
dp-wake: card0-DP-1=disconnected — poking
dp-wake: card0-DP-1: disconnected -> connected
dp-wake: card0-DP-2=disconnected — poking
dp-wake: card0-DP-2: disconnected -> connected
```

## Uninstall

```bash
sudo ./uninstall.sh
```

## Things that did **not** fix it

- Firmware update via `fwupdmgr` — both dock and host were already current.
- `prime-select nvidia` — already set; not a PRIME provider issue.
- Reloading the NVIDIA DRM module — overkill; the connectors just needed a poke.
- A BIOS "always power dock" setting — MSI laptops don't expose this; it's a
  Lenovo/Dell ecosystem feature.

## Manual escape hatch

If the service isn't installed or hasn't run yet, the one-liner that
recovers your monitors right now is:

```bash
echo detect | sudo tee /sys/class/drm/card*-DP-*/status >/dev/null
```

## Diagnostic recipe (for the next mystery)

```bash
# What does the kernel actually see?
for c in /sys/class/drm/card*-*-*; do
  [ -e "$c/status" ] && echo "$(basename $c): $(cat $c/status)"
done

# Are we even on the right session type?
echo "$XDG_SESSION_TYPE"   # wayland or x11

# Wayland users: xrandr lies about providers. Ask the compositor.
gdbus call --session \
  --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.gnome.Mutter.DisplayConfig.GetCurrentState

# Force a re-probe and watch what the kernel logs
echo detect | sudo tee /sys/class/drm/card0-DP-1/status >/dev/null
dmesg -w
```

## License

[MIT](LICENSE)
