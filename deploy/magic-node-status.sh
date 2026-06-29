#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/magic-vpn-node/config/node.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"
PUBLIC_KEY_FILE="/etc/magic-vpn-node/${WG_INTERFACE}.public.key"

echo "Magic VPN node status"
echo "====================="
echo "Node ID: ${NODE_ID:-not-set}"
echo "Node name: ${NODE_NAME:-not-set}"
echo "Control API: ${CONTROL_API_URL:-not-set}"
echo "WireGuard interface: ${WG_INTERFACE}"
echo "WireGuard port: ${WG_PORT}/udp"
echo

echo "System forwarding:"
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding || true
echo

echo "Firewall:"
firewall-cmd --state || true
firewall-cmd --list-ports || true
firewall-cmd --query-masquerade || true
echo

echo "WireGuard service:"
systemctl --no-pager --full status "wg-quick@${WG_INTERFACE}" || true
echo

echo "WireGuard peers:"
wg show "${WG_INTERFACE}" || true
echo

if [[ -f "${PUBLIC_KEY_FILE}" ]]; then
  echo "Node public key:"
  cat "${PUBLIC_KEY_FILE}"
fi
