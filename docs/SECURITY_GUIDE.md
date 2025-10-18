# Guía de Seguridad - Túneles SSH Inversos para IoT

## Principios de Seguridad

Este sistema implementa los siguientes principios de seguridad:

1. **Defensa en profundidad**: Múltiples capas de seguridad
2. **Mínimo privilegio**: Acceso limitado a lo estrictamente necesario
3. **Autenticación fuerte**: Claves SSH sin contraseñas
4. **Auditoría completa**: Logging de todas las operaciones
5. **Cifrado end-to-end**: Todas las comunicaciones cifradas

## Configuración SSH Segura

### Servidor

**Configuración recomendada** (`/etc/ssh/sshd_config.d/iot-tunnel.conf`):

```
# Autenticación solo por clave pública
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Deshabilitar acceso root
PermitRootLogin no

# Protocolo SSH 2 únicamente
Protocol 2

# Cifrados fuertes
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group-exchange-sha256

# Usuario dedicado con restricciones
Match User iot-tunnel
    AllowTcpForwarding yes
    GatewayPorts no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    PermitOpen localhost:10000-20000
    ClientAliveInterval 30
    ClientAliveCountMax 3
```

### Clientes

**Opciones SSH recomendadas**:

```
-o ServerAliveInterval=30
-o ServerAliveCountMax=3
-o ExitOnForwardFailure=yes
-o StrictHostKeyChecking=accept-new
-o UserKnownHostsFile=/etc/iot-ssh-tunnel/known_hosts
```

## Gestión de Claves SSH

### Generación de Claves

**Algoritmo recomendado: Ed25519**

```bash
# Generar clave ed25519 (más segura y rápida)
ssh-keygen -t ed25519 -f /etc/iot-ssh-tunnel/tunnel_key -C "iot-device-$(hostname)"

# Alternativa: RSA 4096 (compatible legacy)
ssh-keygen -t rsa -b 4096 -f /etc/iot-ssh-tunnel/tunnel_key -C "iot-device-$(hostname)"
```

**NO usar:**
- RSA menor a 2048 bits
- DSA (obsoleto)
- Claves con passphrase vacía en sistemas multi-usuario

### Permisos de Archivos

```bash
# Clave privada: solo lectura por propietario
chmod 600 /etc/iot-ssh-tunnel/tunnel_key

# Clave pública: lectura por todos
chmod 644 /etc/iot-ssh-tunnel/tunnel_key.pub

# Directorio de configuración
chmod 700 /etc/iot-ssh-tunnel

# authorized_keys en servidor
chmod 600 /home/iot-tunnel/.ssh/authorized_keys
chmod 700 /home/iot-tunnel/.ssh
```

### Rotación de Claves

**Frecuencia recomendada: cada 90 días**

```bash
# Generar reporte de claves antiguas
./security/key_rotation.sh report \
    /opt/iot-ssh-reverse-tunnel/server/configs/device_mapping 90

# Rotar clave de dispositivo
./security/key_rotation.sh rotate <device_id> <current_key_path> ed25519
```

### Restricciones en authorized_keys

**Formato recomendado:**

```
command="echo 'Tunnel only'",no-agent-forwarding,no-X11-forwarding,no-pty,no-user-rc,permitopen="localhost:10001" ssh-ed25519 AAAAC3...
```

**Restricciones:**
- `command="..."`: Fuerza comando específico
- `no-agent-forwarding`: Previene forwarding de SSH agent
- `no-X11-forwarding`: Deshabilita X11
- `no-pty`: Sin terminal interactivo
- `no-user-rc`: No ejecutar ~/.ssh/rc
- `permitopen="..."`: Solo permitir forwarding a puerto específico

## Firewall y Seguridad de Red

### Servidor

**Reglas mínimas (iptables):**

```bash
# Permitir SSH entrante
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Permitir conexiones establecidas
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Denegar todo lo demás (default deny)
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Rate limiting para prevenir brute force
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# Guardar reglas
iptables-save > /etc/iptables/rules.v4
```

**UFW (más simple):**

```bash
# Configuración básica
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp

# Rate limiting
ufw limit 22/tcp

# Habilitar
ufw enable
```

### Cloud Providers

Ver ejemplos específicos en `/examples/cloud_providers/`

## Aislamiento y Sandboxing

### Usuario Dedicado

```bash
# Crear usuario sin shell ni home directory escribible
useradd -r -m -d /home/iot-tunnel -s /usr/sbin/nologin iot-tunnel

# Limitar recursos con systemd
# En el archivo .service:
[Service]
User=iot-tunnel
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/iot-ssh-tunnel /var/run/iot-ssh-tunnel
```

### Namespaces y Cgroups

**Limitar recursos del servicio:**

```
[Service]
# Límites de memoria
MemoryLimit=512M
MemoryHigh=400M

# Límites de CPU
CPUQuota=50%

# Límites de procesos
TasksMax=100

# Límites de archivos abiertos
LimitNOFILE=1024
```

## Auditoría y Logging

### Configuración de Logging

**Servidor SSH:**

```
# En sshd_config
SyslogFacility AUTH
LogLevel VERBOSE
```

**Logs del sistema:**

```bash
# Ver logs de SSH
journalctl -u sshd -f

# Ver logs de túneles
tail -f /var/log/iot-ssh-tunnel/*.log

# Logs de autenticación
tail -f /var/log/auth.log
```

### Qué Monitorear

1. **Intentos de autenticación fallidos**
   ```bash
   grep "Failed password" /var/log/auth.log
   grep "Invalid user" /var/log/auth.log
   ```

2. **Conexiones exitosas**
   ```bash
   grep "Accepted publickey" /var/log/auth.log
   ```

3. **Cambios en authorized_keys**
   ```bash
   # Monitorear con auditd
   auditctl -w /home/iot-tunnel/.ssh/authorized_keys -p wa
   ```

4. **Uso de recursos**
   ```bash
   # Conexiones activas
   ss -tn | grep :22

   # Uso de puertos de túnel
   ss -tn | grep "10[0-9][0-9][0-9]"
   ```

### Centralización de Logs

**Configurar rsyslog para enviar logs centralizados:**

```bash
# En /etc/rsyslog.d/iot-tunnel.conf
:programname, isequal, "iot-ssh-tunnel" @@log-server:514
```

## Detección de Intrusiones

### Fail2ban

**Configuración para SSH:**

```ini
# /etc/fail2ban/jail.d/sshd.conf
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
```

### Monitoreo de Anomalías

**Alertas automáticas:**

```bash
# Dispositivos desconectados por más de 5 minutos
./server/scripts/connection_monitor.sh daemon 60

# Múltiples intentos de conexión desde misma IP
watch -n 60 'grep "Failed" /var/log/auth.log | tail -20'
```

## Hardening del Sistema

### Servidor

```bash
# Deshabilitar servicios innecesarios
systemctl disable avahi-daemon
systemctl disable cups
systemctl disable bluetooth

# Actualizar sistema regularmente
apt-get update && apt-get upgrade -y

# Instalar actualizaciones de seguridad automáticas
apt-get install unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

# Configurar kernel hardening
cat >> /etc/sysctl.conf << EOF
# Protección contra SYN floods
net.ipv4.tcp_syncookies = 1

# Ignorar ICMP redirects
net.ipv4.conf.all.accept_redirects = 0

# No enviar ICMP redirects
net.ipv4.conf.all.send_redirects = 0

# Protección contra IP spoofing
net.ipv4.conf.all.rp_filter = 1

# Log de paquetes sospechosos
net.ipv4.conf.all.log_martians = 1
EOF

sysctl -p
```

### Dispositivos IoT

```bash
# Deshabilitar servicios innecesarios
systemctl disable bluetooth
systemctl disable ModemManager

# Firewall básico (solo salida)
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Limitar acceso físico si es posible
# - Deshabilitar USB
# - Cifrar disco
# - Secure boot
```

## Gestión de Secretos

### Almacenamiento Seguro

**NO almacenar en:**
- Código fuente
- Variables de entorno no cifradas
- Archivos de configuración en repositorio git

**Almacenar en:**
- Filesystem con permisos restrictivos (600)
- Encrypted filesystems (LUKS)
- Hardware Security Modules (HSM) si disponible
- Secrets management (Vault, etc.) para deployments grandes

### Transmisión Segura

**Para deployment inicial:**

```bash
# Usar scp con verificación de fingerprint
scp -o StrictHostKeyChecking=ask device_key root@device:/etc/iot-ssh-tunnel/

# O mejor, usar ansible vault para automatización
ansible-vault encrypt device_key
```

## Respuesta a Incidentes

### Procedimiento en Caso de Compromiso

1. **Aislar dispositivo**
   ```bash
   # Revocar acceso inmediatamente
   ./server/scripts/device_registry.sh deactivate <device_id>

   # Cerrar túnel
   ./server/scripts/tunnel_manager.sh close <device_id>
   ```

2. **Investigar**
   ```bash
   # Revisar logs
   grep <device_id> /var/log/iot-ssh-tunnel/*.log
   grep <device_ip> /var/log/auth.log
   ```

3. **Remediar**
   ```bash
   # Rotar todas las claves
   ./security/key_rotation.sh rotate <device_id> <key_path>

   # Actualizar firmware/software del dispositivo
   ```

4. **Restaurar**
   ```bash
   # Reactivar dispositivo con nuevas credenciales
   ./server/scripts/device_registry.sh reactivate <device_id>
   ```

### Backup y Recovery

```bash
# Backup completo del servidor
tar -czf backup-$(date +%Y%m%d).tar.gz \
    /opt/iot-ssh-reverse-tunnel/server/configs \
    /home/iot-tunnel/.ssh \
    /var/lib/iot-ssh-tunnel

# Backup cifrado
tar -czf - /path/to/backup | gpg -c > backup-$(date +%Y%m%d).tar.gz.gpg
```

## Checklist de Seguridad

### Servidor
- [ ] SSH configurado con claves únicamente
- [ ] Usuario dedicado con mínimos privilegios
- [ ] Firewall configurado y activo
- [ ] Rate limiting habilitado
- [ ] Logging verboso activado
- [ ] Fail2ban configurado
- [ ] Sistema actualizado
- [ ] Servicios innecesarios deshabilitados
- [ ] Backups configurados

### Dispositivos
- [ ] Claves únicas por dispositivo
- [ ] Permisos de archivos correctos
- [ ] Firewall básico activo
- [ ] Servicios innecesarios deshabilitados
- [ ] Acceso físico restringido
- [ ] Rotación de claves programada

### Operaciones
- [ ] Procedimientos de rotación de claves documentados
- [ ] Plan de respuesta a incidentes definido
- [ ] Monitoreo y alertas configurados
- [ ] Logs centralizados y retenidos
- [ ] Auditorías de seguridad periódicas programadas
- [ ] Personal capacitado en procedimientos de seguridad

## Referencias

- CIS Benchmarks for Debian/Ubuntu
- NIST SP 800-123 Guide to General Server Security
- OWASP IoT Security Guidance
- RFC 4253 SSH Transport Layer Protocol
- RFC 4252 SSH Authentication Protocol
