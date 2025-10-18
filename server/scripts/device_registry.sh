#!/bin/bash
#
# device_registry.sh - Sistema de Registro de Dispositivos IoT
# Gestiona el registro centralizado de dispositivos con asignación de puertos
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_CONFIG_DIR="${SCRIPT_DIR}/../configs"
DEVICE_MAPPING_FILE="${SERVER_CONFIG_DIR}/device_mapping"
LOG_FILE="/var/log/iot-ssh-tunnel/device_registry.log"
AUTHORIZED_KEYS_DIR="/home/iot-tunnel/.ssh"
PORT_RANGE_START=10000
PORT_RANGE_END=20000

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

# Inicializar estructura de archivos
initialize() {
    mkdir -p "${SERVER_CONFIG_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"

    if [[ ! -f "${DEVICE_MAPPING_FILE}" ]]; then
        echo "# Device Mapping File - Format: DEVICE_ID|PORT|PUBLIC_KEY_FINGERPRINT|REGISTERED_DATE|STATUS" > "${DEVICE_MAPPING_FILE}"
        log_info "Archivo de mapeo de dispositivos creado"
    fi

    if [[ ! -d "${AUTHORIZED_KEYS_DIR}" ]]; then
        log_error "Directorio de claves SSH no encontrado: ${AUTHORIZED_KEYS_DIR}"
        exit 1
    fi
}

# Obtener próximo puerto disponible
get_next_available_port() {
    local used_ports
    used_ports=$(grep -v '^#' "${DEVICE_MAPPING_FILE}" 2>/dev/null | cut -d'|' -f2 | sort -n)

    for port in $(seq ${PORT_RANGE_START} ${PORT_RANGE_END}); do
        if ! echo "${used_ports}" | grep -q "^${port}$"; then
            echo "${port}"
            return 0
        fi
    done

    log_error "No hay puertos disponibles en el rango ${PORT_RANGE_START}-${PORT_RANGE_END}"
    return 1
}

# Validar identificador de dispositivo
validate_device_id() {
    local device_id="$1"

    if [[ ! "${device_id}" =~ ^[a-f0-9]{32}$ ]]; then
        log_error "ID de dispositivo inválido: ${device_id} (debe ser un hash MD5 de 32 caracteres)"
        return 1
    fi

    return 0
}

# Verificar si dispositivo ya está registrado
is_device_registered() {
    local device_id="$1"
    grep -q "^${device_id}|" "${DEVICE_MAPPING_FILE}" 2>/dev/null
}

# Registrar nuevo dispositivo
register_device() {
    local device_id="$1"
    local public_key_file="$2"

    # Validaciones
    validate_device_id "${device_id}" || return 1

    if [[ ! -f "${public_key_file}" ]]; then
        log_error "Archivo de clave pública no encontrado: ${public_key_file}"
        return 1
    fi

    if is_device_registered "${device_id}"; then
        log_warning "Dispositivo ${device_id} ya está registrado"
        return 1
    fi

    # Obtener puerto disponible
    local port
    port=$(get_next_available_port) || return 1

    # Obtener fingerprint de la clave pública
    local fingerprint
    fingerprint=$(ssh-keygen -lf "${public_key_file}" | awk '{print $2}')

    # Registrar en mapping file
    local registration_date
    registration_date=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${device_id}|${port}|${fingerprint}|${registration_date}|active" >> "${DEVICE_MAPPING_FILE}"

    # Agregar clave pública a authorized_keys con restricciones
    local authorized_keys_file="${AUTHORIZED_KEYS_DIR}/authorized_keys"
    local restriction="command=\"echo 'Tunnel only'\",no-agent-forwarding,no-X11-forwarding,permitopen=\"localhost:${port}\""

    echo "${restriction} $(cat "${public_key_file}")" >> "${authorized_keys_file}"

    log_info "Dispositivo registrado exitosamente:"
    log_info "  Device ID: ${device_id}"
    log_info "  Puerto asignado: ${port}"
    log_info "  Fingerprint: ${fingerprint}"

    return 0
}

# Listar dispositivos registrados
list_devices() {
    local filter="${1:-all}"

    echo "Dispositivos registrados:"
    echo "------------------------"
    printf "%-34s %-8s %-50s %-20s %-10s\n" "DEVICE_ID" "PORT" "FINGERPRINT" "REGISTERED" "STATUS"

    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        if [[ "${filter}" == "all" ]] || [[ "${status}" == "${filter}" ]]; then
            printf "%-34s %-8s %-50s %-20s %-10s\n" "${device_id}" "${port}" "${fingerprint}" "${reg_date}" "${status}"
        fi
    done < "${DEVICE_MAPPING_FILE}"
}

# Obtener información de dispositivo específico
get_device_info() {
    local device_id="$1"

    validate_device_id "${device_id}" || return 1

    local device_info
    device_info=$(grep "^${device_id}|" "${DEVICE_MAPPING_FILE}" 2>/dev/null)

    if [[ -z "${device_info}" ]]; then
        log_error "Dispositivo no encontrado: ${device_id}"
        return 1
    fi

    IFS='|' read -r dev_id port fingerprint reg_date status <<< "${device_info}"

    echo "Información del dispositivo:"
    echo "  Device ID: ${dev_id}"
    echo "  Puerto: ${port}"
    echo "  Fingerprint: ${fingerprint}"
    echo "  Fecha de registro: ${reg_date}"
    echo "  Estado: ${status}"

    return 0
}

# Desactivar dispositivo
deactivate_device() {
    local device_id="$1"

    validate_device_id "${device_id}" || return 1

    if ! is_device_registered "${device_id}"; then
        log_error "Dispositivo no registrado: ${device_id}"
        return 1
    fi

    # Cambiar estado a inactive
    sed -i "s/^\(${device_id}|.*|.*|.*|\)active$/\1inactive/" "${DEVICE_MAPPING_FILE}"

    log_info "Dispositivo ${device_id} desactivado"
    return 0
}

# Reactivar dispositivo
reactivate_device() {
    local device_id="$1"

    validate_device_id "${device_id}" || return 1

    if ! is_device_registered "${device_id}"; then
        log_error "Dispositivo no registrado: ${device_id}"
        return 1
    fi

    # Cambiar estado a active
    sed -i "s/^\(${device_id}|.*|.*|.*|\)inactive$/\1active/" "${DEVICE_MAPPING_FILE}"

    log_info "Dispositivo ${device_id} reactivado"
    return 0
}

# Eliminar dispositivo
remove_device() {
    local device_id="$1"

    validate_device_id "${device_id}" || return 1

    if ! is_device_registered "${device_id}"; then
        log_error "Dispositivo no registrado: ${device_id}"
        return 1
    fi

    # Obtener fingerprint para eliminar de authorized_keys
    local fingerprint
    fingerprint=$(grep "^${device_id}|" "${DEVICE_MAPPING_FILE}" | cut -d'|' -f3)

    # Eliminar de mapping file
    sed -i "/^${device_id}|/d" "${DEVICE_MAPPING_FILE}"

    # Eliminar de authorized_keys
    local authorized_keys_file="${AUTHORIZED_KEYS_DIR}/authorized_keys"
    if [[ -f "${authorized_keys_file}" ]]; then
        grep -v "${fingerprint}" "${authorized_keys_file}" > "${authorized_keys_file}.tmp" || true
        mv "${authorized_keys_file}.tmp" "${authorized_keys_file}"
    fi

    log_info "Dispositivo ${device_id} eliminado completamente"
    return 0
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Sistema de Registro de Dispositivos IoT para Túneles SSH Inversos

COMANDOS:
  register <device_id> <public_key_file>   Registrar nuevo dispositivo
  list [filter]                            Listar dispositivos (all|active|inactive)
  info <device_id>                         Obtener información de dispositivo
  deactivate <device_id>                   Desactivar dispositivo
  reactivate <device_id>                   Reactivar dispositivo
  remove <device_id>                       Eliminar dispositivo completamente
  help                                     Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") register a1b2c3d4... /path/to/device_key.pub
  $(basename "$0") list active
  $(basename "$0") info a1b2c3d4...
  $(basename "$0") deactivate a1b2c3d4...

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        register)
            if [[ $# -lt 3 ]]; then
                log_error "Faltan argumentos para register"
                show_help
                exit 1
            fi
            register_device "$2" "$3"
            ;;
        list)
            list_devices "${2:-all}"
            ;;
        info)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            get_device_info "$2"
            ;;
        deactivate)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            deactivate_device "$2"
            ;;
        reactivate)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            reactivate_device "$2"
            ;;
        remove)
            if [[ $# -lt 2 ]]; then
                log_error "Falta device_id"
                show_help
                exit 1
            fi
            remove_device "$2"
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
