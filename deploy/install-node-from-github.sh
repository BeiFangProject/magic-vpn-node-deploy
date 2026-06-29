#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: curl ... | sudo bash"
  exit 1
fi

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/magic-vpn-node}"
NODE_NAME="${NODE_NAME:-}"
NODE_REGION="${NODE_REGION:-}"
NODE_COUNTRY_CODE="${NODE_COUNTRY_CODE:-}"
NODE_CITY="${NODE_CITY:-}"
WG_PORT="${WG_PORT:-51820}"
WG_ADDRESS="${WG_ADDRESS:-10.66.0.1/24}"
ENDPOINT_HOST="${ENDPOINT_HOST:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --name)
      NODE_NAME="$2"
      shift 2
      ;;
    --region)
      NODE_REGION="$2"
      shift 2
      ;;
    --country)
      NODE_COUNTRY_CODE="$2"
      shift 2
      ;;
    --city)
      NODE_CITY="$2"
      shift 2
      ;;
    --port)
      WG_PORT="$2"
      shift 2
      ;;
    --address)
      WG_ADDRESS="$2"
      shift 2
      ;;
    --endpoint)
      ENDPOINT_HOST="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${REPO_URL}" ]]; then
  echo "Missing repo URL."
  echo "Example:"
  echo "  curl -fsSL https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/deploy/install-node-from-github.sh | sudo bash -s -- --repo https://github.com/YOUR_NAME/YOUR_REPO.git"
  exit 1
fi

detect_public_ip() {
  curl -fsS4 https://api.ipify.org 2>/dev/null || \
    curl -fsS4 https://ifconfig.me 2>/dev/null || \
    hostname -I | awk '{print $1}'
}

detect_geo_json() {
  curl -fsS "https://ipapi.co/json/" 2>/dev/null || \
    curl -fsS "http://ip-api.com/json/?fields=status,countryCode,city,continentCode,query" 2>/dev/null || \
    echo "{}"
}

json_value() {
  local key="$1"
  python3 -c '
import json
import sys

key = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print(data.get(key) or "")
' "$key"
}

normalize_slug() {
  tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

region_from_country() {
  case "$1" in
    JP|HK|SG|KR|TW|TH|VN|MY|ID|PH|IN) echo "asia" ;;
    US|CA|MX|BR|AR|CL) echo "america" ;;
    GB|DE|FR|NL|ES|IT|SE|PL|FI) echo "europe" ;;
    AU|NZ) echo "oceania" ;;
    *) echo "global" ;;
  esac
}

echo "[1/6] Installing git and helpers..."
dnf -y install git curl python3 >/dev/null

echo "[2/6] Detecting server location..."
PUBLIC_IP="$(detect_public_ip)"
GEO_JSON="$(detect_geo_json)"
DETECTED_COUNTRY="$(printf '%s' "${GEO_JSON}" | json_value country_code)"
if [[ -z "${DETECTED_COUNTRY}" ]]; then
  DETECTED_COUNTRY="$(printf '%s' "${GEO_JSON}" | json_value countryCode)"
fi
DETECTED_CITY="$(printf '%s' "${GEO_JSON}" | json_value city)"

NODE_COUNTRY_CODE="${NODE_COUNTRY_CODE:-${DETECTED_COUNTRY:-UN}}"
NODE_CITY="${NODE_CITY:-${DETECTED_CITY:-Unknown}}"
NODE_REGION="${NODE_REGION:-$(region_from_country "${NODE_COUNTRY_CODE}")}"

if [[ -z "${ENDPOINT_HOST}" ]]; then
  ENDPOINT_HOST="${PUBLIC_IP}"
fi

if [[ -z "${NODE_NAME}" ]]; then
  CITY_SLUG="$(printf '%s' "${NODE_CITY}" | normalize_slug)"
  IP_SLUG="$(printf '%s' "${PUBLIC_IP}" | sed 's/\./-/g; s/:/-/g' | normalize_slug)"
  NODE_NAME="$(printf '%s-%s-%s' "${NODE_COUNTRY_CODE}" "${CITY_SLUG:-node}" "${IP_SLUG}" | normalize_slug)"
fi

echo "Detected public IP: ${PUBLIC_IP}"
echo "Detected location: ${NODE_COUNTRY_CODE} / ${NODE_CITY} / ${NODE_REGION}"
echo "Node name: ${NODE_NAME}"

echo "[3/6] Pulling project from GitHub..."
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  git -C "${INSTALL_DIR}" fetch origin "${BRANCH}"
  git -C "${INSTALL_DIR}" reset --hard "origin/${BRANCH}"
else
  rm -rf "${INSTALL_DIR}"
  git clone --branch "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
fi

echo "[4/6] Writing node env..."
mkdir -p "${INSTALL_DIR}/config"
cat >"${INSTALL_DIR}/config/node.env" <<ENV
NODE_ID=
NODE_NAME=${NODE_NAME}
NODE_TOKEN=
CONTROL_API_URL=
NODE_REGION=${NODE_REGION}
NODE_COUNTRY_CODE=${NODE_COUNTRY_CODE}
NODE_CITY=${NODE_CITY}
WG_INTERFACE=wg0
WG_PORT=${WG_PORT}
WG_ADDRESS=${WG_ADDRESS}
WG_CONFIG_PATH=/etc/wireguard/wg0.conf
ENDPOINT_HOST=${ENDPOINT_HOST}
PUBLIC_IP=${PUBLIC_IP}
PUBLIC_INTERFACE=
CLIENT_DNS=1.1.1.1
ENV

echo "[5/6] Installing node server requirements..."
bash "${INSTALL_DIR}/deploy/install-centos9.sh"

echo "[6/6] Setting up WireGuard..."
ENV_FILE="${INSTALL_DIR}/config/node.env" bash "${INSTALL_DIR}/deploy/setup-wireguard-node.sh"

echo
echo "All done. Paste the JSON above into the admin panel."
