#!/bin/bash
#
# key_rotation.sh - Sistema de Rotación de Claves SSH
# Gestiona la rotación periódica de claves SSH para mejorar seguridad
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT_DIR="${SCRIPT_DIR}/../server/scripts"
KEYGEN_SCRIPT="${SCRIPT_DIR}/keygen.sh"
DEVICE_REGISTRY_SCRIPT="${SERVER_SCRIPT_DIR}/device_registry.sh"
LOG_FILE="/var/log/iot-ssh-tunnel/key_rotation.log"
ROTATION_DIR="/var/lib/iot-ssh-tunnel/key_rotation"
BACKUP_RETENTION_DAYS=90

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Inicializar
initialize() {
    mkdir -p "${ROTATION_DIR}"
    mkdir -p "${ROTATION_DIR}/backups"
    mkdir -p "${ROTATION_DIR}/new_keys"
    mkdir -p "$(dirname "${LOG_FILE}")"

    if [[ ! -x "${KEYGEN_SCRIPT}" ]]; then
        log_error "Script keygen.sh no encontrado o no ejecutable: ${KEYGEN_SCRIPT}"
        exit 1
    fi
}

# Crear backup de clave actual
backup_key() {
    local key_path="$1"
    local device_id="${2:-unknown}"

    if [[ ! -f "${key_path}" ]]; then
        log_error "Clave no encontrada para backup: ${key_path}"
        return 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${ROTATION_DIR}/backups/${device_id}_${timestamp}"

    mkdir -p "${backup_dir}"

    log_info "Creando backup de clave: ${device_id}"

    # Copiar clave privada y pública
    cp "${key_path}" "${backup_dir}/"
    if [[ -f "${key_path}.pub" ]]; then
        cp "${key_path}.pub" "${backup_dir}/"
    fi

    # Guardar metadata
    cat > "${backup_dir}/metadata.txt" << EOF
Device ID: ${device_id}
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Original Path: ${key_path}
Fingerprint: $(ssh-keygen -lf "${key_path}.pub" 2>/dev/null | awk '{print $2}' || echo "N/A")
EOF

    log_success "Backup creado: ${backup_dir}"
    echo "${backup_dir}"
    return 0
}

# Rotar clave de un dispositivo
rotate_device_key() {
    local device_id="$1"
    local key_path="$2"
    local key_type="${3:-ed25519}"

    log_info "Iniciando rotación de clave para dispositivo: ${device_id}"

    # Verificar que la clave actual existe
    if [[ ! -f "${key_path}" ]]; then
        log_error "Clave actual no encontrada: ${key_path}"
        return 1
    fi

    # Crear backup de clave actual
    local backup_dir
    backup_dir=$(backup_key "${key_path}" "${device_id}") || {
        log_error "Fallo al crear backup"
        return 1
    }

    # Generar nueva clave
    local new_key_dir="${ROTATION_DIR}/new_keys/${device_id}_$(date +%Y%m%d)"
    mkdir -p "${new_key_dir}"
    local new_key_path="${new_key_dir}/tunnel_key"

    log_info "Generando nueva clave (tipo: ${key_type})"

    if ! "${KEYGEN_SCRIPT}" generate "${new_key_path}" "${key_type}" "rotated-${device_id}" &>> "${LOG_FILE}"; then
        log_error "Fallo al generar nueva clave"
        return 1
    fi

    log_success "Nueva clave generada: ${new_key_path}"

    # Mostrar instrucciones para deployment
    echo ""
    echo "==============================================="
    echo "Rotación de Clave - Instrucciones de Deployment"
    echo "==============================================="
    echo ""
    echo "Device ID: ${device_id}"
    echo ""
    echo "1. BACKUP (Completado)"
    echo "   Ubicación: ${backup_dir}"
    echo ""
    echo "2. NUEVA CLAVE"
    echo "   Privada: ${new_key_path}"
    echo "   Pública: ${new_key_path}.pub"
    echo ""
    echo "3. DEPLOYMENT EN DISPOSITIVO:"
    echo "   a. Copiar nueva clave privada al dispositivo:"
    echo "      scp ${new_key_path} device:/etc/iot-ssh-tunnel/tunnel_key"
    echo ""
    echo "   b. Establecer permisos correctos:"
    echo "      ssh device 'chmod 600 /etc/iot-ssh-tunnel/tunnel_key'"
    echo ""
    echo "   c. Reiniciar servicio de túnel:"
    echo "      ssh device 'systemctl restart iot-ssh-tunnel'"
    echo ""
    echo "4. ACTUALIZACIÓN EN SERVIDOR:"
    echo "   Ejecute el siguiente comando en el servidor:"
    echo "   ${DEVICE_REGISTRY_SCRIPT} update-key ${device_id} ${new_key_path}.pub"
    echo ""
    echo "5. VERIFICACIÓN:"
    echo "   Verifique que el túnel se reestablece correctamente"
    echo ""
    echo "Clave pública (para referencia):"
    cat "${new_key_path}.pub"
    echo ""
    echo "==============================================="

    # Guardar registro de rotación
    local rotation_log="${ROTATION_DIR}/rotation_history.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S')|${device_id}|${key_type}|${backup_dir}|${new_key_path}" >> "${rotation_log}"

    log_success "Rotación de clave completada para ${device_id}"
    return 0
}

# Rotar múltiples claves en batch
batch_rotate() {
    local device_list_file="$1"
    local key_type="${2:-ed25519}"

    if [[ ! -f "${device_list_file}" ]]; then
        log_error "Archivo de lista de dispositivos no encontrado: ${device_list_file}"
        return 1
    fi

    log_info "Iniciando rotación batch desde: ${device_list_file}"

    local total=0
    local success=0
    local failed=0

    while IFS='|' read -r device_id key_path; do
        # Saltar líneas de comentario
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        ((total++))

        echo ""
        echo "----------------------------------------"
        log_info "Procesando dispositivo ${total}: ${device_id}"

        if rotate_device_key "${device_id}" "${key_path}" "${key_type}"; then
            ((success++))
        else
            ((failed++))
            log_error "Fallo al rotar clave para ${device_id}"
        fi

        echo "----------------------------------------"
        echo ""

    done < "${device_list_file}"

    # Resumen
    echo ""
    echo "========================================"
    echo "Resumen de Rotación Batch"
    echo "========================================"
    echo "Total de dispositivos: ${total}"
    echo "Exitosos: ${success}"
    echo "Fallidos: ${failed}"
    echo "========================================"

    return 0
}

# Limpiar backups antiguos
cleanup_old_backups() {
    local retention_days="${1:-${BACKUP_RETENTION_DAYS}}"

    log_info "Limpiando backups anteriores a ${retention_days} días"

    local deleted_count=0

    find "${ROTATION_DIR}/backups" -type d -name "*_[0-9]*" -mtime "+${retention_days}" | while read -r backup_dir; do
        log_info "Eliminando backup antiguo: ${backup_dir}"
        rm -rf "${backup_dir}"
        ((deleted_count++))
    done

    log_success "Limpieza completada. Backups eliminados: ${deleted_count}"
    return 0
}

# Ver historial de rotaciones
show_rotation_history() {
    local device_id="${1:-}"
    local rotation_log="${ROTATION_DIR}/rotation_history.log"

    if [[ ! -f "${rotation_log}" ]]; then
        log_warning "No hay historial de rotaciones disponible"
        return 0
    fi

    echo "Historial de Rotaciones de Claves"
    echo "=================================="
    printf "%-20s %-34s %-10s %-40s\n" "FECHA" "DEVICE_ID" "KEY_TYPE" "BACKUP"

    while IFS='|' read -r date dev_id key_type backup_dir new_key; do
        if [[ -z "${device_id}" ]] || [[ "${dev_id}" == "${device_id}" ]]; then
            printf "%-20s %-34s %-10s %-40s\n" "${date}" "${dev_id:0:32}.." "${key_type}" "$(basename "${backup_dir}")"
        fi
    done < "${rotation_log}"
}

# Verificar edad de claves
check_key_age() {
    local key_path="$1"
    local warning_days="${2:-90}"

    if [[ ! -f "${key_path}" ]]; then
        log_error "Clave no encontrada: ${key_path}"
        return 1
    fi

    local key_date
    if [[ "$(uname)" == "Darwin" ]]; then
        key_date=$(stat -f %m "${key_path}")
    else
        key_date=$(stat -c %Y "${key_path}")
    fi

    local current_date
    current_date=$(date +%s)

    local age_days=$(( (current_date - key_date) / 86400 ))

    echo "Edad de la clave: ${age_days} días"

    if [[ ${age_days} -gt ${warning_days} ]]; then
        log_warning "La clave tiene más de ${warning_days} días. Se recomienda rotación."
        return 1
    else
        log_info "Edad de la clave dentro del rango aceptable"
        return 0
    fi
}

# Generar reporte de claves que requieren rotación
generate_rotation_report() {
    local device_mapping="$1"
    local max_age_days="${2:-90}"
    local output_file="${ROTATION_DIR}/rotation_needed_$(date +%Y%m%d).txt"

    if [[ ! -f "${device_mapping}" ]]; then
        log_error "Archivo de mapeo no encontrado: ${device_mapping}"
        return 1
    fi

    echo "# Dispositivos que Requieren Rotación de Claves" > "${output_file}"
    echo "# Generado: $(date '+%Y-%m-%d %H:%M:%S')" >> "${output_file}"
    echo "# Criterio: Claves con más de ${max_age_days} días" >> "${output_file}"
    echo "# Formato: DEVICE_ID|KEY_PATH|AGE_DAYS" >> "${output_file}"
    echo "" >> "${output_file}"

    local count=0

    while IFS='|' read -r device_id port fingerprint reg_date status; do
        if [[ "${device_id}" =~ ^# ]] || [[ -z "${device_id}" ]]; then
            continue
        fi

        # Aquí se necesitaría lógica para encontrar la ruta de la clave
        # Por ahora, se asume una convención de nombres
        local assumed_key_path="/etc/iot-ssh-tunnel/devices/${device_id}/tunnel_key"

        if [[ -f "${assumed_key_path}" ]]; then
            local key_date age_days

            if [[ "$(uname)" == "Darwin" ]]; then
                key_date=$(stat -f %m "${assumed_key_path}")
            else
                key_date=$(stat -c %Y "${assumed_key_path}")
            fi

            age_days=$(( ($(date +%s) - key_date) / 86400 ))

            if [[ ${age_days} -gt ${max_age_days} ]]; then
                echo "${device_id}|${assumed_key_path}|${age_days}" >> "${output_file}"
                ((count++))
            fi
        fi

    done < "${device_mapping}"

    log_info "Reporte generado: ${output_file}"
    log_info "Dispositivos que requieren rotación: ${count}"

    cat "${output_file}"
    return 0
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Sistema de Rotación de Claves SSH para Túneles IoT

COMANDOS:
  rotate <device_id> <key_path> [type]           Rotar clave de dispositivo
  batch <device_list_file> [type]                Rotar múltiples claves
  cleanup [retention_days]                       Limpiar backups antiguos
  history [device_id]                            Ver historial de rotaciones
  check-age <key_path> [warning_days]            Verificar edad de clave
  report <device_mapping> [max_age_days]         Generar reporte de rotación
  help                                           Mostrar esta ayuda

OPCIONES:
  type              Tipo de nueva clave (ed25519|rsa|ecdsa)
  retention_days    Días de retención de backups (default: 90)
  warning_days      Días antes de advertencia (default: 90)
  max_age_days      Edad máxima antes de rotación (default: 90)

EJEMPLOS:
  # Rotar clave de un dispositivo
  $(basename "$0") rotate a1b2c3... /etc/iot-ssh-tunnel/tunnel_key ed25519

  # Rotar múltiples claves desde archivo
  $(basename "$0") batch /tmp/devices_to_rotate.txt

  # Limpiar backups de más de 90 días
  $(basename "$0") cleanup 90

  # Ver historial de rotaciones
  $(basename "$0") history

  # Verificar edad de una clave
  $(basename "$0") check-age /etc/iot-ssh-tunnel/tunnel_key 90

  # Generar reporte de claves que necesitan rotación
  $(basename "$0") report /path/to/device_mapping 90

FORMATO DE ARCHIVO PARA BATCH:
  device_id|/path/to/current/key
  a1b2c3d4e5f6...|/etc/iot-ssh-tunnel/device1/key
  f6e5d4c3b2a1...|/etc/iot-ssh-tunnel/device2/key

MEJORES PRÁCTICAS:
  1. Rote claves cada 90 días como mínimo
  2. Use ed25519 para nuevas claves (más seguro)
  3. Mantenga backups por al menos 90 días
  4. Documente todas las rotaciones
  5. Verifique conectividad después de cada rotación
  6. Programe rotaciones durante ventanas de mantenimiento

PROCESO DE ROTACIÓN:
  1. Backup de clave actual
  2. Generación de nueva clave
  3. Deployment en dispositivo
  4. Actualización en servidor
  5. Verificación de conectividad
  6. Limpieza de backups antiguos

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        rotate)
            if [[ $# -lt 3 ]]; then
                log_error "Faltan argumentos para rotate"
                show_help
                exit 1
            fi
            rotate_device_key "$2" "$3" "${4:-ed25519}"
            ;;
        batch)
            if [[ $# -lt 2 ]]; then
                log_error "Falta archivo de lista de dispositivos"
                show_help
                exit 1
            fi
            batch_rotate "$2" "${3:-ed25519}"
            ;;
        cleanup)
            cleanup_old_backups "${2:-${BACKUP_RETENTION_DAYS}}"
            ;;
        history)
            show_rotation_history "${2:-}"
            ;;
        check-age)
            if [[ $# -lt 2 ]]; then
                log_error "Falta ruta de clave"
                show_help
                exit 1
            fi
            check_key_age "$2" "${3:-90}"
            ;;
        report)
            if [[ $# -lt 2 ]]; then
                log_error "Falta archivo de mapeo de dispositivos"
                show_help
                exit 1
            fi
            generate_rotation_report "$2" "${3:-90}"
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
