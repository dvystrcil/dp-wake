#!/usr/bin/env bash
# Install dp-wake. Must run as root.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"

install -m 0755 "$HERE/dp-wake.sh"        /usr/local/bin/dp-wake.sh
install -m 0644 "$HERE/dp-wake.service"   /etc/systemd/system/dp-wake.service
install -m 0755 "$HERE/dp-wake-resume"    /lib/systemd/system-sleep/dp-wake-resume

systemctl daemon-reload
systemctl enable --now dp-wake.service

echo
echo "Installed. Verify with:"
echo "  systemctl status dp-wake.service"
echo "  journalctl -t dp-wake -n 20"
