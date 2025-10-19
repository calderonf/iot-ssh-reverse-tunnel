#!/bin/bash
#
# iot-tunnel-start.sh - Script de Inicio para Servicio Systemd
# Wrapper para iniciar túnel SSH inverso como servicio
#

set -euo pipefail

# Configuración
CONFIG_DIR="/etc/iot-ssh-tunnel"
CONFIG_FILE="${CONFIG_DIR}/tunnel.conf"
LOG_FILE="/var/log/iot-ssh-tunnel/service.log"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Verificar configuración
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log "ERROR: Archivo de configuración no encontrado: ${CONFIG_FILE}"
    exit 1
fi

# Cargar configuración
source "${CONFIG_FILE}"

# Verificar variables requeridas
if [[ -z "${SERVER_HOST:-}" ]] || [[ -z "${TUNNEL_PORT:-}" ]]; then
    log "ERROR: Configuración incompleta en ${CONFIG_FILE}"
    exit 1
fi

# Verificar clave SSH
if [[ ! -f "${SSH_KEY:-/etc/iot-ssh-tunnel/tunnel_key}" ]]; then
    log "ERROR: Clave SSH no encontrada: ${SSH_KEY}"
    exit 1
fi

log "Iniciando túnel SSH inverso"
log "Servidor: ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"
log "Puerto túnel: ${TUNNEL_PORT}"

# Establecer variables de entorno para autossh
# Usar RuntimeDirectory de systemd si está disponible, sino usar /var/run
RUNTIME_DIR="${RUNTIME_DIRECTORY:-/var/run/iot-ssh-tunnel}"
export AUTOSSH_PIDFILE="${RUNTIME_DIR}/autossh.pid"
export AUTOSSH_PORT="${AUTOSSH_PORT:-0}"
export AUTOSSH_GATETIME=0

# Comando SSH
SSH_ARGS="-N -R ${TUNNEL_PORT}:localhost:22 -i ${SSH_KEY} ${SSH_OPTIONS} -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST}"

# Usar autossh si está disponible, sino ssh directo
if command -v autossh &> /dev/null; then
    log "Usando autossh para reconexión automática"
    exec autossh -M "${AUTOSSH_PORT}" ${SSH_ARGS}
else
    log "autossh no disponible, usando ssh directo"
    exec ssh ${SSH_ARGS}
fi
