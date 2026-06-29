#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash install-centos9.sh"
  exit 1
fi

WG_PORT="${WG_PORT:-51820}"
SWAP_FILE="${SWAP_FILE:-/swapfile}"
SWAP_SIZE="${SWAP_SIZE:-1G}"

ensure_swap() {
  if swapon --show | grep -q .; then
    echo "Swap already enabled."
    return
  fi

  echo "No swap detected. Creating ${SWAP_SIZE} swap at ${SWAP_FILE}..."
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" || dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=1024
  else
    dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=1024
  fi

  chmod 600 "${SWAP_FILE}"
  mkswap "${SWAP_FILE}"
  swapon "${SWAP_FILE}"

  if ! grep -q "^${SWAP_FILE} " /etc/fstab; then
    echo "${SWAP_FILE} none swap sw 0 0" >>/etc/fstab
  fi
}

dnf_install() {
  dnf -y --setopt=install_weak_deps=False --setopt=max_parallel_downloads=1 install "$@"
}

echo "[1/8] Preparing low-memory server..."
ensure_swap
dnf clean all || true

echo "[2/8] Updating CentOS 9 packages..."
dnf -y --setopt=install_weak_deps=False --setopt=max_parallel_downloads=1 update

echo "[3/8] Installing base tools..."
dnf_install dnf-plugins-core curl wget git vim firewalld tar gzip jq iproute iptables

echo "[4/8] Enabling repositories..."
dnf_install epel-release || true
dnf config-manager --set-enabled crb || true

echo "[5/8] Installing WireGuard..."
dnf_install wireguard-tools

echo "[6/8] Enabling firewall..."
systemctl enable --now firewalld

echo "[7/8] Enabling kernel forwarding..."
cat >/etc/sysctl.d/99-magic-vpn-node.conf <<SYSCTL
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl --system

echo "[8/8] Opening WireGuard firewall port..."
firewall-cmd --permanent --add-port="${WG_PORT}/udp"
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

mkdir -p /opt/magic-vpn-node/config /etc/magic-vpn-node

echo "CentOS 9 VPN node initialization completed."
echo "Next:"
echo "  1. Copy node.env.example to /opt/magic-vpn-node/config/node.env"
echo "  2. Edit node.env"
echo "  3. Run setup-wireguard-node.sh"
