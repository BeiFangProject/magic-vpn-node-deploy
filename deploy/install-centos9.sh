#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash install-centos9.sh"
  exit 1
fi

WG_PORT="${WG_PORT:-51820}"

echo "[1/7] Updating CentOS 9 packages..."
dnf -y update

echo "[2/7] Installing base tools..."
dnf -y install dnf-plugins-core curl wget git vim firewalld tar gzip jq iproute iptables

echo "[3/7] Enabling repositories..."
dnf -y install epel-release || true
dnf config-manager --set-enabled crb || true

echo "[4/7] Installing WireGuard..."
dnf -y install wireguard-tools

echo "[5/7] Enabling firewall..."
systemctl enable --now firewalld

echo "[6/7] Enabling kernel forwarding..."
cat >/etc/sysctl.d/99-magic-vpn-node.conf <<SYSCTL
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl --system

echo "[7/7] Opening WireGuard firewall port..."
firewall-cmd --permanent --add-port="${WG_PORT}/udp"
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

mkdir -p /opt/magic-vpn-node/config /etc/magic-vpn-node

echo "CentOS 9 VPN node initialization completed."
echo "Next:"
echo "  1. Copy node.env.example to /opt/magic-vpn-node/config/node.env"
echo "  2. Edit node.env"
echo "  3. Run setup-wireguard-node.sh"
