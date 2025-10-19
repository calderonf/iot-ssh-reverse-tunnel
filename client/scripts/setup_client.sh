#!/bin/bash
#
# setup_client.sh - Configuración Automática del Cliente IoT
# Configura el túnel SSH inverso de forma interactiva
#

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Directorios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_DIR="/etc/iot-ssh-tunnel"
LOG_DIR="/var/log/iot-ssh-tunnel"
RUN_DIR="/run/iot-ssh-tunnel"

# Banner
show_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Configuración Automática del Cliente IoT SSH Tunnel    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Funciones de logging
log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${BLUE}${BOLD}▶${NC} $1"
}

log_wait() {
    echo -e "${CYAN}[⏳]${NC} $1"
}

# Verificar que se ejecuta como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        echo "Ejecute: sudo $0"
        exit 1
    fi
}

# Verificar dependencias
check_dependencies() {
    log_step "Verificando dependencias..."

    local missing_deps=()

    for cmd in ssh ssh-keygen autossh systemctl; do
        if ! command -v "${cmd}" &> /dev/null; then
            missing_deps+=("${cmd}")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Faltan dependencias: ${missing_deps[*]}"
        echo ""
        echo "Instale las dependencias con:"
        echo "  apt-get update"
        echo "  apt-get install -y openssh-client autossh systemd"
        exit 1
    fi

    log_info "Todas las dependencias están instaladas"
}

# Recopilar información del usuario
gather_information() {
    log_step "Recopilando información de configuración..."
    echo ""

    # IP del servidor
    read -p "$(echo -e ${CYAN}Ingrese la IP o hostname del servidor SSH: ${NC})" SERVER_HOST
    if [[ -z "${SERVER_HOST}" ]]; then
        log_error "La IP del servidor es requerida"
        exit 1
    fi

    # Puerto SSH del servidor
    read -p "$(echo -e ${CYAN}Puerto SSH del servidor [22]: ${NC})" SERVER_PORT
    SERVER_PORT="${SERVER_PORT:-22}"

    # Usuario SSH del servidor
    read -p "$(echo -e ${CYAN}Usuario SSH del servidor [iot-tunnel]: ${NC})" SERVER_USER
    SERVER_USER="${SERVER_USER:-iot-tunnel}"

    # Cadena para generar Device ID
    echo ""
    log_info "El Device ID se generará a partir de información única del dispositivo"
    read -p "$(echo -e ${CYAN}Cadena adicional para el Device ID [opcional]: ${NC})" DEVICE_SEED

    echo ""
    log_info "Configuración recopilada:"
    echo "  Servidor: ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"
    echo "  Seed Device ID: ${DEVICE_SEED:-<automático>}"
    echo ""

    read -p "$(echo -e ${YELLOW}¿Continuar con esta configuración? [S/n]: ${NC})" CONFIRM
    CONFIRM="${CONFIRM:-S}"

    if [[ ! "${CONFIRM}" =~ ^[SsYy]$ ]]; then
        log_warn "Configuración cancelada por el usuario"
        exit 0
    fi
}

# Generar Device ID
generate_device_id() {
    log_step "Generando Device ID único..."

    # Usar el script existente
    if [[ -x "${SCRIPT_DIR}/device_identifier.sh" ]]; then
        DEVICE_ID=$("${SCRIPT_DIR}/device_identifier.sh" get "${DEVICE_SEED}")
    else
        log_error "No se encontró device_identifier.sh"
        exit 1
    fi

    log_info "Device ID generado: ${DEVICE_ID}"
}

# Generar claves SSH
generate_ssh_keys() {
    log_step "Generando claves SSH..."

    # Crear directorio de configuración
    mkdir -p "${CONFIG_DIR}"
    chmod 755 "${CONFIG_DIR}"

    local key_file="${CONFIG_DIR}/tunnel_key"

    if [[ -f "${key_file}" ]]; then
        log_warn "Ya existe una clave SSH en ${key_file}"
        read -p "$(echo -e ${YELLOW}¿Desea regenerar la clave? [s/N]: ${NC})" REGEN
        REGEN="${REGEN:-N}"

        if [[ ! "${REGEN}" =~ ^[SsYy]$ ]]; then
            log_info "Usando clave existente"
            PUBLIC_KEY=$(cat "${key_file}.pub")
            KEY_FINGERPRINT=$(ssh-keygen -lf "${key_file}.pub" | awk '{print $2}')
            return 0
        fi

        # Backup de claves antiguas
        mv "${key_file}" "${key_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        mv "${key_file}.pub" "${key_file}.pub.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    # Generar nueva clave
    if [[ -x "${PROJECT_ROOT}/security/keygen.sh" ]]; then
        "${PROJECT_ROOT}/security/keygen.sh" generate "${key_file}" ed25519 "iot-device-${DEVICE_ID}"
    else
        ssh-keygen -t ed25519 -f "${key_file}" -N "" -C "iot-device-${DEVICE_ID}"
    fi

    chmod 600 "${key_file}"
    chmod 644 "${key_file}.pub"

    PUBLIC_KEY=$(cat "${key_file}.pub")
    KEY_FINGERPRINT=$(ssh-keygen -lf "${key_file}.pub" | awk '{print $2}')

    log_info "Clave SSH generada exitosamente"
    log_info "Fingerprint: ${KEY_FINGERPRINT}"
}

# Mostrar información de registro
show_registration_info() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}║  INFORMACIÓN PARA REGISTRAR EL DISPOSITIVO EN EL SERVIDOR             ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}1. Device ID:${NC}"
    echo -e "   ${GREEN}${DEVICE_ID}${NC}"
    echo ""
    echo -e "${BOLD}2. Clave Pública SSH:${NC}"
    echo -e "   ${GREEN}${PUBLIC_KEY}${NC}"
    echo ""
    echo -e "${BOLD}3. Fingerprint:${NC}"
    echo -e "   ${GREEN}${KEY_FINGERPRINT}${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}INSTRUCCIONES PARA EL SERVIDOR:${NC}"
    echo ""
    echo "En el servidor, ejecute los siguientes comandos:"
    echo ""
    echo -e "${GREEN}# 1. Crear archivo temporal con la clave pública${NC}"
    echo "cat > /tmp/device_${DEVICE_ID}.pub << 'EOFKEY'"
    echo "${PUBLIC_KEY}"
    echo "EOFKEY"
    echo ""
    echo -e "${GREEN}# 2. Registrar el dispositivo${NC}"
    echo "sudo /opt/iot-ssh-reverse-tunnel/server/scripts/device_registry.sh register \\"
    echo "    ${DEVICE_ID} \\"
    echo "    /tmp/device_${DEVICE_ID}.pub"
    echo ""
    echo -e "${GREEN}# 3. Anotar el puerto asignado que muestre el comando${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Esperar confirmación de registro
wait_for_registration() {
    log_wait "Esperando que registre el dispositivo en el servidor..."
    echo ""
    read -p "$(echo -e ${YELLOW}Presione ENTER cuando haya registrado el dispositivo en el servidor...${NC})"
    echo ""

    # Solicitar puerto asignado
    while true; do
        read -p "$(echo -e ${CYAN}Ingrese el puerto asignado por el servidor: ${NC})" ASSIGNED_PORT

        if [[ "${ASSIGNED_PORT}" =~ ^[0-9]+$ ]] && [[ ${ASSIGNED_PORT} -ge 10000 ]] && [[ ${ASSIGNED_PORT} -le 20000 ]]; then
            break
        else
            log_error "Puerto inválido. Debe ser un número entre 10000 y 20000"
        fi
    done

    log_info "Puerto asignado: ${ASSIGNED_PORT}"
}

# Configurar túnel
configure_tunnel() {
    log_step "Configurando túnel SSH..."

    if [[ -x "${SCRIPT_DIR}/ssh_tunnel_setup.sh" ]]; then
        "${SCRIPT_DIR}/ssh_tunnel_setup.sh" setup \
            "${SERVER_HOST}" \
            "${SERVER_PORT}" \
            "${SERVER_USER}" \
            "${ASSIGNED_PORT}"

        log_info "Túnel configurado exitosamente"
    else
        log_error "No se encontró ssh_tunnel_setup.sh"
        exit 1
    fi
}

# Instalar servicio systemd
install_systemd_service() {
    log_step "Instalando servicio systemd..."

    # Crear directorios necesarios
    mkdir -p "${LOG_DIR}"
    mkdir -p "${RUN_DIR}"
    chmod 755 "${LOG_DIR}"
    chmod 755 "${RUN_DIR}"

    # Crear archivo known_hosts
    touch "${CONFIG_DIR}/known_hosts"
    chmod 644 "${CONFIG_DIR}/known_hosts"

    # Copiar archivos systemd
    local systemd_dir="${PROJECT_ROOT}/client/systemd"

    if [[ -f "${systemd_dir}/iot-ssh-tunnel.service" ]]; then
        cp "${systemd_dir}/iot-ssh-tunnel.service" /etc/systemd/system/
        log_info "Servicio systemd instalado"
    else
        log_error "No se encontró iot-ssh-tunnel.service"
        exit 1
    fi

    if [[ -f "${systemd_dir}/iot-tunnel-start.sh" ]]; then
        cp "${systemd_dir}/iot-tunnel-start.sh" /usr/local/bin/
        chmod +x /usr/local/bin/iot-tunnel-start.sh
        log_info "Script de inicio instalado"
    fi

    if [[ -f "${systemd_dir}/iot-tunnel-stop.sh" ]]; then
        cp "${systemd_dir}/iot-tunnel-stop.sh" /usr/local/bin/
        chmod +x /usr/local/bin/iot-tunnel-stop.sh
        log_info "Script de parada instalado"
    fi

    # Copiar configuración tmpfiles.d
    if [[ -f "${systemd_dir}/iot-ssh-tunnel.conf" ]]; then
        cp "${systemd_dir}/iot-ssh-tunnel.conf" /etc/tmpfiles.d/
        systemd-tmpfiles --create /etc/tmpfiles.d/iot-ssh-tunnel.conf
        log_info "Configuración tmpfiles.d instalada"
    fi

    # Recargar systemd
    systemctl daemon-reload
    log_info "Systemd recargado"
}

# Habilitar e iniciar servicio
start_service() {
    log_step "Habilitando e iniciando servicio..."

    systemctl enable iot-ssh-tunnel
    log_info "Servicio habilitado para inicio automático"

    systemctl start iot-ssh-tunnel
    log_info "Servicio iniciado"

    sleep 3

    # Verificar estado
    if systemctl is-active --quiet iot-ssh-tunnel; then
        log_info "Servicio está corriendo correctamente"
    else
        log_warn "El servicio no está activo. Verificando logs..."
        journalctl -u iot-ssh-tunnel -n 20 --no-pager
    fi
}

# Mostrar instrucciones de verificación
show_verification_instructions() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}║  ✓ CONFIGURACIÓN COMPLETADA EXITOSAMENTE                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Resumen de la configuración:${NC}"
    echo "  Device ID:      ${DEVICE_ID}"
    echo "  Servidor:       ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}"
    echo "  Puerto túnel:   ${ASSIGNED_PORT}"
    echo "  Servicio:       iot-ssh-tunnel"
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}VERIFICACIÓN EN EL CLIENTE (este dispositivo):${NC}"
    echo ""
    echo -e "${GREEN}# Ver estado del servicio${NC}"
    echo "sudo systemctl status iot-ssh-tunnel"
    echo ""
    echo -e "${GREEN}# Ver logs en tiempo real${NC}"
    echo "sudo journalctl -u iot-ssh-tunnel -f"
    echo ""
    echo -e "${GREEN}# Verificar estado del túnel${NC}"
    echo "sudo ${SCRIPT_DIR}/ssh_tunnel_setup.sh status"
    echo ""
    echo -e "${GREEN}# Probar conectividad${NC}"
    echo "sudo ${SCRIPT_DIR}/ssh_tunnel_setup.sh test"
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}VERIFICACIÓN EN EL SERVIDOR:${NC}"
    echo ""
    echo -e "${GREEN}# Listar túneles activos${NC}"
    echo "sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active"
    echo ""
    echo -e "${GREEN}# Verificar túnel específico${NC}"
    echo "sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh check ${DEVICE_ID}"
    echo ""
    echo -e "${GREEN}# Conectarse al dispositivo${NC}"
    echo "sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login ${DEVICE_ID:0:8}"
    echo ""
    echo -e "${GREEN}# O conectarse directamente por puerto${NC}"
    echo "ssh -p ${ASSIGNED_PORT} <usuario>@localhost"
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}¡Configuración completada! El túnel SSH inverso está activo.${NC}"
    echo ""
}

# Guardar configuración en archivo
save_configuration() {
    local config_file="${CONFIG_DIR}/setup_info.txt"

    cat > "${config_file}" << EOF
# Configuración del Cliente IoT SSH Tunnel
# Generado: $(date)

DEVICE_ID=${DEVICE_ID}
SERVER_HOST=${SERVER_HOST}
SERVER_PORT=${SERVER_PORT}
SERVER_USER=${SERVER_USER}
ASSIGNED_PORT=${ASSIGNED_PORT}
KEY_FINGERPRINT=${KEY_FINGERPRINT}
EOF

    chmod 600 "${config_file}"
    log_info "Configuración guardada en ${config_file}"
}

# Main
main() {
    show_banner

    check_root
    check_dependencies
    gather_information

    echo ""
    log_step "Iniciando configuración automática..."
    echo ""

    generate_device_id
    generate_ssh_keys

    show_registration_info
    wait_for_registration

    configure_tunnel
    install_systemd_service
    save_configuration
    start_service

    show_verification_instructions
}

main "$@"
