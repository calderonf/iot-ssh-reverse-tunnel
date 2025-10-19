# Guía de Despliegue Rápido - Túneles SSH Inversos para IoT

Esta guía te permitirá configurar el sistema de túneles SSH inversos en menos de 15 minutos.

## 📋 Requisitos Previos

- **Servidor**: Máquina Linux con IP pública (Ubuntu 20.04+ / Debian 11+)
- **Dispositivos IoT**: Dispositivos Linux con conexión a Internet
- Acceso root/sudo en ambos

---

## 🚀 Parte 1: Configuración del Servidor (Una sola vez)

### Paso 1: Preparar el Sistema

```bash
# Actualizar sistema
sudo apt-get update && sudo apt-get upgrade -y

# Instalar dependencias
sudo apt-get install -y openssh-server git netstat-nat net-tools sshpass
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

### Paso 3: Instalar el Sistema

```bash
# Clonar repositorio
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

# IMPORTANTE: Editar el archivo para autorizar puertos
sudo nano /etc/ssh/sshd_config.d/iot-tunnel.conf
```

**Agregar líneas `PermitListen` para cada puerto que usarás (10000-20000):**

```
# Ejemplo: autorizar 10 dispositivos
PermitListen 10000
PermitListen 10001
PermitListen 10002
PermitListen 10003
PermitListen 10004
PermitListen 10005
PermitListen 10006
PermitListen 10007
PermitListen 10008
PermitListen 10009
```

```bash
# Verificar sintaxis
sudo sshd -t

# Recargar SSH
sudo systemctl reload ssh   # Debian/Ubuntu
# sudo systemctl reload sshd  # RHEL/CentOS

# Verificar que está escuchando
sudo ss -tlnp | grep :22
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
sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status
```

**Cloud (Azure/AWS/GCP):**

Abre el puerto 22 (SSH) en el grupo de seguridad de tu VM.

### ✅ Verificación del Servidor

```bash
# Verificar que el servicio SSH está activo
sudo systemctl status ssh

# Listar túneles (debe estar vacío por ahora)
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list
```

---

## 📱 Parte 2: Agregar Dispositivos IoT (Repetir por cada dispositivo)

### Método Automático (Recomendado)

#### En el Dispositivo IoT:

**Paso 1: Preparar Sistema**

```bash
# Actualizar e instalar dependencias
sudo apt-get update
sudo apt-get install -y openssh-client autossh git

# Clonar repositorio
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel
sudo chmod +x client/scripts/*.sh security/*.sh
```

**Paso 2: Ejecutar Configuración Automática**

```bash
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh
```

El script solicitará:
- **IP del servidor**: `tu-servidor.com` o `x.x.x.x`
- **Puerto SSH**: `22` (por defecto)
- **Usuario SSH**: `iot-tunnel` (por defecto)
- **Semilla Device ID**: (opcional, dejar vacío)

**Paso 3: Copiar Información Mostrada**

El script mostrará algo como:

```
╔════════════════════════════════════════════════════════════════════════╗
║  INFORMACIÓN PARA REGISTRAR EL DISPOSITIVO EN EL SERVIDOR             ║
╚════════════════════════════════════════════════════════════════════════╝

1. Device ID:
   18e466389ef615c415fff9a98735efb8

2. Clave Pública SSH:
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-18e46...

3. Fingerprint:
   SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### En el Servidor:

**Paso 4: Registrar el Dispositivo**

Copia y ejecuta los comandos que muestra el script del dispositivo:

```bash
# 1. Crear archivo temporal con la clave pública
cat > /tmp/device_18e466389ef615c415fff9a98735efb8.pub << 'EOFKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-18e46...
EOFKEY

# 2. Registrar el dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/device_registry.sh register \
    18e466389ef615c415fff9a98735efb8 \
    /tmp/device_18e466389ef615c415fff9a98735efb8.pub
```

**Anota el puerto asignado** (ejemplo: `Puerto asignado: 10000`)

#### De vuelta en el Dispositivo IoT:

**Paso 5: Completar Configuración**

- Presiona **ENTER** en el script
- Ingresa el **puerto asignado** por el servidor

¡Listo! El script completará automáticamente la configuración.

---

## ✅ Verificación del Sistema

### En el Dispositivo IoT:

```bash
# Ver estado del servicio
sudo systemctl status iot-ssh-tunnel

# Ver logs en tiempo real
sudo journalctl -u iot-ssh-tunnel -f

# Verificar estado del túnel
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh status
```

**Output esperado:**
```
✓ Servicio activo y corriendo
✓ Túnel SSH establecido
✓ Conectividad verificada
```

### En el Servidor:

```bash
# Listar todos los túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Ver estadísticas
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh stats

# Verificar dispositivo específico
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh check 18e46638...
```

---

## 🔌 Acceder a los Dispositivos

### Método 1: Usando tunnel_manager (Recomendado)

```bash
# Conectar con prefijo del Device ID (solo primeros 5-8 caracteres)
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46

# Primera vez: se pedirá usuario y contraseña del dispositivo
# El sistema copiará las claves SSH automáticamente

# Próximas veces: ¡Sin contraseña!
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46
```

### Método 2: SSH Directo por Puerto

```bash
# Conectar directamente al puerto asignado
ssh -p 10000 usuario@localhost
```

---

## 🔧 Comandos Útiles

### Gestión de Túneles (Servidor)

```bash
# Listar todos los dispositivos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list

# Listar solo activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Estadísticas
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh stats

# Verificar dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh check <device_id>

# Cerrar túnel
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh close <device_id>

# Monitoreo en tiempo real
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh monitor

# Diagnosticar SSH de dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh diagnose 18e46 user pass
```

### Gestión del Cliente (Dispositivo)

```bash
# Estado del servicio
sudo systemctl status iot-ssh-tunnel

# Reiniciar servicio
sudo systemctl restart iot-ssh-tunnel

# Ver logs
sudo journalctl -u iot-ssh-tunnel -f

# Verificar túnel
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh status

# Probar conectividad
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh test
```

---

## 🚨 Troubleshooting Rápido

### El túnel no se conecta

**En el dispositivo:**
```bash
# Ver logs detallados
sudo journalctl -u iot-ssh-tunnel -n 50

# Verificar que la clave existe
ls -la /etc/iot-ssh-tunnel/tunnel_key*

# Probar conexión manual
ssh -i /etc/iot-ssh-tunnel/tunnel_key iot-tunnel@servidor
```

**En el servidor:**
```bash
# Verificar que el puerto está autorizado
grep "PermitListen.*10000" /etc/ssh/sshd_config.d/iot-tunnel.conf

# Ver logs SSH
sudo tail -f /var/log/auth.log | grep iot-tunnel

# Verificar que el dispositivo está registrado
cat /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping
```

### No puedo acceder con login

```bash
# Verificar que el túnel está activo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Diagnosticar
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh diagnose 18e46 usuario contraseña

# Borrar credenciales guardadas y volver a intentar
sudo rm /opt/iot-ssh-reverse-tunnel/server/configs/device_credentials
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46 usuario contraseña
```

### El servicio no inicia en el dispositivo

```bash
# Crear directorios necesarios
sudo mkdir -p /run/iot-ssh-tunnel /var/log/iot-ssh-tunnel
sudo chmod 755 /run/iot-ssh-tunnel /var/log/iot-ssh-tunnel

# Crear known_hosts
sudo touch /etc/iot-ssh-tunnel/known_hosts
sudo chmod 644 /etc/iot-ssh-tunnel/known_hosts

# Aplicar tmpfiles.d
sudo systemd-tmpfiles --create /etc/tmpfiles.d/iot-ssh-tunnel.conf

# Reiniciar
sudo systemctl daemon-reload
sudo systemctl restart iot-ssh-tunnel
```

---

## 📚 Documentación Adicional

- **Guía Detallada**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Arquitectura**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Seguridad**: [SECURITY.md](SECURITY.md)
- **Scripts del Cliente**: [client/scripts/README.md](../client/scripts/README.md)

---

## 💡 Consejos Finales

1. **Documenta los Device IDs**: Mantén un registro de qué dispositivo corresponde a cada ID
2. **Monitorea regularmente**: Usa `tunnel_manager.sh stats` para ver el estado general
3. **Backups**: Respalda `/opt/iot-ssh-reverse-tunnel/server/configs/` regularmente
4. **Rotación de claves**: Considera rotar claves SSH cada 90 días
5. **Logs**: Revisa logs periódicamente para detectar problemas temprano

---

## 🎯 Resumen del Flujo

```
┌─────────────────────────────────────────────────────────────┐
│  SERVIDOR (Una sola vez)                                    │
├─────────────────────────────────────────────────────────────┤
│  1. Instalar dependencias                                   │
│  2. Crear usuario iot-tunnel                                │
│  3. Clonar repositorio                                      │
│  4. Configurar SSH (autorizar puertos)                      │
│  5. Inicializar sistema                                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  DISPOSITIVO IoT (Por cada dispositivo)                     │
├─────────────────────────────────────────────────────────────┤
│  1. Instalar dependencias                                   │
│  2. Clonar repositorio                                      │
│  3. Ejecutar setup_client.sh                                │
│  4. Copiar información al servidor                          │
│  5. Registrar en servidor                                   │
│  6. Ingresar puerto asignado                                │
│  7. ¡Listo!                                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  ACCESO                                                      │
├─────────────────────────────────────────────────────────────┤
│  tunnel_manager.sh login <prefix>                           │
│  Primera vez: configura claves SSH                          │
│  Siguientes: acceso directo sin contraseña                  │
└─────────────────────────────────────────────────────────────┘
```

---

**¿Problemas?** Consulta la [Guía de Troubleshooting](DEPLOYMENT.md#troubleshooting) detallada.
