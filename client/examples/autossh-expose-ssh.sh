#!/usr/bin/env bash
set -euo pipefail

# Expone el SSH local del dispositivo (22) como puerto 10001 en el servidor.
# Reemplaza las variables según corresponda.

SERVER_HOST="<<SERVER_PUBLIC_IP_OR_DNS>>"
SERVER_PORT="22"
REMOTE_PORT="10001"

SSH_USER="iot-tunnel"
KEY_PATH="/etc/iot-ssh-tunnel/tunnel_key"

# Mantener vivo el túnel sin monitor de autossh (-M 0)
exec autossh -M 0 -N \
  -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" \
  -i "${KEY_PATH}" \
  -R 0.0.0.0:${REMOTE_PORT}:127.0.0.1:22 \
  ${SSH_USER}@${SERVER_HOST} -p ${SERVER_PORT}
