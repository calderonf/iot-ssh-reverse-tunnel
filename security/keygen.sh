#!/bin/bash
#
# keygen.sh - Generador de Claves SSH para Túneles IoT
# Crea pares de claves SSH seguras para dispositivos y servidor
#

set -euo pipefail

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/iot-ssh-tunnel/keygen.log"
DEFAULT_KEY_TYPE="ed25519"
DEFAULT_KEY_BITS=4096

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
    mkdir -p "$(dirname "${LOG_FILE}")"

    # Verificar que ssh-keygen está disponible
    if ! command -v ssh-keygen &> /dev/null; then
        log_error "ssh-keygen no está instalado"
        exit 1
    fi
}

# Generar clave para dispositivo IoT
generate_device_key() {
    local output_path="${1}"
    local key_type="${2:-${DEFAULT_KEY_TYPE}}"
    local comment="${3:-iot-device-$(date +%Y%m%d)}"

    if [[ -z "${output_path}" ]]; then
        log_error "Debe especificar ruta de salida para la clave"
        return 1
    fi

    # Verificar si la clave ya existe
    if [[ -f "${output_path}" ]]; then
        log_warning "La clave ya existe: ${output_path}"
        read -p "¿Desea sobrescribir? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log_info "Operación cancelada"
            return 1
        fi
    fi

    # Crear directorio si no existe
    mkdir -p "$(dirname "${output_path}")"

    log_info "Generando clave SSH para dispositivo IoT"
    log_info "  Tipo: ${key_type}"
    log_info "  Ruta: ${output_path}"
    log_info "  Comentario: ${comment}"

    # Generar clave según el tipo
    case "${key_type}" in
        ed25519)
            ssh-keygen -t ed25519 -f "${output_path}" -C "${comment}" -N "" -q
            ;;
        rsa)
            ssh-keygen -t rsa -b ${DEFAULT_KEY_BITS} -f "${output_path}" -C "${comment}" -N "" -q
            ;;
        ecdsa)
            ssh-keygen -t ecdsa -b 521 -f "${output_path}" -C "${comment}" -N "" -q
            ;;
        *)
            log_error "Tipo de clave no soportado: ${key_type}"
            return 1
            ;;
    esac

    # Establecer permisos seguros
    chmod 600 "${output_path}"
    chmod 644 "${output_path}.pub"

    # Mostrar fingerprint
    local fingerprint
    fingerprint=$(ssh-keygen -lf "${output_path}.pub" | awk '{print $2}')

    log_success "Clave generada exitosamente"
    log_info "  Clave privada: ${output_path}"
    log_info "  Clave pública: ${output_path}.pub"
    log_info "  Fingerprint: ${fingerprint}"

    # Mostrar clave pública
    echo ""
    echo "Clave pública:"
    echo "=============="
    cat "${output_path}.pub"
    echo ""

    return 0
}

# Generar múltiples claves para deployment
batch_generate() {
    local output_dir="$1"
    local count="${2:-1}"
    local key_type="${3:-${DEFAULT_KEY_TYPE}}"
    local prefix="${4:-device}"

    if [[ -z "${output_dir}" ]]; then
        log_error "Debe especificar directorio de salida"
        return 1
    fi

    mkdir -p "${output_dir}"

    log_info "Generación batch de ${count} claves"
    log_info "  Directorio: ${output_dir}"
    log_info "  Tipo: ${key_type}"

    local manifest_file="${output_dir}/keys_manifest.txt"
    echo "# Manifest de Claves SSH - Generado: $(date '+%Y-%m-%d %H:%M:%S')" > "${manifest_file}"
    echo "# Formato: KEY_NAME|FINGERPRINT|GENERATION_DATE" >> "${manifest_file}"

    for i in $(seq 1 "${count}"); do
        local key_name="${prefix}_$(printf '%04d' ${i})"
        local key_path="${output_dir}/${key_name}"
        local comment="${key_name}-$(date +%Y%m%d)"

        log_info "Generando clave ${i}/${count}: ${key_name}"

        # Generar clave sin prompt
        case "${key_type}" in
            ed25519)
                ssh-keygen -t ed25519 -f "${key_path}" -C "${comment}" -N "" -q
                ;;
            rsa)
                ssh-keygen -t rsa -b ${DEFAULT_KEY_BITS} -f "${key_path}" -C "${comment}" -N "" -q
                ;;
            ecdsa)
                ssh-keygen -t ecdsa -b 521 -f "${key_path}" -C "${comment}" -N "" -q
                ;;
        esac

        chmod 600 "${key_path}"
        chmod 644 "${key_path}.pub"

        # Agregar al manifest
        local fingerprint
        fingerprint=$(ssh-keygen -lf "${key_path}.pub" | awk '{print $2}')
        echo "${key_name}|${fingerprint}|$(date '+%Y-%m-%d %H:%M:%S')" >> "${manifest_file}"
    done

    log_success "Generación batch completada"
    log_info "  Claves generadas: ${count}"
    log_info "  Manifest: ${manifest_file}"

    return 0
}

# Verificar integridad de clave
verify_key() {
    local key_path="$1"

    if [[ ! -f "${key_path}" ]]; then
        log_error "Clave no encontrada: ${key_path}"
        return 1
    fi

    log_info "Verificando clave SSH: ${key_path}"

    # Verificar formato de clave privada
    if ssh-keygen -l -f "${key_path}" &> /dev/null; then
        log_success "Clave privada válida"
    else
        log_error "Clave privada inválida o corrupta"
        return 1
    fi

    # Verificar clave pública si existe
    if [[ -f "${key_path}.pub" ]]; then
        if ssh-keygen -l -f "${key_path}.pub" &> /dev/null; then
            log_success "Clave pública válida"

            # Mostrar información
            local fingerprint key_type bits
            read -r bits key_type fingerprint _ <<< $(ssh-keygen -lf "${key_path}.pub")

            echo ""
            echo "Información de la clave:"
            echo "  Tipo: ${key_type}"
            echo "  Bits: ${bits}"
            echo "  Fingerprint: ${fingerprint}"
            echo ""
        else
            log_error "Clave pública inválida o corrupta"
            return 1
        fi
    else
        log_warning "Clave pública no encontrada: ${key_path}.pub"
    fi

    # Verificar permisos
    local perms
    perms=$(stat -c %a "${key_path}" 2>/dev/null || stat -f %A "${key_path}")

    if [[ "${perms}" == "600" ]] || [[ "${perms}" == "0600" ]]; then
        log_success "Permisos correctos: ${perms}"
    else
        log_warning "Permisos inseguros: ${perms} (recomendado: 600)"
        log_info "Corrigiendo permisos..."
        chmod 600 "${key_path}"
    fi

    return 0
}

# Convertir clave pública a formato authorized_keys con restricciones
format_authorized_key() {
    local public_key_file="$1"
    local tunnel_port="${2:-10000}"
    local restrictions="${3:-default}"

    if [[ ! -f "${public_key_file}" ]]; then
        log_error "Clave pública no encontrada: ${public_key_file}"
        return 1
    fi

    local public_key
    public_key=$(cat "${public_key_file}")

    # Construir restricciones
    local restriction_string=""

    case "${restrictions}" in
        default)
            restriction_string="command=\"echo 'Tunnel only'\",no-agent-forwarding,no-X11-forwarding,permitopen=\"localhost:${tunnel_port}\""
            ;;
        strict)
            restriction_string="command=\"echo 'Tunnel only'\",no-agent-forwarding,no-X11-forwarding,no-pty,no-user-rc,permitopen=\"localhost:${tunnel_port}\""
            ;;
        minimal)
            restriction_string="permitopen=\"localhost:${tunnel_port}\""
            ;;
        none)
            restriction_string=""
            ;;
        *)
            log_error "Nivel de restricciones desconocido: ${restrictions}"
            return 1
            ;;
    esac

    # Generar línea authorized_keys
    if [[ -n "${restriction_string}" ]]; then
        echo "${restriction_string} ${public_key}"
    else
        echo "${public_key}"
    fi

    return 0
}

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: $(basename "$0") [COMANDO] [OPCIONES]

Generador de Claves SSH para Sistema de Túneles IoT

COMANDOS:
  generate <output_path> [type] [comment]        Generar clave para dispositivo
  batch <output_dir> <count> [type] [prefix]     Generar múltiples claves
  verify <key_path>                              Verificar integridad de clave
  format <public_key> [port] [restrictions]      Formatear para authorized_keys
  help                                           Mostrar esta ayuda

TIPOS DE CLAVE:
  ed25519    EdDSA usando curva Curve25519 (recomendado, más seguro y rápido)
  rsa        RSA 4096 bits (compatible con sistemas legacy)
  ecdsa      ECDSA 521 bits (alternativa moderna)

NIVELES DE RESTRICCIÓN:
  default    Restricciones estándar (recomendado)
  strict     Restricciones máximas
  minimal    Restricciones mínimas
  none       Sin restricciones (no recomendado)

EJEMPLOS:
  # Generar clave ed25519 para dispositivo
  $(basename "$0") generate /etc/iot-ssh-tunnel/tunnel_key

  # Generar clave RSA para compatibilidad
  $(basename "$0") generate /path/to/key rsa "mi-dispositivo-001"

  # Generar 10 claves para deployment
  $(basename "$0") batch /tmp/iot-keys 10 ed25519 device

  # Verificar integridad de clave
  $(basename "$0") verify /etc/iot-ssh-tunnel/tunnel_key

  # Formatear clave pública para authorized_keys
  $(basename "$0") format /etc/iot-ssh-tunnel/tunnel_key.pub 10001 strict

MEJORES PRÁCTICAS:
  1. Use ed25519 para nuevos deployments (más seguro y eficiente)
  2. Use RSA 4096 solo si necesita compatibilidad con sistemas antiguos
  3. Nunca comparta claves privadas entre dispositivos
  4. Almacene claves privadas con permisos 600
  5. Use restricciones 'strict' en entornos de producción
  6. Rote claves periódicamente (ver key_rotation.sh)

SEGURIDAD:
  - Las claves se generan sin passphrase para automatización
  - Los permisos se establecen automáticamente (600 para privadas, 644 para públicas)
  - Se recomienda usar ed25519 por su resistencia a ataques
  - Las claves nunca se transmiten por red sin cifrado

EOF
}

# Main
main() {
    initialize

    local command="${1:-help}"

    case "${command}" in
        generate)
            if [[ $# -lt 2 ]]; then
                log_error "Falta especificar ruta de salida"
                show_help
                exit 1
            fi
            generate_device_key "$2" "${3:-${DEFAULT_KEY_TYPE}}" "${4:-}"
            ;;
        batch)
            if [[ $# -lt 3 ]]; then
                log_error "Faltan argumentos para generación batch"
                show_help
                exit 1
            fi
            batch_generate "$2" "$3" "${4:-${DEFAULT_KEY_TYPE}}" "${5:-device}"
            ;;
        verify)
            if [[ $# -lt 2 ]]; then
                log_error "Falta especificar ruta de clave"
                show_help
                exit 1
            fi
            verify_key "$2"
            ;;
        format)
            if [[ $# -lt 2 ]]; then
                log_error "Falta especificar clave pública"
                show_help
                exit 1
            fi
            format_authorized_key "$2" "${3:-10000}" "${4:-default}"
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
