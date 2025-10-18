#!/bin/bash
#
# device_identifier.sh - Generador de Identificador Único de Dispositivo
# Crea identificador basado en machine-id o características de hardware
#

set -euo pipefail

# Configuración
DEVICE_ID_FILE="/etc/iot-ssh-tunnel/device_id"
LOG_FILE="/var/log/iot-ssh-tunnel/device_identifier.log"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Inicializar
initialize() {
    mkdir -p "$(dirname "${DEVICE_ID_FILE}")"
    mkdir -p "$(dirname "${LOG_FILE}")"
}

# Generar ID desde machine-id
generate_from_machine_id() {
    local machine_id=""

    # Intentar obtener machine-id de systemd
    if [[ -f /etc/machine-id ]]; then
        machine_id=$(cat /etc/machine-id)
        log_info "Machine ID obtenido de /etc/machine-id"
    elif [[ -f /var/lib/dbus/machine-id ]]; then
        machine_id=$(cat /var/lib/dbus/machine-id)
        log_info "Machine ID obtenido de /var/lib/dbus/machine-id"
    else
        log_warning "No se encontró machine-id en ubicaciones estándar"
        return 1
    fi

    # Convertir a formato consistente (MD5)
    echo -n "${machine_id}" | md5sum | awk '{print $1}'
    return 0
}

# Generar ID desde características de hardware
generate_from_hardware() {
    local hw_info=""

    # Recopilar información de hardware disponible
    if command -v dmidecode &> /dev/null; then
        # UUID de la placa base
        local board_uuid
        board_uuid=$(sudo dmidecode -s system-uuid 2>/dev/null || echo "")
        hw_info="${hw_info}${board_uuid}"
    fi

    # Serial de la CPU
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_serial
        cpu_serial=$(grep -m1 'Serial' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo "")
        hw_info="${hw_info}${cpu_serial}"
    fi

    # MAC Address de interfaces de red
    local mac_addresses
    mac_addresses=$(ip link show 2>/dev/null | grep -oP '(?<=link/ether )[0-9a-f:]+' | sort | head -n1 || echo "")
    hw_info="${hw_info}${mac_addresses}"

    # Si no se pudo obtener información de hardware
    if [[ -z "${hw_info}" ]]; then
        log_error "No se pudo obtener información de hardware"
        return 1
    fi

    log_info "ID generado desde características de hardware"
    echo -n "${hw_info}" | md5sum | awk '{print $1}'
    return 0
}

# Generar ID personalizado
generate_custom_id() {
    local custom_data="$1"

    if [[ -z "${custom_data}" ]]; then
        log_error "No se proporcionó información para generar ID personalizado"
        return 1
    fi

    log_info "ID generado desde datos personalizados"
    echo -n "${custom_data}" | md5sum | awk '{print $1}'
    return 0
}

# Obtener o generar device ID
get_device_id() {
    local force_regenerate="${1:-false}"

    # Si ya existe y no se fuerza regeneración, devolver existente
    if [[ -f "${DEVICE_ID_FILE}" ]] && [[ "${force_regenerate}" != "true" ]]; then
        cat "${DEVICE_ID_FILE}"
        return 0
    fi

    # Intentar generar desde machine-id
    local device_id
    device_id=$(generate_from_machine_id) || \
    device_id=$(generate_from_hardware) || {
        log_error "No se pudo generar device ID"
        return 1
    }

    # Guardar device ID
    echo "${device_id}" > "${DEVICE_ID_FILE}"
    chmod 600 "${DEVICE_ID_FILE}"

    log_info "Device ID generado y guardado: ${device_id}"
    echo "${device_id}"
    return 0
}

# Validar formato de device ID
validate_device_id() {
    local device_id="$1"

    if [[ ! "${device_id}" =~ ^[a-f0-9]{32}$ ]]; then
        log_error "Formato de device ID inválido: ${device_id}"
        return 1
    fi

    log_info "Device ID válido: ${device_id}"
    return 0
}

# Mostrar información del dispositivo
show_device_info() {
    echo "Información del Dispositivo IoT"
    echo "================================"

    # Device ID
    if [[ -f "${DEVICE_ID_FILE}" ]]; then
        local device_id
        device_id=$(cat "${DEVICE_ID_FILE}")
        echo "Device ID: ${device_id}"
        echo "Archivo: ${DEVICE_ID_FILE}"
    else
        echo "Device ID: No configurado"
    fi

    echo ""
    echo "Información del Sistema:"

    # Hostname
    echo "Hostname: $(hostname)"

    # Machine ID
    if [[ -f /etc/machine-id ]]; then
        echo "Machine ID: $(cat /etc/machine-id)"
    fi

    # MAC Addresses
    echo "Interfaces de red:"
    ip link show 2>/dev/null | grep -A1 '^[0-9]' | grep -oP '(?<=link/ether )[0-9a-f:]+' || echo "  No disponible"

    # Información de CPU
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model
        cpu_model=$(grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs || echo "No disponible")
        echo "CPU: ${cpu_model}"
    fi

    # Sistema operativo
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "OS: ${PRETTY_NAME:-${NAME} ${VERSION}}"
    fi

    # Kernel
    echo "Kernel: $(uname -r)"

    # Arquitectura
    echo "Arquitectura: $(uname -m)"
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Generador de Identificador Único para Dispositivos IoT

COMANDOS:
  get                        Obtener device ID (generar si no existe)
  regenerate                 Forzar regeneración de device ID
  custom <data>              Generar ID desde datos personalizados
  validate <device_id>       Validar formato de device ID
  info                       Mostrar información del dispositivo
  help                       Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") get
  $(basename "$0") regenerate
  $(basename "$0") custom "serial:ABC123"
  $(basename "$0") validate a1b2c3d4e5f6...
  $(basename "$0") info

ARCHIVOS:
  Device ID: ${DEVICE_ID_FILE}
  Log: ${LOG_FILE}

DESCRIPCIÓN:
  Este script genera un identificador único para el dispositivo IoT
  basándose en machine-id o características de hardware. El ID se
  almacena persistentemente y se utiliza para registrar el dispositivo
  en el servidor de túneles SSH.

EOF
}

# Main
main() {
    initialize

    local command="${1:-get}"

    case "${command}" in
        get)
            get_device_id "false"
            ;;
        regenerate)
            get_device_id "true"
            ;;
        custom)
            if [[ $# -lt 2 ]]; then
                log_error "Falta información para ID personalizado"
                show_help
                exit 1
            fi

            # Generar el ID personalizado
            local custom_id
            custom_id=$(generate_custom_id "$2")

            if [[ $? -eq 0 ]]; then
                # Guardar en /etc/iot-ssh-tunnel/device_id
                echo "${custom_id}" > "${DEVICE_ID_FILE}"
                chmod 600 "${DEVICE_ID_FILE}"
                log_info "Device ID personalizado guardado en ${DEVICE_ID_FILE}"

                # Mostrar el ID generado
                echo "${custom_id}"
            else
                log_error "Error al generar ID personalizado"
                exit 1
            fi
            ;;
        validate)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device ID para validar"
                show_help
                exit 1
            fi
            validate_device_id "$2"
            ;;
        info)
            show_device_info
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
