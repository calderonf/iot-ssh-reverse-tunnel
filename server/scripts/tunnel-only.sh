#!/usr/bin/env bash
set -euo pipefail

# Script de contención para el usuario iot-tunnel.
# Valida (opcionalmente) el device y puerto contra /etc/iot-ssh-tunnel/ports.allow.
# Este archivo NO se instala automáticamente; el repo provee referencia.

DEVICE_ARG="${1:-device_id=UNSET}"
PORT_ARG="${2:-port=UNSET}"
DEVICE_ID="${DEVICE_ARG#device_id=}"
PORT_NUM="${PORT_ARG#port=}"

ALLOW_FILE="/etc/iot-ssh-tunnel/ports.allow"

# Si existe lista blanca, verificar (formato: device_id,port)
if [[ -f "$ALLOW_FILE" ]]; then
  if ! grep -qE "^${DEVICE_ID},${PORT_NUM}$" "$ALLOW_FILE"; then
    echo "Port/Device not allowed: ${DEVICE_ID},${PORT_NUM}" >&2
    exit 1
  fi
fi

# No abrir shell; el canal -R lo maneja sshd
sleep infinity
