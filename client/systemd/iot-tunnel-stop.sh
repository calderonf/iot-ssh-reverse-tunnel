#!/bin/bash
#
# iot-tunnel-stop.sh - Script de Detención para Servicio Systemd
# Wrapper para detener túnel SSH inverso de forma segura
#

set -euo pipefail

# Configuración
PID_FILE="/var/run/iot-ssh-tunnel/autossh.pid"
LOG_FILE="/var/log/iot-ssh-tunnel/service.log"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "Deteniendo túnel SSH inverso"

# Detener autossh si existe PID file
if [[ -f "${PID_FILE}" ]]; then
    PID=$(cat "${PID_FILE}")
    if kill -0 "${PID}" 2>/dev/null; then
        log "Deteniendo proceso autossh (PID: ${PID})"
        kill "${PID}"
        sleep 2

        # Forzar si es necesario
        if kill -0 "${PID}" 2>/dev/null; then
            log "Forzando detención de proceso"
            kill -9 "${PID}"
        fi
    fi
    rm -f "${PID_FILE}"
fi

# Limpiar procesos SSH huérfanos relacionados con el túnel
pkill -f "ssh.*-R.*localhost:22" || true

log "Túnel detenido"
exit 0
