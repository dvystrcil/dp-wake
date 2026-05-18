#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

systemctl disable --now dp-wake.service 2>/dev/null || true
rm -f /etc/systemd/system/dp-wake.service
rm -f /usr/local/bin/dp-wake.sh
rm -f /lib/systemd/system-sleep/dp-wake-resume
systemctl daemon-reload

echo "Removed."
