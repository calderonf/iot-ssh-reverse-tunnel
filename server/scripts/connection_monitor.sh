#!/bin/bash
#
# connection_monitor.sh - Monitor de Conexiones SSH
# Monitorea y registra actividad de conexiones SSH inversas
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_DIR="${SCRIPT_DIR}/../configs"
DEVICE_MAPPING_FILE="${SERVER_CONFIG_DIR}/device_mapping"
LOG_FILE="/var/log/iot-ssh-tunnel/connection_monitor.log"
METRICS_DIR="/var/lib/iot-ssh-tunnel/metrics"
ALERT_SCRIPT="${SCRIPT_DIR}/alert_handler.sh"
CHECK_INTERVAL=60
ALERT_THRESHOLD_DISCONNECTED=300

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

log_metric() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$1" >> "${METRICS_DIR}/metrics.log"
}

# Inicializar
initialize() {
    mkdir -p "${METRICS_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"

    if [[ ! -f "${DEVICE_MAPPING_FILE}" ]]; then
        log_error "Archivo de mapeo de dispositivos no encontrado: ${DEVICE_MAPPING_FILE}"
        exit 1
    fi

    # Crear archivo de estado si no existe
    if [[ ! -f "${METRICS_DIR}/connection_state.dat" ]]; then
        echo "# device_id|last_seen|connection_status|alert_sent" > "${METRICS_DIR}/connection_state.dat"
    fi
}

# Verificar si puerto tiene túnel activo
is_tunnel_active() {
    local port="$1"
    ss -tln 2>/dev/null | grep -q ":${port}[[:space:]]" || \
    netstat -tln 2>/dev/null | grep -q ":${port}[[:space:]]"
}

# Obtener timestamp actual
get_timestamp() {
    date +%s
}

# Actualizar estado de conexión del dispositivo
update_connection_state() {
    local device_id="$1"
    local status="$2"
    local timestamp
    timestamp=$(get_timestamp)

    local state_file="${METRICS_DIR}/connection_state.dat"
    local temp_file="${state_file}.tmp"

    # Verificar si dispositivo ya tiene entrada
    if grep -q "^${device_id}|" "${state_file}" 2>/dev/null; then
        # Actualizar entrada existente
        while IFS='|' read -r dev_id last_seen conn_status alert_sent; do
            if [[ "${dev_id}" == "${device_id}" ]]; then
                echo "${dev_id}|${timestamp}|${status}|${alert_sent:-0}"
            else
                echo "${dev_id}|${last_seen}|${conn_status}|${alert_sent}"
            fi
        done < "${state_file}" > "${temp_file}"
        mv "${temp_file}" "${state_file}"
    else
        # Agregar nueva entrada
        echo "${device_id}|${timestamp}|${status}|0" >> "${state_file}"
    fi

    log_debug "Estado actualizado para ${device_id}: ${status}"
}

# Obtener estado de conexión del dispositivo
get_connection_state() {
    local device_id="$1"
    local state_file="${METRICS_DIR}/connection_state.dat"

    grep "^${device_id}|" "${state_file}" 2>/dev/null || echo "${device_id}|0|unknown|0"
}

# Enviar alerta
send_alert() {
    local device_id="$1"
    local alert_type="$2"
    local message="$3"

    log_warning "ALERTA [${alert_type}] - Dispositivo: ${device_id} - ${message}"

    # Ejecutar script de alertas si existe
    if [[ -x "${ALERT_SCRIPT}" ]]; then
        "${ALERT_SCRIPT}" "${device_id}" "${alert_type}" "${message}" &
    fi

    # Marcar alerta como enviada
    local state_file="${METRICS_DIR}/connection_state.dat"
    local temp_file="${state_file}.tmp"

    while IFS='|' read -r dev_id last_seen conn_status alert_sent; do
        if [[ "${dev_id}" == "${device_id}" ]]; then
            echo "${dev_id}|${last_seen}|${conn_status}|$(get_timestamp)"
        else
            echo "${dev_id}|${last_seen}|${conn_status}|${alert_sent}"
        fi
    done < "${state_file}" > "${temp_file}"
    mv "${temp_file}" "${state_file}"
}

# Verificar y monitorear todos los dispositivos
monitor_all_devices() {
    local current_time
    current_time=$(get_timestamp)

    local total_devices=0
    local connected_devices=0
    local disconnected_devices=0
    local new_connections=0
    local lost_connections=0

    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        # Solo monitorear dispositivos activos
        if [[ "${status}" != "active" ]]; then
            continue
        fi

        ((total_devices++))

        local current_status="disconnected"
        if is_tunnel_active "${port}"; then
            current_status="connected"
            ((connected_devices++))
        else
            ((disconnected_devices++))
        fi

        # Obtener estado anterior
        local previous_state
        previous_state=$(get_connection_state "${device_id}")
        IFS='|' read -r _ last_seen prev_status alert_sent <<< "${previous_state}"

        # Detectar cambios de estado
        if [[ "${prev_status}" != "${current_status}" ]]; then
            if [[ "${current_status}" == "connected" ]]; then
                log_info "Dispositivo CONECTADO: ${device_id} (puerto ${port})"
                ((new_connections++))

                # Reset alert flag en nueva conexión
                send_alert "${device_id}" "CONNECTION_RESTORED" "Dispositivo reconectado exitosamente"
            else
                log_warning "Dispositivo DESCONECTADO: ${device_id} (puerto ${port})"
                ((lost_connections++))
            fi
        fi

        # Verificar si se debe enviar alerta por desconexión prolongada
        if [[ "${current_status}" == "disconnected" ]]; then
            local time_since_last_seen=$((current_time - last_seen))
            local time_since_alert=$((current_time - alert_sent))

            if [[ ${time_since_last_seen} -gt ${ALERT_THRESHOLD_DISCONNECTED} ]] && \
               [[ ${time_since_alert} -gt ${ALERT_THRESHOLD_DISCONNECTED} ]]; then
                send_alert "${device_id}" "PROLONGED_DISCONNECTION" \
                    "Dispositivo desconectado por más de $((time_since_last_seen / 60)) minutos"
            fi
        fi

        # Actualizar estado
        update_connection_state "${device_id}" "${current_status}"

    done < "${DEVICE_MAPPING_FILE}"

    # Registrar métricas
    log_metric "total=${total_devices}|connected=${connected_devices}|disconnected=${disconnected_devices}|new=${new_connections}|lost=${lost_connections}"

    # Mostrar resumen si hay cambios
    if [[ ${new_connections} -gt 0 ]] || [[ ${lost_connections} -gt 0 ]]; then
        log_info "Resumen: ${connected_devices}/${total_devices} conectados, ${new_connections} nuevas conexiones, ${lost_connections} pérdidas"
    fi
}

# Generar reporte de disponibilidad
generate_availability_report() {
    local days="${1:-7}"
    local report_file="${METRICS_DIR}/availability_report_$(date +%Y%m%d).txt"

    echo "Reporte de Disponibilidad - Últimos ${days} días" > "${report_file}"
    echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')" >> "${report_file}"
    echo "========================================" >> "${report_file}"
    echo "" >> "${report_file}"

    # Analizar métricas de los últimos días
    local cutoff_date
    cutoff_date=$(date -d "${days} days ago" '+%Y-%m-%d' 2>/dev/null || date -v-"${days}"d '+%Y-%m-%d')

    if [[ -f "${METRICS_DIR}/metrics.log" ]]; then
        local total_checks=0
        local total_connected=0

        while IFS='|' read -r timestamp metrics; do
            local check_date="${timestamp%% *}"

            if [[ "${check_date}" > "${cutoff_date}" ]] || [[ "${check_date}" == "${cutoff_date}" ]]; then
                ((total_checks++))

                # Extraer número de dispositivos conectados
                local connected
                connected=$(echo "${metrics}" | grep -oP 'connected=\K[0-9]+' || echo 0)
                total_connected=$((total_connected + connected))
            fi
        done < "${METRICS_DIR}/metrics.log"

        if [[ ${total_checks} -gt 0 ]]; then
            local avg_connected=$((total_connected / total_checks))
            echo "Promedio de dispositivos conectados: ${avg_connected}" >> "${report_file}"
        fi
    fi

    # Estado actual de cada dispositivo
    echo "" >> "${report_file}"
    echo "Estado Actual de Dispositivos:" >> "${report_file}"
    echo "-------------------------------" >> "${report_file}"

    while IFS='|' read -r device_id last_seen status alert_sent; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        local last_seen_date
        last_seen_date=$(date -d "@${last_seen}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "${last_seen}" '+%Y-%m-%d %H:%M:%S')

        echo "Dispositivo: ${device_id}" >> "${report_file}"
        echo "  Estado: ${status}" >> "${report_file}"
        echo "  Última vez visto: ${last_seen_date}" >> "${report_file}"
        echo "" >> "${report_file}"
    done < "${METRICS_DIR}/connection_state.dat"

    log_info "Reporte generado: ${report_file}"
    cat "${report_file}"
}

# Modo daemon - monitoreo continuo
run_daemon() {
    local interval="${1:-${CHECK_INTERVAL}}"

    log_info "Iniciando monitor en modo daemon (intervalo: ${interval}s)"

    # Crear archivo PID
    echo $$ > "${METRICS_DIR}/monitor.pid"

    # Trap para limpieza
    trap cleanup EXIT INT TERM

    while true; do
        monitor_all_devices
        sleep "${interval}"
    done
}

# Limpieza al salir
cleanup() {
    log_info "Deteniendo monitor de conexiones"
    rm -f "${METRICS_DIR}/monitor.pid"
    exit 0
}

# Detener daemon
stop_daemon() {
    if [[ -f "${METRICS_DIR}/monitor.pid" ]]; then
        local pid
        pid=$(cat "${METRICS_DIR}/monitor.pid")

        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}"
            log_info "Monitor detenido (PID: ${pid})"
        else
            log_warning "No se encontró proceso activo con PID: ${pid}"
            rm -f "${METRICS_DIR}/monitor.pid"
        fi
    else
        log_error "No se encontró archivo PID. Monitor no está ejecutándose."
        return 1
    fi
}

# Ver estado del daemon
daemon_status() {
    if [[ -f "${METRICS_DIR}/monitor.pid" ]]; then
        local pid
        pid=$(cat "${METRICS_DIR}/monitor.pid")

        if kill -0 "${pid}" 2>/dev/null; then
            echo -e "${GREEN}Monitor activo (PID: ${pid})${NC}"
            return 0
        else
            echo -e "${RED}Monitor no está ejecutándose (PID obsoleto: ${pid})${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Monitor no está ejecutándose${NC}"
        return 1
    fi
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Monitor de Conexiones SSH Inversas para Dispositivos IoT

COMANDOS:
  check                      Verificar estado de todas las conexiones
  daemon [interval]          Ejecutar en modo daemon (default: 60s)
  stop                       Detener daemon
  status                     Ver estado del daemon
  report [days]              Generar reporte de disponibilidad
  help                       Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") check
  $(basename "$0") daemon 30
  $(basename "$0") stop
  $(basename "$0") report 7

CONFIGURACIÓN:
  LOG_FILE: ${LOG_FILE}
  METRICS_DIR: ${METRICS_DIR}
  CHECK_INTERVAL: ${CHECK_INTERVAL}s
  ALERT_THRESHOLD: ${ALERT_THRESHOLD_DISCONNECTED}s

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        check)
            monitor_all_devices
            ;;
        daemon)
            run_daemon "${2:-${CHECK_INTERVAL}}"
            ;;
        stop)
            stop_daemon
            ;;
        status)
            daemon_status
            ;;
        report)
            generate_availability_report "${2:-7}"
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
