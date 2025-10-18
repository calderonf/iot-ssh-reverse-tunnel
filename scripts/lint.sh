#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
EXIT_CODE=0

# Validar que los scripts .sh sean ejecutables
while IFS= read -r -d '' script; do
  if [[ ! -x "$script" ]]; then
    echo "Shell script no ejecutable: ${script}" >&2
    EXIT_CODE=1
  fi
done < <(find "$ROOT_DIR" -type f -name "*.sh" -print0)

# Verificar que los archivos de configuración no contengan tabuladores
while IFS= read -r -d '' config; do
  if grep -P '\t' "$config" >/dev/null; then
    echo "Tabuladores detectados en archivo de configuración: ${config}" >&2
    EXIT_CODE=1
  fi
done < <(find "$ROOT_DIR/server/configs" -type f -print0 2>/dev/null)

CONFIG_FILE="$ROOT_DIR/server/configs/sshd_config.d/iot-tunnel.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  if ! grep -q "^\s*AllowTcpForwarding\s\+remote" "$CONFIG_FILE"; then
    echo "Falta 'AllowTcpForwarding remote' en ${CONFIG_FILE}" >&2
    EXIT_CODE=1
  fi
  if ! grep -q "^\s*GatewayPorts\s\+clientspecified" "$CONFIG_FILE"; then
    echo "Falta 'GatewayPorts clientspecified' en ${CONFIG_FILE}" >&2
    EXIT_CODE=1
  fi
  if ! grep -q "^\s*PermitListen\s\+" "$CONFIG_FILE"; then
    echo "Falta al menos una directiva PermitListen en ${CONFIG_FILE}" >&2
    EXIT_CODE=1
  fi
else
  echo "Archivo de configuración no encontrado: ${CONFIG_FILE}" >&2
  EXIT_CODE=1
fi

if [[ "$EXIT_CODE" -ne 0 ]]; then
  exit "$EXIT_CODE"
fi

echo "Lint OK"
