# Guía de Despliegue - Túneles SSH Inversos para IoT

## Tabla de Contenidos

1. [Requisitos Previos](#requisitos-previos)
2. [Configuración del Servidor](#configuración-del-servidor)
3. [Configuración de Dispositivos IoT](#configuración-de-dispositivos-iot)
4. [Verificación y Testing](#verificación-y-testing)
5. [Troubleshooting](#troubleshooting)

## Requisitos Previos

### Servidor Central

**Hardware:**
- CPU: 1 vCPUs mínimo
- RAM: 1GB mínimo
- Disco: 30GB mínimo
- Red: IP pública estática se hacen pruebas con máquina Standard_B1s de azure

**Software:**
- Sistema operativo: Debian 11+ o Ubuntu 20.04+
- OpenSSH Server 8.0+
- Acceso root o sudo

**Red:**
- Puerto SSH (22) accesible desde Internet
- Firewall configurado para permitir conexiones SSH entrantes

### Dispositivos IoT

**Hardware:**
- CPU: Compatible con arquitectura ARM/x86/x64
- RAM: 256MB mínimo
- Disco: 500MB disponible
- Red: Conectividad IP (WiFi, Ethernet, Celular)

**Software:**
- Sistema operativo: Linux (Debian, Ubuntu, Yocto, etc.)
- OpenSSH Client 7.0+
- Autossh (recomendado)
- Systemd (para servicio automático)

## Configuración del Servidor

### Paso 1: Preparación del Sistema

```bash
# Actualizar sistema
sudo apt-get update
sudo apt-get upgrade -y

# Instalar dependencias
sudo apt-get install -y openssh-server git netstat-nat net-tools
```

### Paso 2: Crear Usuario Dedicado

```bash
# Crear usuario para túneles IoT
sudo useradd -r -m -d /home/iot-tunnel -s /bin/bash iot-tunnel

# Crear estructura de directorios
sudo mkdir -p /home/iot-tunnel/.ssh
sudo mkdir -p /var/log/iot-ssh-tunnel
sudo mkdir -p /var/lib/iot-ssh-tunnel/metrics
sudo mkdir -p /var/run/iot-ssh-tunnel

# Establecer permisos
sudo chown -R iot-tunnel:iot-tunnel /home/iot-tunnel
sudo chmod 700 /home/iot-tunnel/.ssh
sudo chown iot-tunnel:iot-tunnel /var/log/iot-ssh-tunnel
sudo chown iot-tunnel:iot-tunnel /var/lib/iot-ssh-tunnel
sudo chown iot-tunnel:iot-tunnel /var/run/iot-ssh-tunnel
```

### Paso 3: Clonar Repositorio

```bash
# Clonar el repositorio
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# Establecer permisos de ejecución
sudo chmod +x server/scripts/*.sh
sudo chmod +x security/*.sh
```

### Paso 4: Configurar SSH

```bash
# Copiar configuración endurecida
sudo cp server/configs/sshd_config.d/iot-tunnel.conf /etc/ssh/sshd_config.d/

# Ajusta la lista `PermitListen` dentro del archivo para reflejar los puertos autorizados. por defecto solo hay 3, 
#PermitListen 10000
#PermitListen 10001
#PermitListen 10002

# (Opcional) Instalar script de contención
sudo cp server/scripts/tunnel-only.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/tunnel-only.sh

# Verificar sintaxis de la configuración SSH
# Este comando comprueba que no haya errores en los archivos de configuración antes de aplicarlos
sudo sshd -t

# Recargar servicio tras cambios de configuración
# Debian / Ubuntu
sudo systemctl reload ssh

# RHEL / CentOS / Amazon Linux
sudo systemctl reload sshd

# NOTA: Si el servicio SSH no está activo y obtienes el error "ssh.service is not active, cannot reload"
# ejecuta los siguientes comandos para iniciar el servicio:
#   sudo systemctl start ssh          # Inicia el servicio SSH
#   sudo systemctl enable ssh         # Habilita el servicio para que inicie automáticamente en el arranque
#   sudo systemctl status ssh         # Verifica que el servicio esté corriendo correctamente
# Una vez que el servicio esté activo, podrás usar 'reload' para aplicar cambios de configuración sin interrumpir conexiones existentes

# Verificar que está escuchando
sudo ss -tlnp | grep :22
```
del ùltimo comando deberìa salir algo como:
```bash
usuario@EquipoServidor:/etc/ssh/sshd_config.d$ sudo ss -tlnp | grep :22
LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=11870,fd=3),("systemd",pid=1,fd=64))
LISTEN 0      4096            [::]:22           [::]:*    users:(("sshd",pid=11870,fd=4),("systemd",pid=1,fd=65))
```

### Paso 5: Inicializar Sistema de Registro

```bash
# Crear archivo de mapeo
sudo mkdir -p /opt/iot-ssh-reverse-tunnel/server/configs
sudo touch /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping
sudo chown iot-tunnel:iot-tunnel /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping

# Inicializar con header
echo "# Device Mapping File - Format: DEVICE_ID|PORT|PUBLIC_KEY_FINGERPRINT|REGISTERED_DATE|STATUS" | \
    sudo tee /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping
```

### Paso 6: Configurar Firewall

**UFW (Ubuntu/Debian):**

```bash
# Permitir SSH
sudo ufw allow 22/tcp

# Habilitar firewall
sudo ufw enable

# Verificar estado
sudo ufw status
```

**iptables:**

```bash
# Permitir SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Guardar reglas
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### Paso 7: Configurar Monitoreo (Opcional)

```bash
# Crear servicio systemd para monitor
sudo tee /etc/systemd/system/iot-tunnel-monitor.service << 'EOF'
[Unit]
Description=IoT SSH Tunnel Connection Monitor
After=network-online.target sshd.service

[Service]
Type=simple
User=iot-tunnel
ExecStart=/opt/iot-ssh-reverse-tunnel/server/scripts/connection_monitor.sh daemon 60
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar servicio
sudo systemctl daemon-reload
sudo systemctl enable iot-tunnel-monitor
sudo systemctl start iot-tunnel-monitor

# Verificar estado
sudo systemctl status iot-tunnel-monitor
```
Si esta trabajando en una màquina virtual en la nube, por favor abra los puertos correspondientes

## Configuración de Dispositivos IoT

### Paso 1: Preparación del Dispositivo

```bash
# Actualizar sistema
sudo apt-get update
sudo apt-get upgrade -y

# Instalar dependencias
sudo apt-get install -y openssh-client autossh git
```

### Paso 2: Clonar Repositorio

```bash
# Clonar el repositorio
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# Establecer permisos
sudo chmod +x client/scripts/*.sh
sudo chmod +x security/*.sh
```

### Paso 3: Generar Device ID

```bash
# Generar identificador único
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/device_identifier.sh get

# El output será algo como:
# a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

# Guardar este ID para el registro
DEVICE_ID=$(sudo /opt/iot-ssh-reverse-tunnel/client/scripts/device_identifier.sh get)
echo "Device ID: ${DEVICE_ID}"
```

### Paso 4: Generar Claves SSH

```bash
# Crear directorio de configuración
sudo mkdir -p /etc/iot-ssh-tunnel

# Generar par de claves ed25519
sudo /opt/iot-ssh-reverse-tunnel/security/keygen.sh generate \
    /etc/iot-ssh-tunnel/tunnel_key \
    ed25519 \
    "iot-device-${DEVICE_ID}"

# Mostrar clave pública (para registro en servidor)
sudo cat /etc/iot-ssh-tunnel/tunnel_key.pub
```

### Paso 5: Registrar Dispositivo en Servidor

**En el servidor**, ejecutar:


```bash
DEVICE_ID=18e46... #el ID que generò en el dispositivo IOT
# Copiar la clave pública del dispositivo a un archivo temporal
# (Usar el output del paso anterior)
cat > /tmp/device_${DEVICE_ID}.pub << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-a1b2c3d4...
EOF

# Registrar dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/device_registry.sh register \
    ${DEVICE_ID} \
    /tmp/device_${DEVICE_ID}.pub

# El output mostrará el puerto asignado
# Ejemplo: Puerto asignado: 10001
```

### Paso 6: Configurar Túnel en Dispositivo

**En el dispositivo**, usando el puerto asignado:

```bash
# Configurar túnel (usar el puerto asignado por el servidor)
ASSIGNED_PORT=10001  # Reemplazar con el puerto real
SERVER_HOST="tunnel.example.com"  # Reemplazar con el host real

sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh setup \
    ${SERVER_HOST} \
    22 \
    iot-tunnel \
    ${ASSIGNED_PORT}

# Probar conectividad
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh test
```

### Paso 7: Instalar Servicio Systemd

```bash
# Copiar archivos de servicio
sudo cp /opt/iot-ssh-reverse-tunnel/client/systemd/iot-ssh-tunnel.service \
    /etc/systemd/system/

sudo cp /opt/iot-ssh-reverse-tunnel/client/systemd/iot-tunnel-start.sh \
    /usr/local/bin/

sudo cp /opt/iot-ssh-reverse-tunnel/client/systemd/iot-tunnel-stop.sh \
    /usr/local/bin/

# Establecer permisos
sudo chmod +x /usr/local/bin/iot-tunnel-start.sh
sudo chmod +x /usr/local/bin/iot-tunnel-stop.sh

# Habilitar e iniciar servicio
sudo systemctl daemon-reload
sudo systemctl enable iot-ssh-tunnel
sudo systemctl start iot-ssh-tunnel

# Verificar estado
sudo systemctl status iot-ssh-tunnel
```

### Paso 8: Verificar Túnel Activo

**En el dispositivo:**

```bash
# Ver estado del túnel
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh status
```

**En el servidor:**

```bash
# Listar túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Verificar túnel específico
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh check ${DEVICE_ID}
```

## Verificación y Testing

### Test 1: Conectividad Básica

**Desde el servidor:**

```bash
# Conectar al dispositivo a través del túnel
ssh -p ${ASSIGNED_PORT} localhost

# Deberías ver el prompt del dispositivo IoT
```

### Test 2: Reconexión Automática

**En el dispositivo:**

```bash
# Detener túnel manualmente
sudo systemctl stop iot-ssh-tunnel

# Esperar 30 segundos

# Verificar que se reconectó automáticamente
sudo systemctl status iot-ssh-tunnel
```

### Test 3: Persistencia tras Reinicio

**En el dispositivo:**

```bash
# Reiniciar dispositivo
sudo reboot

# Después del reinicio, verificar que el túnel se estableció
sudo systemctl status iot-ssh-tunnel
```

**En el servidor:**

```bash
# Verificar que el túnel está activo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active
```

### Test 4: Monitoreo

**En el servidor:**

```bash
# Ver estadísticas
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh stats

# Generar reporte
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/connection_monitor.sh report 7
```

## Deployment Masivo

Para desplegar en múltiples dispositivos:

### 1. Preparar Scripts de Automatización

```bash
# crear script de deployment
cat > /opt/deploy_iot_tunnel.sh << 'EOF'
#!/bin/bash
set -e

SERVER_HOST="tunnel.example.com"
SERVER_PORT="22"
SERVER_USER="iot-tunnel"

# Instalar dependencias
apt-get update
apt-get install -y openssh-client autossh git

# Clonar repositorio
cd /opt
git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel
chmod +x client/scripts/*.sh security/*.sh

# Generar device ID
DEVICE_ID=$(./client/scripts/device_identifier.sh get)

# Generar claves
mkdir -p /etc/iot-ssh-tunnel
./security/keygen.sh generate /etc/iot-ssh-tunnel/tunnel_key ed25519

# Enviar clave pública al servidor para registro
# (Esto requiere un mecanismo seguro de registro automático)

# Configurar servicio
cp client/systemd/iot-ssh-tunnel.service /etc/systemd/system/
cp client/systemd/iot-tunnel-*.sh /usr/local/bin/
chmod +x /usr/local/bin/iot-tunnel-*.sh

systemctl daemon-reload
systemctl enable iot-ssh-tunnel

echo "Device ID: ${DEVICE_ID}"
echo "Registre este dispositivo en el servidor antes de iniciar el servicio"
EOF

chmod +x /opt/deploy_iot_tunnel.sh
```

### 2. Ejecutar en Dispositivos

```bash
# Ejecutar script de deployment
sudo /opt/deploy_iot_tunnel.sh
```

## Mantenimiento

### Rotación de Claves

```bash
# En el servidor, generar reporte de claves antiguas
sudo /opt/iot-ssh-reverse-tunnel/security/key_rotation.sh report \
    /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping \
    90

# Rotar clave de un dispositivo
sudo /opt/iot-ssh-reverse-tunnel/security/key_rotation.sh rotate \
    ${DEVICE_ID} \
    /path/to/current/key
```

### Backup

```bash
# Backup de configuración del servidor
sudo tar -czf /backup/iot-tunnel-server-$(date +%Y%m%d).tar.gz \
    /opt/iot-ssh-reverse-tunnel/server/configs \
    /home/iot-tunnel/.ssh/authorized_keys \
    /var/lib/iot-ssh-tunnel

# Backup de logs
sudo tar -czf /backup/iot-tunnel-logs-$(date +%Y%m%d).tar.gz \
    /var/log/iot-ssh-tunnel
```

### Actualización

```bash
# En servidor y dispositivos
cd /opt/iot-ssh-reverse-tunnel
sudo git pull

# Reiniciar servicios si es necesario
sudo systemctl restart iot-ssh-tunnel  # En dispositivos
sudo systemctl restart iot-tunnel-monitor  # En servidor
```

## Checklist de Deployment

### Servidor

- [ ] Sistema actualizado
- [ ] OpenSSH Server instalado y configurado
- [ ] Usuario iot-tunnel creado
- [ ] Repositorio clonado
- [ ] Configuración SSH aplicada
- [ ] Firewall configurado
- [ ] Sistema de registro inicializado
- [ ] Monitor configurado (opcional)

### Dispositivo IoT

- [ ] Sistema actualizado
- [ ] OpenSSH Client y autossh instalados
- [ ] Repositorio clonado
- [ ] Device ID generado
- [ ] Par de claves SSH generado
- [ ] Dispositivo registrado en servidor
- [ ] Túnel configurado con puerto asignado
- [ ] Servicio systemd instalado y habilitado
- [ ] Conectividad verificada

## Próximos Pasos

Una vez completado el deployment:

1. Monitorear logs durante las primeras 24 horas
2. Verificar que los túneles permanecen estables
3. Documentar cualquier configuración específica
4. Programar rotación de claves
5. Configurar backups automáticos
6. Establecer alertas de monitoreo
