# Arquitectura del Sistema de Túneles SSH Inversos para IoT

## Visión General

Este sistema proporciona conectividad remota segura a dispositivos IoT ubicados detrás de NAT mediante túneles SSH inversos persistentes con autossh.

## Componentes Principales

### 1. Servidor Central

Servidor público accesible desde Internet que actúa como punto de entrada para los túneles SSH inversos.

**Responsabilidades:**
- Aceptar conexiones SSH inversas desde dispositivos IoT
- Mantener registro centralizado de dispositivos
- Gestionar asignación dinámica de puertos
- Monitorear estado de conexiones
- Autenticar dispositivos mediante claves SSH

**Componentes:**
```
server/
├── scripts/
│   ├── device_registry.sh      - Registro y gestión de dispositivos
│   ├── tunnel_manager.sh       - Gestión de túneles activos
│   ├── connection_monitor.sh   - Monitoreo de conexiones
│   └── tunnel-only.sh          - Contención para sesiones de túnel
└── configs/
    ├── sshd_config.d/
    │   └── iot-tunnel.conf     - Configuración endurecida para túneles inversos
    └── device_mapping.example  - Plantilla de mapeo dispositivo → puerto
```

### 2. Dispositivos IoT (Clientes)

Dispositivos embebidos que establecen túneles SSH inversos hacia el servidor central.

**Responsabilidades:**
- Generar identificador único de dispositivo
- Establecer túnel SSH inverso
- Mantener conexión persistente
- Reconectar automáticamente tras desconexiones

**Componentes:**
```
client/
├── scripts/
│   ├── device_identifier.sh    - Generación de ID único
│   ├── ssh_tunnel_setup.sh     - Configuración del túnel
│   └── auto_reconnect.sh       - Sistema de reconexión
└── systemd/
    ├── autossh-iot-tunnel.service - Servicio systemd basado en autossh
    ├── iot-ssh-tunnel.service     - Servicio heredado gestionado por scripts
    ├── iot-tunnel-start.sh        - Script de inicio
    └── iot-tunnel-stop.sh         - Script de detención
```

### 3. Sistema de Seguridad

Gestión de credenciales SSH y rotación de claves.

**Componentes:**
```
security/
├── keygen.sh           - Generación de pares de claves SSH
└── key_rotation.sh     - Rotación periódica de claves
```

## Flujo de Operación

### Fase 1: Registro Inicial

```
┌─────────────┐                    ┌──────────────┐
│  Dispositivo│                    │   Servidor   │
│     IoT     │                    │   Central    │
└──────┬──────┘                    └──────┬───────┘
       │                                  │
       │ 1. Generar Device ID             │
       │    (machine-id hash)             │
       │                                  │
       │ 2. Generar par de claves SSH     │
       │    (ed25519)                     │
       │                                  │
       │ 3. Enviar clave pública      ──► │
       │                                  │
       │                                  │ 4. Registrar dispositivo
       │                                  │    - Asignar puerto
       │                                  │    - Almacenar fingerprint
       │                                  │    - Actualizar authorized_keys
       │                                  │
       │ ◄──  5. Confirmar registro       │
       │        (puerto asignado)         │
       │                                  │
```

### Fase 2: Establecimiento del Túnel

```
┌─────────────┐                    ┌──────────────┐
│  Dispositivo│                    │   Servidor   │
│     IoT     │                    │   Central    │
└──────┬──────┘                    └──────┬───────┘
       │                                  │
       │ 1. Iniciar autossh               │
       │                                  │
       │ 2. SSH -R puerto:localhost:22 ──►│
       │                                  │
       │                                  │ 3. Validar clave SSH
       │                                  │
       │                                  │ 4. Establecer túnel
       │                                  │
       │ ◄──  5. Túnel establecido        │
       │                                  │
       │                                  │
       │ 6. Keep-alive (cada 30s)     ──► │
       │                                  │
```

### Fase 3: Acceso Remoto

```
┌──────────┐    ┌──────────────┐    ┌─────────────┐
│Administra│    │   Servidor   │    │ Dispositivo │
│   dor    │    │   Central    │    │     IoT     │
└────┬─────┘    └──────┬───────┘    └──────┬──────┘
     │                 │                   │
     │ 1. SSH al puerto                   │
     │    del túnel ──►│                   │
     │                 │                   │
     │                 │ 2. Reenvío    ──► │
     │                 │    por túnel      │
     │                 │                   │
     │                 │                   │ 3. Aceptar conexión
     │                 │                   │
     │ ◄───────────────┴─────── 4. Sesión SSH establecida
     │                                     │
```

## Arquitectura de Red

### Topología

```
                     Internet
                        │
                        │
              ┌─────────▼─────────┐
              │  Servidor Central │
              │  IP Pública       │
              │  Puerto SSH: 22   │
              └─────────┬─────────┘
                        │
         ┌──────────────┼──────────────┐
         │              │              │
    ┌────▼────┐    ┌────▼────┐    ┌───▼─────┐
    │Túnel    │    │Túnel    │    │Túnel    │
    │Puerto   │    │Puerto   │    │Puerto   │
    │10001    │    │10002    │    │10003    │
    └────┬────┘    └────┬────┘    └────┬────┘
         │              │              │
         │              │              │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │ NAT/    │    │ NAT/    │    │ NAT/    │
    │Firewall │    │Firewall │    │Firewall │
    └────┬────┘    └────┬────┘    └────┬────┘
         │              │              │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │Disposit.│    │Disposit.│    │Disposit.│
    │IoT #1   │    │IoT #2   │    │IoT #3   │
    └─────────┘    └─────────┘    └─────────┘
```

### Asignación de Puertos

- **Puerto SSH Servidor:** 22 (estándar, configurable)
- **Rango de Túneles:** 10000-20000
- **Asignación:** Dinámica, un puerto único por dispositivo
- **Persistencia:** Mapping almacenado en `device_mapping`

## Modelo de Datos

### Device Mapping (servidor)

```
device_id|port|fingerprint|registered_date|status
a1b2c3d4...|10001|SHA256:xxx...|2024-01-15 10:30:00|active
f6e5d4c3...|10002|SHA256:yyy...|2024-01-15 11:45:00|active
```

**Campos:**
- `device_id`: Hash MD5 de machine-id (32 caracteres hex)
- `port`: Puerto asignado para el túnel (10000-20000)
- `fingerprint`: Fingerprint SHA256 de la clave pública SSH
- `registered_date`: Timestamp de registro
- `status`: Estado del dispositivo (active/inactive)

### Connection State (servidor)

```
device_id|last_seen|connection_status|alert_sent
a1b2c3d4...|1674123456|connected|0
```

**Campos:**
- `device_id`: Identificador del dispositivo
- `last_seen`: Unix timestamp de última conexión
- `connection_status`: Estado actual (connected/disconnected)
- `alert_sent`: Timestamp de última alerta enviada

### Tunnel Configuration (cliente)

```bash
SERVER_HOST="tunnel.example.com"
SERVER_PORT="22"
SERVER_USER="iot-tunnel"
TUNNEL_PORT="10001"
SSH_OPTIONS="-o ServerAliveInterval=30 ..."
SSH_KEY="/etc/iot-ssh-tunnel/tunnel_key"
```

## Mecanismos de Seguridad

### 1. Autenticación

- **Claves SSH públicas/privadas** (sin contraseñas)
- **Tipos soportados:** ed25519 (recomendado), RSA 4096, ECDSA 521
- **Fingerprint tracking** para detección de cambios

### 2. Autorización

- **Restricted SSH commands:** Túneles únicamente
- **Port forwarding limitado:** Solo puertos asignados
- **No shell access:** ForceCommand o command restriction

### 3. Cifrado

- **SSH Protocol 2:** Cifrado de extremo a extremo
- **Forward secrecy:** Rotación de claves de sesión
- **Integridad:** HMAC para detección de manipulación

### 4. Aislamiento

- **Usuario dedicado:** iot-tunnel (sin privilegios)
- **Chroot/Sandbox:** Opcional con ForceCommand
- **Rate limiting:** MaxStartups, MaxSessions

### 5. Auditoría

- **Logging centralizado:** Todas las conexiones
- **Metrics tracking:** Estado de túneles
- **Alert system:** Notificación de anomalías

## Estrategias de Resilencia

### Reconexión Automática

1. **Autossh:** Monitoreo y reconexión automática
2. **Keep-alive:** ServerAliveInterval=30, ServerAliveCountMax=3
3. **Backoff exponencial:** Delays incrementales tras fallos
4. **Max retry limits:** Prevenir loops infinitos

### Tolerancia a Fallos

1. **Stateless server:** No depende de estado local
2. **Persistent configuration:** Configuración en disco
3. **Service recovery:** Systemd restart policies
4. **Graceful degradation:** Continuar con dispositivos disponibles

### Monitoreo

1. **Health checks:** Verificación periódica de túneles
2. **Connection tracking:** Estado en tiempo real
3. **Metrics collection:** Estadísticas de disponibilidad
4. **Alerting:** Notificaciones de desconexiones prolongadas

## Escalabilidad

### Límites Actuales

- **Dispositivos simultáneos:** ~10,000 (rango de puertos)
- **Conexiones concurrentes:** Limitado por SSH server config
- **Recursos del servidor:** CPU, memoria, descriptores de archivo

### Estrategias de Escalado

1. **Vertical:**
   - Incrementar recursos del servidor
   - Optimizar SSH configuration (MaxStartups, MaxSessions)
   - Usar hardware acelerado para cifrado

2. **Horizontal:**
   - Múltiples servidores con balanceo de carga
   - Sharding por rangos de device_id
   - DNS round-robin para distribución

3. **Optimización:**
   - Multiplexing SSH con ControlMaster
   - Compresión selectiva
   - Connection pooling

## Consideraciones de Deployment

### Servidor

- **OS:** Debian/Ubuntu LTS
- **Recursos mínimos:** 2 vCPU, 4GB RAM, 50GB disco
- **Red:** IP pública, firewall configurado
- **Backups:** device_mapping, logs, authorized_keys

### Dispositivos IoT

- **OS:** Linux embebido (Debian, Yocto, etc.)
- **Recursos mínimos:** 256MB RAM, 500MB disco
- **Red:** Conectividad IP (WiFi, Ethernet, Celular)
- **Persistencia:** device_id, tunnel_key, configuración

## Patrones de Uso

### 1. Acceso de Mantenimiento

Administrador necesita acceder a dispositivo para diagnóstico.

```bash
# En el servidor
ssh -p 10001 localhost

# Esto conecta al dispositivo IoT vía túnel
```

### 2. Deployment de Actualizaciones

Script de actualización ejecutado remotamente en múltiples dispositivos.

```bash
# Iterar sobre dispositivos activos
for port in $(get_active_tunnels); do
    ssh -p $port localhost "update_firmware.sh"
done
```

### 3. Recolección de Logs

Centralización de logs desde dispositivos remotos.

```bash
# Recolectar logs de todos los dispositivos
for device in $(list_devices); do
    scp -P $port localhost:/var/log/app.log logs/$device.log
done
```

## Referencias Técnicas

- SSH Protocol: RFC 4251-4254
- Autossh: https://www.harding.motd.ca/autossh/
- Systemd Service: systemd.service(5)
- Security Best Practices: NIST SP 800-123
