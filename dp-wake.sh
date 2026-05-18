#!/usr/bin/env bash
# Force a DRM connector re-poll on every DisplayPort output.
#
# Background: certain laptop/dock combinations (notably MSI GS66 + Lenovo TBT3
# Dock) lose DisplayPort hot-plug-detect across a host cold boot. The kernel
# reports the connectors as `status=disconnected` and they never reappear
# until the user physically replugs the dock or writes `detect` into the
# connector's sysfs status file. This script does the latter, automatically,
# at every boot and after every resume from suspend.
#
# Writing `detect` does NOT force a fake connection — it just tells the DRM
# layer "re-run hot-plug detection on this connector". If nothing is attached,
# the status stays `disconnected` and nothing else happens.

set -euo pipefail

DRM_PATH="${DRM_PATH:-/sys/class/drm}"
LOG_TAG="dp-wake"

log() { logger -t "$LOG_TAG" -- "$*"; echo "$*"; }

# Give the GPU drivers a moment to finish initial enumeration. Without this
# the poke can land before the DP connectors are fully registered.
sleep "${DP_WAKE_DELAY:-3}"

shopt -s nullglob
connectors=("$DRM_PATH"/card*-DP-*)
if [ ${#connectors[@]} -eq 0 ]; then
  log "no DP connectors found under $DRM_PATH"
  exit 0
fi

for conn in "${connectors[@]}"; do
  [ -e "$conn/status" ] || continue
  name=$(basename "$conn")
  before=$(cat "$conn/status")

  if [ "$before" = "disconnected" ]; then
    log "$name=disconnected — poking"
    echo detect > "$conn/status" || {
      log "$name: write to status failed (need root?)"
      continue
    }
    sleep 0.3
    after=$(cat "$conn/status")
    log "$name: $before -> $after"
  else
    log "$name=$before — skipping"
  fi
done
