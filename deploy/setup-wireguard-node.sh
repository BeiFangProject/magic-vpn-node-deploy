#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash setup-wireguard-node.sh"
  exit 1
fi

ENV_FILE="${ENV_FILE:-/opt/magic-vpn-node/config/node.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  echo "Copy node.env.example to ${ENV_FILE} and edit it first."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_ADDRESS="${WG_ADDRESS:-10.66.0.1/24}"
VPN_CIDR="${VPN_CIDR:-10.66.0.0/24}"
WG_CONFIG_PATH="${WG_CONFIG_PATH:-/etc/wireguard/${WG_INTERFACE}.conf}"
AGENT_HOST="${AGENT_HOST:-0.0.0.0}"
AGENT_PORT="${AGENT_PORT:-51821}"
KEY_DIR="/etc/magic-vpn-node"
PRIVATE_KEY_FILE="${KEY_DIR}/${WG_INTERFACE}.private.key"
PUBLIC_KEY_FILE="${KEY_DIR}/${WG_INTERFACE}.public.key"
AGENT_TOKEN_FILE="${KEY_DIR}/agent.token"
AGENT_SCRIPT="/opt/magic-vpn-node/magic-vpn-node-agent.py"
NODE_CONFIG_JSON="/opt/magic-vpn-node/node-config.json"

mkdir -p "${KEY_DIR}" /etc/wireguard
chmod 700 "${KEY_DIR}" /etc/wireguard

if [[ ! -f "${PRIVATE_KEY_FILE}" ]]; then
  echo "Generating WireGuard key pair..."
  wg genkey | tee "${PRIVATE_KEY_FILE}" | wg pubkey >"${PUBLIC_KEY_FILE}"
  chmod 600 "${PRIVATE_KEY_FILE}"
  chmod 644 "${PUBLIC_KEY_FILE}"
fi

PRIVATE_KEY="$(cat "${PRIVATE_KEY_FILE}")"
PUBLIC_KEY="$(cat "${PUBLIC_KEY_FILE}")"

if [[ -z "${AGENT_TOKEN:-}" ]]; then
  if [[ ! -f "${AGENT_TOKEN_FILE}" ]]; then
    python3 -c 'import secrets; print(secrets.token_hex(24))' >"${AGENT_TOKEN_FILE}"
    chmod 600 "${AGENT_TOKEN_FILE}"
  fi
  AGENT_TOKEN="$(cat "${AGENT_TOKEN_FILE}")"
fi

if [[ -z "${PUBLIC_INTERFACE:-}" ]]; then
  PUBLIC_INTERFACE="$(ip route show default | awk '/default/ {print $5; exit}')"
fi

if [[ -z "${PUBLIC_INTERFACE}" ]]; then
  echo "Cannot detect public network interface. Set PUBLIC_INTERFACE in ${ENV_FILE}."
  exit 1
fi

detect_public_ip() {
  curl -fsS4 https://api.ipify.org 2>/dev/null || \
    curl -fsS4 https://ifconfig.me 2>/dev/null || \
    hostname -I | awk '{print $1}'
}

PUBLIC_IP="${PUBLIC_IP:-$(detect_public_ip)}"
ENDPOINT_HOST="${ENDPOINT_HOST:-${PUBLIC_IP}}"
NODE_REGION="${NODE_REGION:-asia}"
NODE_COUNTRY_CODE="${NODE_COUNTRY_CODE:-JP}"
NODE_CITY="${NODE_CITY:-Tokyo}"

cat >"${WG_CONFIG_PATH}" <<WGCONF
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}
SaveConfig = false

# NAT outbound VPN client traffic through the public interface.
PostUp = iptables -t nat -C POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE 2>/dev/null || true
WGCONF

chmod 600 "${WG_CONFIG_PATH}"

firewall-cmd --permanent --add-port="${WG_PORT}/udp"
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

systemctl enable --now "wg-quick@${WG_INTERFACE}"

cat >"${AGENT_SCRIPT}" <<'PY'
#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ.get("AGENT_TOKEN", "")
WG_INTERFACE = os.environ.get("WG_INTERFACE", "wg0")


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/health":
            self._json(404, {"ok": False, "message": "not found"})
            return
        self._json(200, {"ok": True})

    def do_POST(self):
        if self.path != "/peers":
            self._json(404, {"ok": False, "message": "not found"})
            return
        auth = self.headers.get("Authorization", "")
        if not TOKEN or auth != f"Bearer {TOKEN}":
            self._json(401, {"ok": False, "message": "unauthorized"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            public_key = payload["public_key"]
            allowed_ip = payload["allowed_ip"]
            subprocess.run(
                ["wg", "set", WG_INTERFACE, "peer", public_key, "allowed-ips", allowed_ip],
                check=True,
                capture_output=True,
                text=True,
            )
            self._json(200, {"ok": True})
        except Exception as exc:
            self._json(400, {"ok": False, "message": str(exc)})


if __name__ == "__main__":
    host = os.environ.get("AGENT_HOST", "0.0.0.0")
    port = int(os.environ.get("AGENT_PORT", "51821"))
    ThreadingHTTPServer((host, port), Handler).serve_forever()
PY

chmod 700 "${AGENT_SCRIPT}"

cat >/etc/systemd/system/magic-vpn-node-agent.service <<SERVICE
[Unit]
Description=Magic VPN Node Agent
After=network-online.target wg-quick@${WG_INTERFACE}.service
Wants=network-online.target

[Service]
Type=simple
Environment=AGENT_TOKEN=${AGENT_TOKEN}
Environment=AGENT_HOST=${AGENT_HOST}
Environment=AGENT_PORT=${AGENT_PORT}
Environment=WG_INTERFACE=${WG_INTERFACE}
ExecStart=/usr/bin/python3 ${AGENT_SCRIPT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

firewall-cmd --permanent --add-port="${AGENT_PORT}/tcp"
firewall-cmd --reload
systemctl daemon-reload
systemctl enable --now magic-vpn-node-agent

cat >"${NODE_CONFIG_JSON}" <<JSON
{
  "name": "${NODE_NAME:-magic-node}",
  "region": "${NODE_REGION}",
  "country_code": "${NODE_COUNTRY_CODE}",
  "city": "${NODE_CITY}",
  "public_ip": "${PUBLIC_IP}",
  "endpoint_host": "${ENDPOINT_HOST}",
  "endpoint_port": ${WG_PORT},
  "wg_public_key": "${PUBLIC_KEY}",
  "bandwidth_limit_bps": null,
  "current_load": 0,
  "status": "maintenance",
  "allow_free_trial": false,
  "agent_url": "http://${ENDPOINT_HOST}:${AGENT_PORT}",
  "agent_token": "${AGENT_TOKEN}",
  "vpn_cidr": "${VPN_CIDR}",
  "dns": "${CLIENT_DNS:-1.1.1.1}"
}
JSON

echo "WireGuard node is ready."
echo "Node name: ${NODE_NAME:-unknown}"
echo "Interface: ${WG_INTERFACE}"
echo "Listen port: ${WG_PORT}/udp"
echo "VPN address: ${WG_ADDRESS}"
echo "Public interface: ${PUBLIC_INTERFACE}"
echo "Public IP: ${PUBLIC_IP}"
echo "Endpoint host: ${ENDPOINT_HOST}"
echo "Node Agent: http://${ENDPOINT_HOST}:${AGENT_PORT}"
echo "WireGuard public key:"
echo "${PUBLIC_KEY}"
echo
echo "Copy the following JSON and paste it into the admin panel node import box:"
echo "---------------- MAGIC_NODE_CONFIG_START ----------------"
cat "${NODE_CONFIG_JSON}"
echo
echo "----------------- MAGIC_NODE_CONFIG_END -----------------"
echo
echo "The same config was saved to ${NODE_CONFIG_JSON}"
