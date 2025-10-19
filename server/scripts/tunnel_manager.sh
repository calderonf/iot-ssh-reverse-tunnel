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
DEVICE_CREDENTIALS_FILE="${SERVER_CONFIG_DIR}/device_credentials"
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

    # Crear archivo de credenciales si no existe (con permisos restrictivos)
    if [[ ! -f "${DEVICE_CREDENTIALS_FILE}" ]]; then
        touch "${DEVICE_CREDENTIALS_FILE}"
        chmod 600 "${DEVICE_CREDENTIALS_FILE}"
        log_info "Archivo de credenciales creado: ${DEVICE_CREDENTIALS_FILE}"
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

# Buscar dispositivo por ID parcial (primeros 5+ caracteres)
find_device_by_prefix() {
    local prefix="$1"
    local matches

    if [[ ${#prefix} -lt 5 ]]; then
        log_error "El prefijo debe tener al menos 5 caracteres"
        return 1
    fi

    matches=$(grep "^${prefix}" "${DEVICE_MAPPING_FILE}" 2>/dev/null || true)

    if [[ -z "${matches}" ]]; then
        return 1
    fi

    local count
    count=$(echo "${matches}" | wc -l)

    if [[ ${count} -gt 1 ]]; then
        log_error "Múltiples dispositivos encontrados con prefijo '${prefix}':"
        echo "${matches}" | cut -d'|' -f1
        return 2
    fi

    echo "${matches}"
    return 0
}

# Guardar credenciales de dispositivo
save_device_credentials() {
    local device_id="$1"
    local username="$2"
    local has_password="${3:-false}"

    # Eliminar credenciales anteriores si existen
    if grep -q "^${device_id}|" "${DEVICE_CREDENTIALS_FILE}" 2>/dev/null; then
        sed -i "/^${device_id}|/d" "${DEVICE_CREDENTIALS_FILE}"
    fi

    # Guardar nuevas credenciales
    echo "${device_id}|${username}|${has_password}" >> "${DEVICE_CREDENTIALS_FILE}"
    log_info "Credenciales guardadas para dispositivo ${device_id:0:8}..."
}

# Obtener credenciales de dispositivo
get_device_credentials() {
    local device_id="$1"

    grep "^${device_id}|" "${DEVICE_CREDENTIALS_FILE}" 2>/dev/null || true
}

# Copiar clave SSH al dispositivo
copy_ssh_key_to_device() {
    local port="$1"
    local username="$2"
    local password="$3"

    # Verificar si existe clave SSH del servidor
    local ssh_key="${HOME}/.ssh/id_rsa.pub"
    if [[ ! -f "${ssh_key}" ]]; then
        ssh_key="${HOME}/.ssh/id_ed25519.pub"
        if [[ ! -f "${ssh_key}" ]]; then
            log_warning "No se encontró clave SSH pública. Generando nueva clave..."
            ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N "" -C "tunnel-manager@$(hostname)"
            ssh_key="${HOME}/.ssh/id_ed25519.pub"
        fi
    fi

    log_info "Copiando clave SSH al dispositivo..."

    # Usar sshpass si está disponible y se proporcionó contraseña
    if command -v sshpass &> /dev/null && [[ -n "${password}" ]]; then
        # Usar ssh-copy-id con sshpass
        if sshpass -p "${password}" ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost" 2>&1 | grep -q "Number of key(s) added:"; then
            log_info "Clave SSH copiada exitosamente"
            return 0
        else
            log_warning "No se pudo copiar la clave SSH automáticamente"
            return 1
        fi
    else
        log_info "Ingrese la contraseña cuando se solicite:"
        if ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost"; then
            log_info "Clave SSH copiada exitosamente"
            return 0
        else
            log_warning "No se pudo copiar la clave SSH"
            return 1
        fi
    fi
}

# Login a dispositivo
login_device() {
    local device_prefix="$1"
    local username="${2:-}"
    local password="${3:-}"

    # Buscar dispositivo
    log_info "Buscando dispositivo con prefijo '${device_prefix}'..."
    local device_info
    device_info=$(find_device_by_prefix "${device_prefix}")
    local find_result=$?

    if [[ ${find_result} -eq 1 ]]; then
        log_error "Dispositivo no encontrado con prefijo '${device_prefix}'"
        return 1
    elif [[ ${find_result} -eq 2 ]]; then
        log_error "Prefijo ambiguo. Use más caracteres para identificar el dispositivo."
        return 1
    fi

    # Extraer información del dispositivo
    IFS='|' read -r device_id port fingerprint reg_date status <<< "${device_info}"

    log_info "Dispositivo encontrado: ${device_id}"
    log_info "Puerto del túnel: ${port}"
    log_info "Estado: ${status}"

    # Verificar si el túnel está activo
    if ! is_tunnel_active "${port}"; then
        log_error "El túnel no está activo. El dispositivo debe estar conectado."
        return 1
    fi

    # Obtener credenciales guardadas
    local saved_creds
    saved_creds=$(get_device_credentials "${device_id}")

    if [[ -n "${saved_creds}" ]]; then
        # Usar credenciales guardadas
        IFS='|' read -r saved_id saved_user has_password <<< "${saved_creds}"

        if [[ -z "${username}" ]]; then
            username="${saved_user}"
            log_info "Usando usuario guardado: ${username}"
        fi

        # Intentar conectar sin contraseña (con clave SSH)
        log_info "Conectando al dispositivo ${device_id:0:8}... en localhost:${port}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost"
        return $?
    else
        # Primera vez - solicitar credenciales si no se proporcionaron
        if [[ -z "${username}" ]]; then
            read -p "Usuario para el dispositivo: " username
        fi

        if [[ -z "${password}" ]]; then
            read -sp "Contraseña para el dispositivo: " password
            echo ""
        fi

        # Validar que tenemos credenciales
        if [[ -z "${username}" ]] || [[ -z "${password}" ]]; then
            log_error "Usuario y contraseña son requeridos"
            return 1
        fi

        # Intentar conexión inicial para validar credenciales
        log_info "Validando credenciales..."
        if command -v sshpass &> /dev/null; then
            # Probar conexión con sshpass
            if sshpass -p "${password}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 -p "${port}" "${username}@localhost" "exit" 2>/dev/null; then
                log_info "Credenciales válidas!"

                # Copiar clave SSH
                log_info "Configurando acceso sin contraseña..."
                if copy_ssh_key_to_device "${port}" "${username}" "${password}"; then
                    save_device_credentials "${device_id}" "${username}" "false"
                    log_info "Acceso sin contraseña configurado exitosamente"
                else
                    save_device_credentials "${device_id}" "${username}" "true"
                    log_warning "No se pudo configurar acceso sin contraseña"
                fi

                # Conectar al dispositivo usando la clave SSH recién copiada
                log_info "Conectando al dispositivo..."
                ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost"
                return $?
            else
                log_error "Fallo la autenticación. Verifique usuario y contraseña."
                return 1
            fi
        else
            # Sin sshpass - modo interactivo
            log_warning "sshpass no está instalado. Modo interactivo activado."
            log_info "Instalarlo mejorará la experiencia: apt-get install sshpass"

            # Intentar copiar clave SSH
            log_info "Configurando acceso sin contraseña (ingrese la contraseña cuando se solicite)..."
            if ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost"; then
                save_device_credentials "${device_id}" "${username}" "false"
                log_info "Acceso sin contraseña configurado exitosamente"
            else
                save_device_credentials "${device_id}" "${username}" "true"
                log_warning "No se pudo configurar acceso sin contraseña"
            fi

            # Conectar
            log_info "Conectando al dispositivo..."
            ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${port}" "${username}@localhost"
            return $?
        fi
    fi
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
  login <prefix> [user] [pass]  Conectar a dispositivo por prefijo de ID
  help                       Mostrar esta ayuda

EJEMPLOS:
  $(basename "$0") list active
  $(basename "$0") stats
  $(basename "$0") check a1b2c3d4...
  $(basename "$0") close a1b2c3d4...
  $(basename "$0") monitor 10
  $(basename "$0") export /tmp/status.json
  $(basename "$0") login a1b2c            # Conectar con prefijo (interactivo)
  $(basename "$0") login a1b2c myuser     # Conectar con usuario
  $(basename "$0") login a1b2c myuser mypass  # Conectar con usuario y contraseña

NOTAS SOBRE LOGIN:
  - El prefijo debe tener al menos 5 caracteres del DEVICE_ID
  - En la primera conexión se copiarán las claves SSH automáticamente
  - Las conexiones posteriores no requerirán contraseña
  - Se recomienda instalar 'sshpass' para mejor experiencia

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
        login)
            if [[ $# -lt 2 ]]; then
                log_error "Falta prefijo del device_id"
                show_help
                exit 1
            fi
            login_device "$2" "${3:-}" "${4:-}"
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
