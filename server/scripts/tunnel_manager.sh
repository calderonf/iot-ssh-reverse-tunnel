#!/bin/bash
#
# tunnel_manager.sh - Gestor de Túneles SSH Inversos
# Administra y supervisa túneles SSH activos
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_DIR="${SCRIPT_DIR}/../configs"
DEVICE_MAPPING_FILE="${SERVER_CONFIG_DIR}/device_mapping"
LOG_FILE="/var/log/iot-ssh-tunnel/tunnel_manager.log"
TUNNEL_STATUS_DIR="/var/run/iot-ssh-tunnel"
SSH_PORT=22

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
    mkdir -p "${TUNNEL_STATUS_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"

    if [[ ! -f "${DEVICE_MAPPING_FILE}" ]]; then
        log_error "Archivo de mapeo de dispositivos no encontrado: ${DEVICE_MAPPING_FILE}"
        exit 1
    fi
}

# Obtener conexiones SSH activas
get_active_ssh_connections() {
    ss -tnp 2>/dev/null | grep ':22' | grep 'ESTAB' || true
}

# Verificar si puerto tiene túnel activo
is_tunnel_active() {
    local port="$1"
    netstat -tln 2>/dev/null | grep -q ":${port}[[:space:]]" || \
    ss -tln 2>/dev/null | grep -q ":${port}[[:space:]]"
}

# Obtener PID del proceso escuchando en puerto
get_tunnel_pid() {
    local port="$1"
    lsof -ti ":${port}" 2>/dev/null || true
}

# Obtener información del túnel activo
get_tunnel_info() {
    local port="$1"
    local pid
    pid=$(get_tunnel_pid "${port}")

    if [[ -z "${pid}" ]]; then
        echo "inactive"
        return 1
    fi

    local remote_addr
    remote_addr=$(ss -tnp 2>/dev/null | grep ":${port}" | awk '{print $5}' | head -n1 || echo "unknown")

    echo "${pid}|${remote_addr}"
    return 0
}

# Listar todos los túneles con su estado
list_tunnels() {
    local filter="${1:-all}"

    echo "Estado de Túneles SSH Inversos"
    echo "==============================="
    printf "%-34s %-8s %-12s %-8s %-20s %-10s\n" "DEVICE_ID" "PORT" "STATUS" "PID" "REMOTE_ADDR" "DEVICE_STATE"

    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        local tunnel_status="inactive"
        local pid="N/A"
        local remote_addr="N/A"

        if is_tunnel_active "${port}"; then
            tunnel_status="active"
            local tunnel_info
            tunnel_info=$(get_tunnel_info "${port}")
            if [[ -n "${tunnel_info}" ]] && [[ "${tunnel_info}" != "inactive" ]]; then
                pid=$(echo "${tunnel_info}" | cut -d'|' -f1)
                remote_addr=$(echo "${tunnel_info}" | cut -d'|' -f2)
            fi
        fi

        if [[ "${filter}" == "all" ]] || \
           [[ "${filter}" == "active" && "${tunnel_status}" == "active" ]] || \
           [[ "${filter}" == "inactive" && "${tunnel_status}" == "inactive" ]]; then
            printf "%-34s %-8s %-12s %-8s %-20s %-10s\n" \
                "${device_id:0:32}.." "${port}" "${tunnel_status}" "${pid}" "${remote_addr}" "${status}"
        fi
    done < "${DEVICE_MAPPING_FILE}"
}

# Obtener estadísticas de túneles
get_tunnel_statistics() {
    local total_devices
    local active_tunnels=0
    local inactive_tunnels=0
    local active_devices
    local inactive_devices

    total_devices=$(grep -v '^#' "${DEVICE_MAPPING_FILE}" | grep -c . || echo 0)
    active_devices=$(grep '|active$' "${DEVICE_MAPPING_FILE}" | grep -c . || echo 0)
    inactive_devices=$(grep '|inactive$' "${DEVICE_MAPPING_FILE}" | grep -c . || echo 0)

    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        if is_tunnel_active "${port}"; then
            ((active_tunnels++))
        else
            ((inactive_tunnels++))
        fi
    done < "${DEVICE_MAPPING_FILE}"

    echo "Estadísticas de Túneles"
    echo "========================"
    echo "Total dispositivos registrados: ${total_devices}"
    echo "Dispositivos activos: ${active_devices}"
    echo "Dispositivos inactivos: ${inactive_devices}"
    echo "Túneles conectados: ${active_tunnels}"
    echo "Túneles desconectados: ${inactive_tunnels}"
    echo "Tasa de conexión: $(awk "BEGIN {printf \"%.2f\", (${active_tunnels}/${total_devices})*100}")%"
}

# Verificar salud de túnel específico
check_tunnel_health() {
    local device_id="$1"

    local device_info
    device_info=$(grep "^${device_id}|" "${DEVICE_MAPPING_FILE}" 2>/dev/null)

    if [[ -z "${device_info}" ]]; then
        log_error "Dispositivo no encontrado: ${device_id}"
        return 1
    fi

    IFS='|' read -r dev_id port fingerprint reg_date status <<< "${device_info}"

    echo "Verificación de Salud del Túnel"
    echo "================================"
    echo "Device ID: ${dev_id}"
    echo "Puerto asignado: ${port}"
    echo "Estado del dispositivo: ${status}"

    if is_tunnel_active "${port}"; then
        echo -e "${GREEN}Estado del túnel: ACTIVO${NC}"

        local tunnel_info
        tunnel_info=$(get_tunnel_info "${port}")
        local pid remote_addr
        pid=$(echo "${tunnel_info}" | cut -d'|' -f1)
        remote_addr=$(echo "${tunnel_info}" | cut -d'|' -f2)

        echo "PID del proceso: ${pid}"
        echo "Dirección remota: ${remote_addr}"

        # Verificar si el túnel responde
        if nc -z localhost "${port}" 2>/dev/null; then
            echo -e "${GREEN}Conectividad: OK${NC}"
            return 0
        else
            echo -e "${YELLOW}Conectividad: DEGRADADA${NC}"
            return 1
        fi
    else
        echo -e "${RED}Estado del túnel: INACTIVO${NC}"
        return 1
    fi
}

# Cerrar túnel específico
close_tunnel() {
    local device_id="$1"

    local device_info
    device_info=$(grep "^${device_id}|" "${DEVICE_MAPPING_FILE}" 2>/dev/null)

    if [[ -z "${device_info}" ]]; then
        log_error "Dispositivo no encontrado: ${device_id}"
        return 1
    fi

    local port
    port=$(echo "${device_info}" | cut -d'|' -f2)

    if ! is_tunnel_active "${port}"; then
        log_warning "No hay túnel activo en puerto ${port} para dispositivo ${device_id}"
        return 1
    fi

    local pid
    pid=$(get_tunnel_pid "${port}")

    if [[ -n "${pid}" ]]; then
        kill "${pid}" 2>/dev/null || true
        sleep 1

        if is_tunnel_active "${port}"; then
            kill -9 "${pid}" 2>/dev/null || true
            log_warning "Túnel forzado a cerrar (SIGKILL)"
        else
            log_info "Túnel cerrado correctamente"
        fi
    fi

    return 0
}

# Monitorear túneles en tiempo real
monitor_tunnels() {
    local interval="${1:-5}"

    log_info "Iniciando monitoreo de túneles (intervalo: ${interval}s)"
    echo "Presione Ctrl+C para detener"
    echo ""

    while true; do
        clear
        echo "=== Monitoreo de Túneles SSH Inversos ==="
        echo "Actualización: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        get_tunnel_statistics
        echo ""

        list_tunnels active
        echo ""

        sleep "${interval}"
    done
}

# Exportar estado de túneles a JSON
export_tunnel_status() {
    local output_file="${1:-/tmp/tunnel_status.json}"

    echo "{" > "${output_file}"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "${output_file}"
    echo "  \"tunnels\": [" >> "${output_file}"

    local first=true
    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        if [[ "${first}" == "false" ]]; then
            echo "," >> "${output_file}"
        fi
        first=false

        local tunnel_status="inactive"
        local pid="null"
        local remote_addr="null"

        if is_tunnel_active "${port}"; then
            tunnel_status="active"
            local tunnel_info
            tunnel_info=$(get_tunnel_info "${port}")
            if [[ -n "${tunnel_info}" ]] && [[ "${tunnel_info}" != "inactive" ]]; then
                pid=$(echo "${tunnel_info}" | cut -d'|' -f1)
                remote_addr="\"$(echo "${tunnel_info}" | cut -d'|' -f2)\""
            fi
        fi

        cat >> "${output_file}" << EOF
    {
      "device_id": "${device_id}",
      "port": ${port},
      "tunnel_status": "${tunnel_status}",
      "device_status": "${status}",
      "pid": ${pid},
      "remote_address": ${remote_addr},
      "fingerprint": "${fingerprint}",
      "registered_date": "${reg_date}"
    }
EOF
    done < "${DEVICE_MAPPING_FILE}"

    echo "" >> "${output_file}"
    echo "  ]" >> "${output_file}"
    echo "}" >> "${output_file}"

    log_info "Estado exportado a: ${output_file}"
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Gestor de Túneles SSH Inversos para Dispositivos IoT

COMANDOS:
  list [filter]              Listar túneles (all|active|inactive)
  stats                      Mostrar estadísticas de túneles
  check <device_id>          Verificar salud de túnel específico
  close <device_id>          Cerrar túnel de dispositivo
  monitor [interval]         Monitorear túneles en tiempo real
  export [output_file]       Exportar estado a JSON
  help                       Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") list active
  $(basename "$0") stats
  $(basename "$0") check a1b2c3d4...
  $(basename "$0") close a1b2c3d4...
  $(basename "$0") monitor 10
  $(basename "$0") export /tmp/status.json

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        list)
            list_tunnels "${2:-all}"
            ;;
        stats)
            get_tunnel_statistics
            ;;
        check)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            check_tunnel_health "$2"
            ;;
        close)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            close_tunnel "$2"
            ;;
        monitor)
            monitor_tunnels "${2:-5}"
            ;;
        export)
            export_tunnel_status "${2:-/tmp/tunnel_status.json}"
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
