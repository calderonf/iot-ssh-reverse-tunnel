#!/bin/bash
#
# ssh_tunnel_setup.sh - Configuración y Gestión de Túnel SSH Inverso
# Establece túnel SSH inverso desde dispositivo IoT hacia servidor
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/iot-ssh-tunnel"
CONFIG_FILE="${CONFIG_DIR}/tunnel.conf"
SSH_KEY_FILE="${CONFIG_DIR}/tunnel_key"
DEVICE_ID_FILE="${CONFIG_DIR}/device_id"
LOG_FILE="/var/log/iot-ssh-tunnel/tunnel.log"
PID_FILE="/var/run/iot-ssh-tunnel/tunnel.pid"

# Valores por defecto
DEFAULT_SERVER_HOST=""
DEFAULT_SERVER_PORT="22"
DEFAULT_SERVER_USER="iot-tunnel"
DEFAULT_TUNNEL_PORT=""
DEFAULT_AUTOSSH_PORT="0"
DEFAULT_SSH_OPTIONS="-o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funciones de logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
}

# Inicializar
initialize() {
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p "$(dirname "${PID_FILE}")"

    # Verificar dependencias
    check_dependencies
}

# Verificar dependencias
check_dependencies() {
    local missing_deps=()

    if ! command -v ssh &> /dev/null; then
        missing_deps+=("ssh")
    fi

    if ! command -v autossh &> /dev/null; then
        log_warning "autossh no está instalado. Se usará ssh directamente."
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing_deps[*]}"
        log_error "Instale con: apt-get install openssh-client autossh"
        exit 1
    fi
}

# Cargar configuración
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_warning "Archivo de configuración no encontrado: ${CONFIG_FILE}"
        return 1
    fi

    source "${CONFIG_FILE}"
    log_debug "Configuración cargada desde ${CONFIG_FILE}"
    return 0
}

# Crear configuración inicial
create_config() {
    local server_host="$1"
    local server_port="${2:-${DEFAULT_SERVER_PORT}}"
    local server_user="${3:-${DEFAULT_SERVER_USER}}"
    local tunnel_port="${4:-${DEFAULT_TUNNEL_PORT}}"

    if [[ -z "${server_host}" ]]; then
        log_error "Se requiere especificar el host del servidor"
        return 1
    fi

    # Crear archivo de configuración
    cat > "${CONFIG_FILE}" << EOF
# Configuración de Túnel SSH Inverso
# Generado: $(date '+%Y-%m-%d %H:%M:%S')

# Servidor SSH remoto
SERVER_HOST="${server_host}"
SERVER_PORT="${server_port}"
SERVER_USER="${server_user}"

# Puerto del túnel (asignado por el servidor)
TUNNEL_PORT="${tunnel_port}"

# Opciones de SSH
SSH_OPTIONS="${DEFAULT_SSH_OPTIONS}"

# Puerto de monitoreo de autossh (0 = automático)
AUTOSSH_PORT="${DEFAULT_AUTOSSH_PORT}"

# Archivo de clave SSH
SSH_KEY="${SSH_KEY_FILE}"

# Device ID
DEVICE_ID_FILE="${DEVICE_ID_FILE}"
EOF

    chmod 600 "${CONFIG_FILE}"
    log_info "Configuración creada: ${CONFIG_FILE}"

    return 0
}

# Obtener Device ID
get_device_id() {
    if [[ -f "${DEVICE_ID_FILE}" ]]; then
        cat "${DEVICE_ID_FILE}"
    else
        log_error "Device ID no encontrado. Ejecute device_identifier.sh primero"
        exit 1
    fi
}

# Verificar clave SSH
check_ssh_key() {
    if [[ ! -f "${SSH_KEY_FILE}" ]]; then
        log_error "Clave SSH no encontrada: ${SSH_KEY_FILE}"
        log_error "Genere una clave con: ssh-keygen -t ed25519 -f ${SSH_KEY_FILE}"
        return 1
    fi

    if [[ ! -f "${SSH_KEY_FILE}.pub" ]]; then
        log_error "Clave pública SSH no encontrada: ${SSH_KEY_FILE}.pub"
        return 1
    fi

    # Verificar permisos
    chmod 600 "${SSH_KEY_FILE}"
    chmod 644 "${SSH_KEY_FILE}.pub"

    log_debug "Clave SSH verificada: ${SSH_KEY_FILE}"
    return 0
}

# Establecer túnel SSH inverso
establish_tunnel() {
    load_config || {
        log_error "No se pudo cargar la configuración"
        return 1
    }

    check_ssh_key || return 1

    local device_id
    device_id=$(get_device_id)

    log_info "Estableciendo túnel SSH inverso"
    log_info "  Device ID: ${device_id}"
    log_info "  Servidor: ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"
    log_info "  Puerto túnel: ${TUNNEL_PORT}"

    # Construir argumentos SSH
    local ssh_args="-N -R ${TUNNEL_PORT}:localhost:22 -i ${SSH_KEY} ${SSH_OPTIONS} -p ${SERVER_PORT} ${SERVER_USER}@${SERVER_HOST}"

    # Usar autossh si está disponible
    if command -v autossh &> /dev/null; then
        export AUTOSSH_PIDFILE="${PID_FILE}"
        export AUTOSSH_PORT="${AUTOSSH_PORT}"
        export AUTOSSH_GATETIME=0

        log_info "Usando autossh para reconexión automática"
        autossh -M "${AUTOSSH_PORT}" -f ${ssh_args}
    else
        log_warning "autossh no disponible, usando ssh directo"
        ssh ${ssh_args} &
        echo $! > "${PID_FILE}"
    fi

    # Verificar que el túnel se estableció
    sleep 2
    if is_tunnel_active; then
        log_info "Túnel establecido exitosamente"
        return 0
    else
        log_error "No se pudo establecer el túnel"
        return 1
    fi
}

# Verificar si túnel está activo
is_tunnel_active() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}")

        if kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Detener túnel
stop_tunnel() {
    if ! is_tunnel_active; then
        log_warning "No hay túnel activo"
        return 1
    fi

    local pid
    pid=$(cat "${PID_FILE}")

    log_info "Deteniendo túnel (PID: ${pid})"

    # Intentar detener gracefully
    kill "${pid}" 2>/dev/null || true
    sleep 2

    # Forzar si es necesario
    if kill -0 "${pid}" 2>/dev/null; then
        kill -9 "${pid}" 2>/dev/null || true
        log_warning "Túnel forzado a cerrar"
    fi

    rm -f "${PID_FILE}"
    log_info "Túnel detenido"

    return 0
}

# Reiniciar túnel
restart_tunnel() {
    log_info "Reiniciando túnel"

    if is_tunnel_active; then
        stop_tunnel
    fi

    sleep 2
    establish_tunnel
}

# Ver estado del túnel
tunnel_status() {
    echo "Estado del Túnel SSH Inverso"
    echo "============================="

    local device_id
    device_id=$(get_device_id 2>/dev/null || echo "No configurado")
    echo "Device ID: ${device_id}"

    if load_config 2>/dev/null; then
        echo "Servidor: ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"
        echo "Puerto túnel: ${TUNNEL_PORT}"
    else
        echo "Configuración: No encontrada"
    fi

    echo ""

    if is_tunnel_active; then
        local pid
        pid=$(cat "${PID_FILE}")
        echo -e "Estado: ${GREEN}ACTIVO${NC}"
        echo "PID: ${pid}"

        # Mostrar conexiones SSH activas
        echo ""
        echo "Conexiones SSH activas:"
        ps -p "${pid}" -o pid,etime,cmd 2>/dev/null || echo "  No disponible"
    else
        echo -e "Estado: ${RED}INACTIVO${NC}"
    fi
}

# Test de conectividad
test_connection() {
    load_config || {
        log_error "No se pudo cargar la configuración"
        return 1
    }

    check_ssh_key || return 1

    log_info "Probando conectividad con servidor SSH"
    log_info "  Servidor: ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"

    # Intentar conexión SSH simple
    if ssh -i "${SSH_KEY}" ${SSH_OPTIONS} -p "${SERVER_PORT}" \
        -o ConnectTimeout=10 \
        "${SERVER_USER}@${SERVER_HOST}" "echo 'OK'" 2>/dev/null; then
        log_info "Conectividad: OK"
        return 0
    else
        log_error "No se pudo conectar al servidor SSH"
        log_error "Verifique configuración de red y credenciales"
        return 1
    fi
}

# Mostrar logs
show_logs() {
    local lines="${1:-50}"

    if [[ -f "${LOG_FILE}" ]]; then
        echo "Últimas ${lines} líneas del log:"
        echo "================================"
        tail -n "${lines}" "${LOG_FILE}"
    else
        log_warning "No se encontró archivo de log: ${LOG_FILE}"
    fi
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Configuración y Gestión de Túnel SSH Inverso para Dispositivos IoT

COMANDOS:
  setup <server> [port] [user] [tunnel_port]   Configurar túnel inicial
  start                                         Iniciar túnel
  stop                                          Detener túnel
  restart                                       Reiniciar túnel
  status                                        Ver estado del túnel
  test                                          Probar conectividad
  logs [lines]                                  Mostrar logs (default: 50)
  help                                          Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") setup tunnel.example.com 22 iot-tunnel 10001
  $(basename "$0") start
  $(basename "$0") status
  $(basename "$0") test
  $(basename "$0") logs 100

ARCHIVOS:
  Configuración: ${CONFIG_FILE}
  Clave SSH: ${SSH_KEY_FILE}
  Device ID: ${DEVICE_ID_FILE}
  Log: ${LOG_FILE}
  PID: ${PID_FILE}

DESCRIPCIÓN:
  Este script gestiona el túnel SSH inverso que permite acceso remoto
  al dispositivo IoT desde el servidor central. Utiliza autossh para
  mantener la conexión persistente y auto-recuperable.

DEPENDENCIAS:
  - openssh-client
  - autossh (recomendado)

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        setup)
            if [[ $# -lt 2 ]]; then
                log_error "Falta especificar servidor"
                show_help
                exit 1
            fi
            create_config "$2" "${3:-}" "${4:-}" "${5:-}"
            ;;
        start)
            establish_tunnel
            ;;
        stop)
            stop_tunnel
            ;;
        restart)
            restart_tunnel
            ;;
        status)
            tunnel_status
            ;;
        test)
            test_connection
            ;;
        logs)
            show_logs "${2:-50}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Comando desconocido: ${command}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
