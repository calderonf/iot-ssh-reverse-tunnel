# Guía de Resolución de Problemas

## Tabla de Contenidos

1. [Problemas Comunes](#problemas-comunes)
2. [Diagnóstico Paso a Paso](#diagnóstico-paso-a-paso)
3. [Herramientas de Debugging](#herramientas-de-debugging)
4. [Problemas Específicos](#problemas-específicos)

## Problemas Comunes

### 1. El Túnel No Se Establece

**Síntomas:**
- El servicio se inicia pero no se puede conectar
- Error "Connection refused"
- Timeout al intentar conectar

**Diagnóstico:**

```bash
# En el dispositivo: verificar estado del servicio
systemctl status autossh-iot-tunnel || systemctl status iot-ssh-tunnel

# Verificar logs
journalctl -u autossh-iot-tunnel -n 50 || journalctl -u iot-ssh-tunnel -n 50

# Probar conexión SSH manualmente
ssh -v -i /etc/iot-ssh-tunnel/tunnel_key \
    -p 22 iot-tunnel@server.example.com

# Verificar conectividad de red
ping server.example.com
telnet server.example.com 22
```

**Soluciones:**

1. **Verificar configuración:**
   ```bash
   # Revisar parámetros del servicio instalado
   systemctl cat autossh-iot-tunnel.service 2>/dev/null
   systemctl cat iot-ssh-tunnel.service 2>/dev/null
   ```

2. **Verificar clave SSH:**
   ```bash
   # Permisos correctos
   ls -la /etc/iot-ssh-tunnel/tunnel_key
   # Debe ser 600

   # Clave válida
   ssh-keygen -l -f /etc/iot-ssh-tunnel/tunnel_key
   ```

3. **Verificar que la clave está registrada en servidor:**
   ```bash
   # En el servidor
   grep "$(ssh-keygen -lf /path/to/device_key.pub | awk '{print $2}')" \
       /home/iot-tunnel/.ssh/authorized_keys
   ```

4. **Verificar firewall:**
   ```bash
   # En el servidor
   ufw status
   iptables -L -n | grep 22
   ```

### 2. El Túnel Se Desconecta Frecuentemente

**Síntomas:**
- Conexión se cae cada pocos minutos
- Logs muestran reconexiones constantes
- Timeout errors

**Diagnóstico:**

```bash
# Ver logs de reconexión
grep "reconnect" /var/log/iot-ssh-tunnel/*.log

# Verificar calidad de red
ping -c 100 server.example.com | grep loss

# Monitorear conexiones
watch -n 5 'ss -tn | grep :22'
```

**Soluciones:**

1. **Ajustar keep-alive:**
   ```bash
   # En el script o servicio de autossh, ajusta los parámetros
   -o "ServerAliveInterval=15" -o "ServerAliveCountMax=5"
   ```

2. **Verificar MTU:**
   ```bash
   # Encontrar MTU óptimo
   ping -M do -s 1472 server.example.com

   # Ajustar si es necesario
   ip link set dev eth0 mtu 1400
   ```

3. **Verificar NAT timeout:**
   - Algunos routers NAT tienen timeouts cortos
   - Reduce ServerAliveInterval a 15-20 segundos

### 3. No Se Puede Conectar al Dispositivo a Través del Túnel

**Síntomas:**
- El túnel está activo pero no se puede SSH al puerto
- "Connection refused" al intentar `ssh -p PORT localhost`

**Diagnóstico:**

```bash
# En el servidor: verificar que el puerto está escuchando
ss -tln | grep :10001

# Verificar proceso SSH
ps aux | grep ssh | grep 10001

# Ver logs del servidor SSH
tail -f /var/log/auth.log
```

**Soluciones:**

1. **Verificar configuración del túnel:**
   ```bash
   # El comando debe exponer explícitamente la IP remota autorizada
   ssh -R 0.0.0.0:REMOTE_PORT:127.0.0.1:22 user@server
   ```

2. **Verificar GatewayPorts:**
   ```bash
   # En servidor /etc/ssh/sshd_config.d/iot-tunnel.conf
   # Debe estar presente dentro del bloque Match
   GatewayPorts clientspecified
   ```

3. **Verificar restricciones de PermitListen:**
   ```bash
   # En authorized_keys el puerto autorizado debe coincidir
   permitlisten="0.0.0.0:10001"
   ```

### 4. Servicio No Inicia Automáticamente

**Síntomas:**
- Después de reiniciar, el túnel no se establece
- Servicio muestra "failed" o "inactive"

**Diagnóstico:**

```bash
# Verificar estado del servicio
systemctl status iot-ssh-tunnel

# Ver dependencias
systemctl list-dependencies iot-ssh-tunnel

# Verificar habilitación
systemctl is-enabled iot-ssh-tunnel
```

**Soluciones:**

1. **Habilitar servicio:**
   ```bash
   systemctl enable iot-ssh-tunnel
   ```

2. **Verificar dependencias:**
   ```bash
   # En iot-ssh-tunnel.service
   [Unit]
   After=network-online.target
   Wants=network-online.target
   ```

3. **Verificar scripts de inicio:**
   ```bash
   # Permisos de ejecución
   ls -la /usr/local/bin/iot-tunnel-start.sh
   chmod +x /usr/local/bin/iot-tunnel-start.sh
   ```

### 5. Errores de Permisos

**Síntomas:**
- "Permission denied (publickey)"
- "Bad ownership or modes"

**Diagnóstico:**

```bash
# Verificar permisos de archivos
ls -la /etc/iot-ssh-tunnel/
ls -la /home/iot-tunnel/.ssh/

# Verificar en logs
grep "Bad ownership" /var/log/auth.log
```

**Soluciones:**

1. **Corregir permisos en dispositivo:**
   ```bash
   chmod 700 /etc/iot-ssh-tunnel
   chmod 600 /etc/iot-ssh-tunnel/tunnel_key
   chmod 644 /etc/iot-ssh-tunnel/tunnel_key.pub
   ```

2. **Corregir permisos en servidor:**
   ```bash
   chown -R iot-tunnel:iot-tunnel /home/iot-tunnel
   chmod 700 /home/iot-tunnel/.ssh
   chmod 600 /home/iot-tunnel/.ssh/authorized_keys
   ```

## Diagnóstico Paso a Paso

### Verificación Completa del Sistema

```bash
#!/bin/bash
# diagnostic.sh - Script de diagnóstico completo

echo "=== Diagnóstico de Túnel SSH IoT ==="
echo ""

echo "1. Verificando conectividad de red..."
if ping -c 3 server.example.com &>/dev/null; then
    echo "   [OK] Conectividad de red"
else
    echo "   [FAIL] Sin conectividad de red"
    exit 1
fi

echo "2. Verificando puerto SSH del servidor..."
if nc -zv server.example.com 22 &>/dev/null; then
    echo "   [OK] Puerto SSH accesible"
else
    echo "   [FAIL] Puerto SSH no accesible"
    exit 1
fi

echo "3. Verificando configuración local..."
if [ -f /etc/iot-ssh-tunnel/tunnel.conf ]; then
    echo "   [OK] Archivo de configuración existe"
    source /etc/iot-ssh-tunnel/tunnel.conf
else
    echo "   [FAIL] Archivo de configuración no encontrado"
    exit 1
fi

echo "4. Verificando clave SSH..."
if [ -f /etc/iot-ssh-tunnel/tunnel_key ]; then
    echo "   [OK] Clave privada existe"
    if ssh-keygen -l -f /etc/iot-ssh-tunnel/tunnel_key &>/dev/null; then
        echo "   [OK] Clave válida"
    else
        echo "   [FAIL] Clave corrupta"
        exit 1
    fi
else
    echo "   [FAIL] Clave privada no encontrada"
    exit 1
fi

echo "5. Verificando permisos..."
PERMS=$(stat -c %a /etc/iot-ssh-tunnel/tunnel_key)
if [ "$PERMS" = "600" ]; then
    echo "   [OK] Permisos correctos"
else
    echo "   [WARN] Permisos incorrectos: $PERMS (debe ser 600)"
fi

echo "6. Verificando servicio..."
if systemctl is-active iot-ssh-tunnel &>/dev/null; then
    echo "   [OK] Servicio activo"
else
    echo "   [FAIL] Servicio inactivo"
fi

echo "7. Probando autenticación SSH..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i /etc/iot-ssh-tunnel/tunnel_key \
    ${SERVER_USER}@${SERVER_HOST} "echo OK" &>/dev/null; then
    echo "   [OK] Autenticación exitosa"
else
    echo "   [FAIL] Autenticación fallida"
fi

echo ""
echo "Diagnóstico completo"
```

## Herramientas de Debugging

### SSH Verbose Mode

```bash
# Nivel 1 (básico)
ssh -v ...

# Nivel 2 (más detalle)
ssh -vv ...

# Nivel 3 (máximo detalle)
ssh -vvv -i /etc/iot-ssh-tunnel/tunnel_key \
    -R 10001:localhost:22 \
    iot-tunnel@server.example.com
```

### Monitoreo de Conexiones

```bash
# Ver todas las conexiones SSH activas
ss -tnp | grep :22

# Ver procesos SSH
ps aux | grep ssh

# Ver túneles específicos
lsof -i :10001

# Monitoreo continuo
watch -n 2 'ss -tn | grep -E ":(22|10001)"'
```

### Análisis de Logs

```bash
# Logs del servicio
journalctl -u iot-ssh-tunnel -f

# Logs de autenticación SSH
tail -f /var/log/auth.log

# Filtrar por usuario
grep "iot-tunnel" /var/log/auth.log

# Buscar errores
grep -i "error\|fail\|denied" /var/log/iot-ssh-tunnel/*.log
```

### Network Debugging

```bash
# Verificar ruta de red
traceroute server.example.com

# Test de ancho de banda
iperf3 -c server.example.com

# Captura de paquetes SSH
tcpdump -i any -n port 22 -w ssh_debug.pcap

# Ver paquetes en tiempo real
tcpdump -i any -n port 22 -A
```

## Problemas Específicos

### Error: "Host key verification failed"

**Causa:** Clave del servidor cambió o no está en known_hosts

**Solución:**
```bash
# Aceptar nueva clave
ssh-keyscan server.example.com >> /etc/iot-ssh-tunnel/known_hosts

# O eliminar entrada antigua
ssh-keygen -R server.example.com
```

### Error: "Too many authentication failures"

**Causa:** SSH prueba múltiples claves antes de la correcta

**Solución:**
```bash
# Especificar clave explícitamente
ssh -o IdentitiesOnly=yes -i /etc/iot-ssh-tunnel/tunnel_key ...

# O deshabilitar otras claves en config
IdentitiesOnly yes
IdentityFile /etc/iot-ssh-tunnel/tunnel_key
```

### Error: "Address already in use"

**Causa:** El puerto del túnel ya está en uso

**Solución en servidor:**
```bash
# Encontrar proceso usando el puerto
lsof -i :10001

# Matar proceso
kill <PID>

# O usar puerto diferente
./server/scripts/device_registry.sh ...
```

### Autossh No Reconecta

**Síntomas:** Autossh no reestablece conexión tras fallo

**Solución:**
```bash
# Verificar variables de entorno
export AUTOSSH_GATETIME=0
export AUTOSSH_PORT=0

# Verificar que autossh está instalado
which autossh

# Ver proceso autossh
ps aux | grep autossh

# Logs de autossh
export AUTOSSH_DEBUG=1
autossh ...
```

### Logs Muestran "Broken pipe"

**Causa:** Conexión interrumpida por timeout o NAT

**Solución:**
```bash
# Reducir keep-alive interval
SSH_OPTIONS="-o ServerAliveInterval=15 -o ServerAliveCountMax=5"

# En servidor, ajustar ClientAlive
ClientAliveInterval 15
ClientAliveCountMax 5
```

### Memory o CPU Alto

**Síntomas:** Uso excesivo de recursos

**Diagnóstico:**
```bash
# Ver uso de recursos por proceso
top -p $(pgrep -f ssh-tunnel)

# Estadísticas de sistema
vmstat 1
iostat 1

# Ver conexiones
netstat -an | grep ESTABLISHED | wc -l
```

**Solución:**
```bash
# Limitar recursos con systemd
# En iot-ssh-tunnel.service:
[Service]
MemoryLimit=256M
CPUQuota=25%

# Reiniciar servicio
systemctl daemon-reload
systemctl restart iot-ssh-tunnel
```

## Comandos Útiles de Referencia

```bash
# Estado completo del sistema
systemctl status iot-ssh-tunnel
journalctl -u iot-ssh-tunnel -n 100
ss -tln | grep -E ":(22|10[0-9]{3})"
ps aux | grep ssh

# En servidor
./server/scripts/tunnel_manager.sh list active
./server/scripts/tunnel_manager.sh stats
./server/scripts/connection_monitor.sh status

# Reinicio completo
systemctl restart iot-ssh-tunnel

# Reiniciar servicio SSH según distribución
# Debian / Ubuntu
sudo systemctl restart ssh

# RHEL / CentOS / Amazon Linux
sudo systemctl restart sshd

# Verificación de configuración
sshd -t  # Servidor
ssh -G server.example.com  # Cliente

# Logs en vivo
tail -f /var/log/iot-ssh-tunnel/*.log
tail -f /var/log/auth.log
journalctl -f -u iot-ssh-tunnel
```

## Obtener Ayuda

Si los problemas persisten:

1. Recopilar información de diagnóstico
2. Revisar logs completos
3. Documentar pasos de reproducción
4. Abrir issue en GitHub con toda la información

**Información a incluir:**
- Versión del SO (cliente y servidor)
- Versión de OpenSSH
- Logs relevantes
- Configuraciones (sanitizadas)
- Pasos para reproducir el problema
