#!/bin/bash
#
# auto_reconnect.sh - Sistema de Reconexión Automática
# Monitorea y reestablece túnel SSH en caso de desconexión
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUNNEL_SETUP_SCRIPT="${SCRIPT_DIR}/ssh_tunnel_setup.sh"
CONFIG_DIR="/etc/iot-ssh-tunnel"
LOG_FILE="/var/log/iot-ssh-tunnel/auto_reconnect.log"
STATE_FILE="/var/run/iot-ssh-tunnel/reconnect_state"
CHECK_INTERVAL=30
MAX_RETRY_ATTEMPTS=5
RETRY_BACKOFF_BASE=60
NETWORK_CHECK_HOST="8.8.8.8"

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
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p "$(dirname "${STATE_FILE}")"

    if [[ ! -x "${TUNNEL_SETUP_SCRIPT}" ]]; then
        log_error "Script de túnel no encontrado o no ejecutable: ${TUNNEL_SETUP_SCRIPT}"
        exit 1
    fi

    # Inicializar archivo de estado
    if [[ ! -f "${STATE_FILE}" ]]; then
        echo "retry_count=0" > "${STATE_FILE}"
        echo "last_attempt=0" >> "${STATE_FILE}"
        echo "last_success=0" >> "${STATE_FILE}"
    fi
}

# Cargar estado
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}"
    else
        retry_count=0
        last_attempt=0
        last_success=0
    fi
}

# Guardar estado
save_state() {
    cat > "${STATE_FILE}" << EOF
retry_count=${retry_count}
last_attempt=${last_attempt}
last_success=${last_success}
EOF
}

# Verificar conectividad de red
check_network() {
    if ping -c 1 -W 5 "${NETWORK_CHECK_HOST}" &> /dev/null; then
        return 0
    fi
    return 1
}

# Verificar estado del túnel
check_tunnel_status() {
    "${TUNNEL_SETUP_SCRIPT}" status &> /dev/null
    return $?
}

# Calcular tiempo de espera con backoff exponencial
calculate_backoff() {
    local attempt="$1"
    local backoff=$((RETRY_BACKOFF_BASE * (2 ** (attempt - 1))))

    # Máximo 1 hora de espera
    if [[ ${backoff} -gt 3600 ]]; then
        backoff=3600
    fi

    echo "${backoff}"
}

# Intentar reconexión
attempt_reconnect() {
    load_state

    local current_time
    current_time=$(date +%s)

    # Incrementar contador de reintentos
    ((retry_count++))
    last_attempt=${current_time}

    log_info "Intento de reconexión #${retry_count}"

    # Verificar conectividad de red primero
    if ! check_network; then
        log_warning "Sin conectividad de red. Esperando..."
        save_state
        return 1
    fi

    # Detener túnel existente si hay
    "${TUNNEL_SETUP_SCRIPT}" stop &> /dev/null || true

    # Esperar un poco antes de reintentar
    sleep 5

    # Intentar establecer túnel
    if "${TUNNEL_SETUP_SCRIPT}" start; then
        log_info "Túnel reestablecido exitosamente"
        retry_count=0
        last_success=${current_time}
        save_state
        return 0
    else
        log_error "Fallo al reestablecer túnel"
        save_state

        # Verificar si se alcanzó el máximo de reintentos
        if [[ ${retry_count} -ge ${MAX_RETRY_ATTEMPTS} ]]; then
            local backoff
            backoff=$(calculate_backoff ${retry_count})
            log_warning "Máximo de reintentos alcanzado. Esperando ${backoff}s antes del próximo intento"
            sleep "${backoff}"
            retry_count=0
            save_state
        fi

        return 1
    fi
}

# Monitorear túnel continuamente
monitor_tunnel() {
    log_info "Iniciando monitoreo de túnel (intervalo: ${CHECK_INTERVAL}s)"

    while true; do
        log_debug "Verificando estado del túnel..."

        if ! check_tunnel_status; then
            log_warning "Túnel no está activo. Intentando reconexión..."
            attempt_reconnect
        else
            log_debug "Túnel activo"

            # Resetear contador de reintentos si está activo
            load_state
            if [[ ${retry_count} -gt 0 ]]; then
                retry_count=0
                save_state
            fi
        fi

        sleep "${CHECK_INTERVAL}"
    done
}

# Verificar salud del túnel con test de conectividad
health_check() {
    log_debug "Ejecutando verificación de salud..."

    # Verificar proceso activo
    if ! check_tunnel_status; then
        log_warning "Túnel no está activo"
        return 1
    fi

    # Verificar conectividad
    if ! "${TUNNEL_SETUP_SCRIPT}" test &> /dev/null; then
        log_warning "Test de conectividad falló"
        return 1
    fi

    log_debug "Verificación de salud OK"
    return 0
}

# Modo daemon
run_daemon() {
    local pid_file="/var/run/iot-ssh-tunnel/auto_reconnect.pid"

    # Verificar si ya está ejecutándose
    if [[ -f "${pid_file}" ]]; then
        local old_pid
        old_pid=$(cat "${pid_file}")
        if kill -0 "${old_pid}" 2>/dev/null; then
            log_error "Auto-reconnect ya está ejecutándose (PID: ${old_pid})"
            exit 1
        fi
    fi

    # Guardar PID
    echo $$ > "${pid_file}"

    # Trap para limpieza
    trap cleanup EXIT INT TERM

    log_info "Auto-reconnect iniciado en modo daemon (PID: $$)"

    # Monitorear continuamente
    monitor_tunnel
}

# Limpieza al salir
cleanup() {
    local pid_file="/var/run/iot-ssh-tunnel/auto_reconnect.pid"
    log_info "Deteniendo auto-reconnect"
    rm -f "${pid_file}"
    exit 0
}

# Detener daemon
stop_daemon() {
    local pid_file="/var/run/iot-ssh-tunnel/auto_reconnect.pid"

    if [[ ! -f "${pid_file}" ]]; then
        log_warning "Auto-reconnect no está ejecutándose"
        return 1
    fi

    local pid
    pid=$(cat "${pid_file}")

    if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}"
        log_info "Auto-reconnect detenido (PID: ${pid})"
    else
        log_warning "Proceso no encontrado (PID: ${pid})"
        rm -f "${pid_file}"
    fi

    return 0
}

# Ver estado del daemon
daemon_status() {
    local pid_file="/var/run/iot-ssh-tunnel/auto_reconnect.pid"

    echo "Estado del Auto-Reconnect"
    echo "========================="

    if [[ -f "${pid_file}" ]]; then
        local pid
        pid=$(cat "${pid_file}")

        if kill -0 "${pid}" 2>/dev/null; then
            echo -e "Estado: ${GREEN}ACTIVO${NC}"
            echo "PID: ${pid}"

            load_state
            echo ""
            echo "Estadísticas:"
            echo "  Reintentos actuales: ${retry_count}"
            echo "  Último intento: $(date -d "@${last_attempt}" 2>/dev/null || echo 'N/A')"
            echo "  Última conexión exitosa: $(date -d "@${last_success}" 2>/dev/null || echo 'N/A')"
        else
            echo -e "Estado: ${RED}INACTIVO (PID obsoleto)${NC}"
        fi
    else
        echo -e "Estado: ${RED}INACTIVO${NC}"
    fi

    echo ""
    echo "Estado del túnel:"
    "${TUNNEL_SETUP_SCRIPT}" status 2>/dev/null || echo "  No disponible"
}

# Resetear estado
reset_state() {
    log_info "Reseteando estado de reconexión"
    echo "retry_count=0" > "${STATE_FILE}"
    echo "last_attempt=0" >> "${STATE_FILE}"
    echo "last_success=0" >> "${STATE_FILE}"
    log_info "Estado reseteado"
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

Sistema de Reconexión Automática para Túnel SSH Inverso

COMANDOS:
  start                      Iniciar auto-reconnect en modo daemon
  stop                       Detener auto-reconnect
  status                     Ver estado del auto-reconnect
  check                      Verificar estado actual del túnel
  reconnect                  Forzar reconexión inmediata
  reset                      Resetear estado de reconexión
  logs [lines]               Mostrar logs (default: 50)
  help                       Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") start
  $(basename "$0") status
  $(basename "$0") reconnect
  $(basename "$0") logs 100

CONFIGURACIÓN:
  CHECK_INTERVAL: ${CHECK_INTERVAL}s
  MAX_RETRY_ATTEMPTS: ${MAX_RETRY_ATTEMPTS}
  RETRY_BACKOFF_BASE: ${RETRY_BACKOFF_BASE}s
  NETWORK_CHECK_HOST: ${NETWORK_CHECK_HOST}

ARCHIVOS:
  Log: ${LOG_FILE}
  Estado: ${STATE_FILE}

DESCRIPCIÓN:
  Este script monitorea continuamente el túnel SSH inverso y lo
  reestablece automáticamente en caso de desconexión. Implementa
  lógica de backoff exponencial para evitar sobrecarga del servidor.

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        start)
            run_daemon
            ;;
        stop)
            stop_daemon
            ;;
        status)
            daemon_status
            ;;
        check)
            health_check
            ;;
        reconnect)
            attempt_reconnect
            ;;
        reset)
            reset_state
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
