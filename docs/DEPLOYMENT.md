# Guía de Despliegue Detallada - Túneles SSH Inversos para IoT

> **💡 ¿Buscas una guía rápida?** Consulta [FAST_DEPLOYMENT.md](FAST_DEPLOYMENT.md) para configuración en menos de 15 minutos.

Esta guía proporciona información detallada sobre la instalación, configuración y operación del sistema de túneles SSH inversos. Incluye opciones avanzadas, troubleshooting extenso y mejores prácticas.

## Tabla de Contenidos

1. [Requisitos Previos](#requisitos-previos)
2. [Configuración del Servidor](#configuración-del-servidor)
3. [Configuración de Dispositivos IoT](#configuración-de-dispositivos-iot)
   - [Método 1: Configuración Automática (Recomendada)](#método-1-configuración-automática-recomendada)
   - [Método 2: Configuración Manual (Avanzada)](#método-2-configuración-manual-avanzada)
4. [Acceso a Dispositivos](#acceso-a-dispositivos)
5. [Verificación y Testing](#verificación-y-testing)
6. [Troubleshooting](#troubleshooting)

## Requisitos Previos

### Servidor Central

**Hardware:**
Se hacen pruebas con máquina Standard_B1s de azure
- CPU: 1 vCPUs mínimo
- RAM: 1GB mínimo
- Disco: 30GB mínimo
- Red: IP pública estática 

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
___
___

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
sudo mkdir -p /run/iot-ssh-tunnel

# Establecer permisos
sudo chown -R iot-tunnel:iot-tunnel /home/iot-tunnel
sudo chmod 700 /home/iot-tunnel/.ssh
sudo chown iot-tunnel:iot-tunnel /var/log/iot-ssh-tunnel
sudo chown iot-tunnel:iot-tunnel /var/lib/iot-ssh-tunnel
sudo chown iot-tunnel:iot-tunnel /run/iot-ssh-tunnel
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
___
___

## Configuración de Dispositivos IoT

Existen dos métodos para configurar los dispositivos IoT: **Configuración Automática (Recomendada)** y **Configuración Manual (Avanzada)**.

---

## Método 1: Configuración Automática (Recomendada)

Este método utiliza un script interactivo que automatiza todo el proceso de configuración.

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

### Paso 3: Ejecutar Script de Configuración Automática

```bash
# Ejecutar el script de configuración interactiva
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh
```

El script solicitará la siguiente información:
- **IP o hostname del servidor SSH**: Ejemplo: `tunnel.example.com`
- **Puerto SSH del servidor**: Por defecto `22`
- **Usuario SSH del servidor**: Por defecto `iot-tunnel`
- **Cadena adicional para Device ID**: Opcional, para personalizar el ID

### Paso 4: Registrar Dispositivo en el Servidor

El script mostrará la información necesaria para registrar el dispositivo:

**En el dispositivo** verás algo como:

```
╔════════════════════════════════════════════════════════════════════════╗
║  INFORMACIÓN PARA REGISTRAR EL DISPOSITIVO EN EL SERVIDOR             ║
╚════════════════════════════════════════════════════════════════════════╝

1. Device ID:
   a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

2. Clave Pública SSH:
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-a1b2c3d4...

3. Fingerprint:
   SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**En el servidor**, ejecuta los comandos que muestra el script:

```bash
# 1. Crear archivo temporal con la clave pública
cat > /tmp/device_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6.pub << 'EOFKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-a1b2c3d4...
EOFKEY

# 2. Registrar el dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/device_registry.sh register \
    a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6 \
    /tmp/device_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6.pub

# 3. Anotar el puerto asignado
# Ejemplo de salida: Puerto asignado: 10001
```

### Paso 5: Completar Configuración

**De vuelta en el dispositivo**, presiona ENTER e ingresa el puerto asignado:

```
Presione ENTER cuando haya registrado el dispositivo en el servidor...
Ingrese el puerto asignado por el servidor: 10001
```

El script automáticamente:
- ✓ Configurará el túnel SSH
- ✓ Instalará el servicio systemd
- ✓ Habilitará el inicio automático
- ✓ Iniciará el servicio
- ✓ Mostrará instrucciones de verificación

### Paso 6: Verificar Instalación

El script mostrará comandos de verificación al finalizar:

**En el cliente (dispositivo IoT):**
```bash
# Ver estado del servicio
sudo systemctl status iot-ssh-tunnel

# Ver logs en tiempo real
sudo journalctl -u iot-ssh-tunnel -f
```

**En el servidor:**
```bash
# Listar túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Conectarse al dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c
```

---
---

## Método 2: Configuración Manual (Avanzada)

Si prefieres configurar manualmente cada paso, sigue estas instrucciones:

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

# Copiar configuración tmpfiles.d para crear directorios en el arranque
sudo cp /opt/iot-ssh-reverse-tunnel/client/systemd/iot-ssh-tunnel.conf \
    /etc/tmpfiles.d/

# Establecer permisos
sudo chmod +x /usr/local/bin/iot-tunnel-start.sh
sudo chmod +x /usr/local/bin/iot-tunnel-stop.sh

# Crear directorios requeridos
sudo mkdir -p /run/iot-ssh-tunnel
sudo mkdir -p /var/log/iot-ssh-tunnel
sudo chmod 755 /run/iot-ssh-tunnel
sudo chmod 755 /var/log/iot-ssh-tunnel

# Crear archivo known_hosts para evitar errores de solo lectura
sudo touch /etc/iot-ssh-tunnel/known_hosts
sudo chmod 644 /etc/iot-ssh-tunnel/known_hosts

# Aplicar configuración tmpfiles.d
sudo systemd-tmpfiles --create /etc/tmpfiles.d/iot-ssh-tunnel.conf

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

## Acceso a Dispositivos Desde el Servidor

### Gestión de Acceso con tunnel_manager.sh

El script `tunnel_manager.sh` incluye un comando `login` que facilita enormemente el acceso a los dispositivos IoT a través de los túneles SSH. Esta herramienta:

- Permite acceder a dispositivos usando solo los primeros 5+ caracteres del Device ID
- Almacena credenciales de forma segura
- Copia automáticamente las claves SSH en la primera conexión
- Elimina la necesidad de recordar puertos asignados
- Proporciona acceso sin contraseña después del primer login

### Uso Básico del Comando Login

**Sintaxis:**
```bash
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login <prefix> [usuario] [contraseña]
```

**Parámetros:**
- `prefix`: Primeros 5 o más caracteres del Device ID
- `usuario` (opcional): Usuario SSH del dispositivo
- `contraseña` (opcional): Contraseña del usuario

### Flujo de Trabajo - Primera Conexión

1. **Listar dispositivos disponibles:**
```bash
# Ver todos los dispositivos registrados con túneles activos y no activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list
# Ver todos los dispositivos registrados con túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active
```

2. **Conectar usando prefijo del Device ID:**
```bash
# Usar los primeros 5-8 caracteres del Device ID
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c
```

3. **Ingresar credenciales (solo primera vez):**
```
Usuario para el dispositivo: pi
Contraseña para el dispositivo: ********
```

4. **El script automáticamente:**
   - Verifica que el túnel esté activo
   - Valida las credenciales
   - Copia las claves SSH públicas al dispositivo
   - Guarda las credenciales en `/opt/iot-ssh-reverse-tunnel/server/configs/device_credentials`
   - Establece la conexión SSH

### Flujo de Trabajo - Conexiones Posteriores

```bash
# Simplemente usar el mismo comando
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c

# ¡Ya no pedirá contraseña! La autenticación usa claves SSH
```

### Ejemplos de Uso

**Conectar de forma interactiva:**
```bash
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46
# Se solicitará usuario y contraseña si es la primera vez
```

**Conectar especificando usuario:**
```bash
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46 admin
# Solo se solicitará contraseña
```

**Conectar con usuario y contraseña (no interactivo):**
```bash
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46 admin MySecurePass123
# Útil para scripts de automatización
```

### Manejo de Errores Comunes

**Error: Dispositivo no encontrado**
```bash
[ERROR] Dispositivo no encontrado con prefijo '123ab'
```
**Solución:** Verifica que el prefijo sea correcto usando `list`:
```bash
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list
```

**Error: Prefijo ambiguo**
```bash
[ERROR] Múltiples dispositivos encontrados con prefijo 'a1'
a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6
a1f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5
[ERROR] Prefijo ambiguo. Use más caracteres para identificar el dispositivo.
```
**Solución:** Usa un prefijo más largo (ej: `a1b2c` en lugar de `a1`)

**Error: Túnel no está activo**
```bash
[ERROR] El túnel no está activo. El dispositivo debe estar conectado.
```
**Solución:** Verifica que el dispositivo esté conectado:
```bash
# En el dispositivo IoT
sudo systemctl status iot-ssh-tunnel
```

**Error: Fallo de autenticación**
```bash
[ERROR] Fallo la autenticación. Verifique usuario y contraseña.
```
**Solución:** Verifica las credenciales del dispositivo y vuelve a intentar.

### Gestión de Credenciales

**Archivo de credenciales:**
- Ubicación: `/opt/iot-ssh-reverse-tunnel/server/configs/device_credentials`
- Permisos: `600` (solo lectura/escritura para el propietario)
- Formato: `DEVICE_ID|USERNAME|HAS_PASSWORD`

**Ver credenciales guardadas:**
```bash
sudo cat /opt/iot-ssh-reverse-tunnel/server/configs/device_credentials
```

**Eliminar credenciales de un dispositivo:**
```bash
# Para forzar reingreso de credenciales en próximo login
sudo sed -i '/^a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6|/d' \
    /opt/iot-ssh-reverse-tunnel/server/configs/device_credentials
```

### Recomendaciones de Seguridad

1. **Instalar sshpass para mejor experiencia:**
```bash
sudo apt-get install sshpass
```
Sin `sshpass`, la copia de claves SSH requerirá ingresar la contraseña manualmente.

2. **Usar claves SSH robustas:**
El script generará automáticamente claves ED25519 si no existen:
```bash
# Verificar claves SSH del servidor
ls -la ~/.ssh/id_*.pub
```

3. **Proteger el archivo de credenciales:**
```bash
# Verificar permisos
ls -la /opt/iot-ssh-reverse-tunnel/server/configs/device_credentials

# Debe mostrar: -rw------- (600)
```

4. **No versionar credenciales:**
El archivo `device_credentials` está automáticamente excluido en `.gitignore`.

### Ventajas del Comando Login

✅ **Simplicidad**: No necesitas recordar puertos asignados
✅ **Seguridad**: Usa autenticación por claves SSH después del primer login
✅ **Rapidez**: Acceso con solo 5-8 caracteres del Device ID
✅ **Automatización**: Soporta modo no interactivo para scripts
✅ **Gestión centralizada**: Credenciales almacenadas de forma segura

## Verificación y Testing

### Test 1: Conectividad Básica

**Desde el servidor (método directo):**

```bash
# Conectar al dispositivo a través del túnel
ssh -p ${ASSIGNED_PORT} localhost

# Deberías ver el prompt del dispositivo IoT
```

**Desde el servidor (usando tunnel_manager.sh login):**

```bash
# Conectar usando prefijo del Device ID (más fácil y recomendado)
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c

# Primera vez - se solicitará usuario y contraseña
# Usuario para el dispositivo: pi
# Contraseña para el dispositivo: ********

# El script automáticamente:
# - Encuentra el dispositivo por el prefijo del ID
# - Verifica que el túnel esté activo
# - Copia las claves SSH al dispositivo
# - Guarda las credenciales de forma segura
# - Abre una sesión SSH al dispositivo

# Conexiones posteriores - NO requieren contraseña
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c

# También puedes especificar usuario y contraseña directamente
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login a1b2c myuser mypassword
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
cp client/systemd/iot-ssh-tunnel.conf /etc/tmpfiles.d/
chmod +x /usr/local/bin/iot-tunnel-*.sh

# Crear directorios y archivos requeridos
mkdir -p /run/iot-ssh-tunnel /var/log/iot-ssh-tunnel
touch /etc/iot-ssh-tunnel/known_hosts
chmod 644 /etc/iot-ssh-tunnel/known_hosts
systemd-tmpfiles --create /etc/tmpfiles.d/iot-ssh-tunnel.conf

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

## Troubleshooting

### Error: "ssh: Could not resolve hostname ssh"

**Síntoma:**
```bash
ssh: Could not resolve hostname ssh: Name or service not known
autossh[xxxx]: ssh exited with error status 255; restarting ssh
```

**Causa:** El comando autossh está mal formado y está interpretando "ssh" como un hostname en lugar de un comando.

**Solución:** Este error fue corregido en las versiones actuales. Si lo encuentras, asegúrate de que:
- Los scripts usen `SSH_ARGS` (solo argumentos) en lugar de `SSH_CMD` (que incluía "ssh")
- El comando autossh debe ser: `autossh -M "${AUTOSSH_PORT}" ${SSH_ARGS}`
- Actualiza los archivos desde el repositorio

### Error: "Could not create directory '/root/.ssh'"

**Síntoma:**
```bash
Could not create directory '/root/.ssh' (Read-only file system)
Failed to add the host to the list of known hosts (/root/.ssh/known_hosts)
```

**Causa:** Las restricciones de seguridad de systemd (`ProtectSystem=strict`) impiden la escritura en `/root/.ssh`.

**Solución:**
```bash
# Crear archivo known_hosts en ubicación permitida
sudo touch /etc/iot-ssh-tunnel/known_hosts
sudo chmod 644 /etc/iot-ssh-tunnel/known_hosts

# Regenerar configuración para incluir UserKnownHostsFile
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh setup \
    ${SERVER_HOST} 22 iot-tunnel ${ASSIGNED_PORT}

# Verificar que /etc/iot-ssh-tunnel/tunnel.conf incluya:
# SSH_OPTIONS="... -o UserKnownHostsFile=/etc/iot-ssh-tunnel/known_hosts"
```

### Error: "Failed to set up mount namespacing"

**Síntoma:**
```bash
iot-ssh-tunnel.service: Failed to set up mount namespacing: /run/iot-ssh-tunnel: No such file or directory
Main process exited, code=exited, status=226/NAMESPACE
```

**Causa:** Los directorios requeridos por systemd no existen.

**Solución:**
```bash
# Crear directorios manualmente
sudo mkdir -p /run/iot-ssh-tunnel
sudo mkdir -p /var/log/iot-ssh-tunnel
sudo chmod 755 /run/iot-ssh-tunnel
sudo chmod 755 /var/log/iot-ssh-tunnel

# Instalar configuración tmpfiles.d
sudo cp /opt/iot-ssh-reverse-tunnel/client/systemd/iot-ssh-tunnel.conf \
    /etc/tmpfiles.d/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/iot-ssh-tunnel.conf

# Reiniciar servicio
sudo systemctl daemon-reload
sudo systemctl restart iot-ssh-tunnel
```

### Error: "remote port forwarding failed for listen port"

**Síntoma:**
```bash
Error: remote port forwarding failed for listen port 10000
ssh exited with error status 255
```

**Causas posibles:**
1. El puerto ya está en uso en el servidor
2. El puerto no está autorizado en la configuración SSH del servidor
3. Hay una conexión previa que no se cerró correctamente

**Solución:**

**En el servidor:**
```bash
# Verificar si el puerto está en uso
sudo ss -tlnp | grep :10000

# Si hay una conexión colgada, terminarla
sudo pkill -f "sshd.*:10000"

# Verificar que el puerto esté autorizado en /etc/ssh/sshd_config.d/iot-tunnel.conf
grep "PermitListen.*10000" /etc/ssh/sshd_config.d/iot-tunnel.conf

# Si no está, agregarlo
echo "PermitListen 10000" | sudo tee -a /etc/ssh/sshd_config.d/iot-tunnel.conf
sudo systemctl reload ssh
```

**En el dispositivo:**
```bash
# Reintentar conexión
sudo systemctl restart iot-ssh-tunnel
sudo systemctl status iot-ssh-tunnel
```

### Servicio inactivo después de instalación

**Síntoma:** El test de conectividad es exitoso pero `systemctl status` muestra el servicio inactivo.

**Solución:**
```bash
# Verificar logs detallados
sudo journalctl -u iot-ssh-tunnel -n 50 --no-pager

# Verificar que todos los archivos estén en su lugar
ls -la /usr/local/bin/iot-tunnel-start.sh
ls -la /usr/local/bin/iot-tunnel-stop.sh
ls -la /etc/systemd/system/iot-ssh-tunnel.service
ls -la /etc/iot-ssh-tunnel/tunnel.conf

# Reiniciar servicio con logs en tiempo real
sudo systemctl restart iot-ssh-tunnel
sudo journalctl -u iot-ssh-tunnel -f
```

### Verificación de conectividad

**Comprobar que el túnel funciona correctamente:**

**En el dispositivo:**
```bash
# Ver estado del servicio
sudo systemctl status iot-ssh-tunnel

# Ver logs en tiempo real
sudo journalctl -u iot-ssh-tunnel -f

# Verificar procesos autossh/ssh
ps aux | grep -E "(autossh|ssh.*iot-tunnel)"
```

**En el servidor:**
```bash
# Listar túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Verificar puerto específico
sudo ss -tlnp | grep :10000

# Intentar conexión SSH al dispositivo
ssh -p 10000 localhost
```

### Logs útiles para debugging

```bash
# En el dispositivo - logs del servicio
sudo journalctl -u iot-ssh-tunnel --no-pager -n 100

# En el dispositivo - logs del script
sudo tail -f /var/log/iot-ssh-tunnel/service.log

# En el servidor - logs SSH
sudo tail -f /var/log/auth.log | grep iot-tunnel

# En el servidor - logs de túneles
sudo tail -f /var/log/iot-ssh-tunnel/tunnel.log
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
- [ ] Directorios runtime creados (`/run/iot-ssh-tunnel`, `/var/log/iot-ssh-tunnel`)
- [ ] Archivo `known_hosts` creado (`/etc/iot-ssh-tunnel/known_hosts`)
- [ ] Configuración tmpfiles.d instalada (`/etc/tmpfiles.d/iot-ssh-tunnel.conf`)
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
