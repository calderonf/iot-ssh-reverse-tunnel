# Caso de Uso: IoT Industrial - Monitoreo de Maquinaria

## Escenario

Una empresa manufacturera necesita monitorear y mantener remotamente equipos IoT instalados en 50 plantas de producción distribuidas geográficamente. Cada planta tiene:

- 5-10 dispositivos de monitoreo (Raspberry Pi / dispositivos embebidos Linux)
- Conexión a Internet limitada detrás de NAT corporativo
- Necesidad de acceso remoto para diagnóstico y mantenimiento
- Requisitos de seguridad estrictos (no exponer puertos públicamente)

## Arquitectura de Solución

```
                    ┌──────────────────────┐
                    │  Servidor Central    │
                    │  (Cloud - AWS/Azure) │
                    │  IP: tunnel.corp.com │
                    └──────────┬───────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    ┌─────▼─────┐        ┌─────▼─────┐      ┌─────▼─────┐
    │ Planta 1  │        │ Planta 2  │      │ Planta N  │
    │ NAT       │        │ NAT       │      │ NAT       │
    └─────┬─────┘        └─────┬─────┘      └─────┬─────┘
          │                    │                    │
    ┌─────▼──────┐      ┌──────▼──────┐     ┌──────▼──────┐
    │ Raspberry  │      │ Raspberry   │     │ Raspberry   │
    │ Pi #1      │      │ Pi #6       │     │ Pi #X       │
    │ (Sensores) │      │ (Sensores)  │     │ (Sensores)  │
    └────────────┘      └─────────────┘     └─────────────┘
```

## Implementación

### Fase 1: Setup del Servidor Central

```bash
# Desplegar servidor en AWS (ver aws_security_group.md)
# t3.small instance, Ubuntu 22.04 LTS

# Configurar servidor
cd /opt
git clone https://github.com/your-org/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# Crear usuario dedicado
useradd -r -m -d /home/iot-tunnel -s /bin/bash iot-tunnel

# Copiar configuración SSH
cp server/configs/ssh_config /etc/ssh/sshd_config.d/iot-tunnel.conf
systemctl restart sshd

# Iniciar monitor
cp server/scripts/connection_monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/connection_monitor.sh
/usr/local/bin/connection_monitor.sh daemon 60 &
```

### Fase 2: Preparar Imagen de Dispositivo

```bash
# En un Raspberry Pi de referencia

# Instalar dependencias
apt-get update
apt-get install -y openssh-client autossh git

# Clonar repositorio
cd /opt
git clone https://github.com/your-org/iot-ssh-reverse-tunnel.git

# Configurar permisos
chmod +x /opt/iot-ssh-reverse-tunnel/client/scripts/*.sh
chmod +x /opt/iot-ssh-reverse-tunnel/security/*.sh

# Crear imagen dorada
# (Esta imagen se usará para todos los dispositivos)
```

### Fase 3: Deployment en Dispositivos

#### Script de Aprovisionamiento Automático

```bash
#!/bin/bash
# provision_device.sh - Script de aprovisionamiento para nuevos dispositivos

set -e

PLANT_ID=$1
DEVICE_NUM=$2
SERVER_HOST="tunnel.corp.com"

if [ -z "$PLANT_ID" ] || [ -z "$DEVICE_NUM" ]; then
    echo "Uso: $0 <plant_id> <device_num>"
    echo "Ejemplo: $0 plant001 01"
    exit 1
fi

echo "Aprovisionando dispositivo: ${PLANT_ID}-device${DEVICE_NUM}"

# Generar device ID único
cd /opt/iot-ssh-reverse-tunnel
DEVICE_ID=$(./client/scripts/device_identifier.sh get)

# Generar claves SSH
mkdir -p /etc/iot-ssh-tunnel
./security/keygen.sh generate \
    /etc/iot-ssh-tunnel/tunnel_key \
    ed25519 \
    "${PLANT_ID}-device${DEVICE_NUM}"

# Enviar clave pública al servidor para registro
# (En producción, usar API o proceso automatizado)
echo "Registre esta clave pública en el servidor:"
cat /etc/iot-ssh-tunnel/tunnel_key.pub

echo ""
echo "Device ID: ${DEVICE_ID}"
echo "Planta: ${PLANT_ID}"
echo "Dispositivo: device${DEVICE_NUM}"

# Esperar confirmación del puerto asignado
read -p "Ingrese el puerto asignado por el servidor: " TUNNEL_PORT

# Configurar túnel
./client/scripts/ssh_tunnel_setup.sh setup \
    ${SERVER_HOST} 22 iot-tunnel ${TUNNEL_PORT}

# Instalar servicio systemd
cp client/systemd/iot-ssh-tunnel.service /etc/systemd/system/
cp client/systemd/iot-tunnel-start.sh /usr/local/bin/
cp client/systemd/iot-tunnel-stop.sh /usr/local/bin/
chmod +x /usr/local/bin/iot-tunnel-*.sh

# Habilitar e iniciar servicio
systemctl daemon-reload
systemctl enable iot-ssh-tunnel
systemctl start iot-ssh-tunnel

# Etiquetar dispositivo
echo "${PLANT_ID}-device${DEVICE_NUM}" > /etc/iot-ssh-tunnel/device_label

echo "Aprovisionamiento completo!"
echo "Verificando conexión..."
sleep 5
systemctl status iot-ssh-tunnel
```

#### Ejecución en Campo

```bash
# En cada Raspberry Pi en la planta
sudo ./provision_device.sh plant001 01
sudo ./provision_device.sh plant001 02
# etc...
```

### Fase 4: Registro en Servidor

```bash
# En el servidor, para cada dispositivo

DEVICE_ID="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"  # Del output del dispositivo

# Registrar dispositivo
./server/scripts/device_registry.sh register \
    ${DEVICE_ID} \
    /tmp/${DEVICE_ID}.pub

# Output mostrará el puerto asignado
# Este puerto se debe comunicar al dispositivo
```

### Fase 5: Operación y Mantenimiento

#### Acceso a Dispositivo

```bash
# Desde el servidor central

# Listar todos los dispositivos
./server/scripts/tunnel_manager.sh list active

# Conectar a dispositivo en planta001-device01 (puerto 10001)
ssh -p 10001 localhost

# Una vez conectado, ejecutar comandos de diagnóstico
uptime
sensors
journalctl -u application -n 50
```

#### Dashboard de Monitoreo

```bash
# Ver estadísticas en tiempo real
watch -n 5 './server/scripts/tunnel_manager.sh stats'

# Generar reporte semanal
./server/scripts/connection_monitor.sh report 7
```

#### Actualización Masiva de Firmware

```bash
#!/bin/bash
# update_firmware.sh - Actualizar firmware en todos los dispositivos

FIRMWARE_FILE="/path/to/firmware.bin"

# Obtener lista de dispositivos activos
ACTIVE_PORTS=$(./server/scripts/tunnel_manager.sh list active | \
    grep -oP '(?<=PORT\s)\d+')

for PORT in $ACTIVE_PORTS; do
    echo "Actualizando dispositivo en puerto $PORT..."

    # Copiar firmware
    scp -P $PORT $FIRMWARE_FILE localhost:/tmp/firmware.bin

    # Ejecutar actualización
    ssh -p $PORT localhost "sudo /opt/update_firmware.sh /tmp/firmware.bin"

    # Verificar
    ssh -p $PORT localhost "cat /etc/firmware_version"

    echo "Dispositivo $PORT actualizado"
done
```

## Beneficios Implementados

### Seguridad

- No se exponen puertos en las plantas
- Autenticación fuerte con claves SSH únicas
- Tráfico completamente cifrado
- Auditoría completa de accesos

### Escalabilidad

- Soporte para 10,000 dispositivos (rango de puertos)
- Fácil adición de nuevas plantas
- Servidor centralizado escalable verticalmente

### Mantenimiento

- Acceso remoto 24/7
- Actualizaciones centralizadas
- Diagnóstico sin visita en sitio
- Reducción de costos operativos en 70%

### Confiabilidad

- Reconexión automática tras cortes de red
- Monitoreo continuo de conectividad
- Alertas proactivas de desconexiones
- Uptime > 99.5%

## Métricas del Deployment

**Después de 6 meses de operación:**

- **Dispositivos desplegados:** 487
- **Plantas cubiertas:** 52
- **Uptime promedio:** 99.7%
- **Tiempo de reconexión promedio:** 45 segundos
- **Visitas en sitio reducidas:** 85%
- **Ahorro anual estimado:** $120,000 USD

## Lecciones Aprendidas

### Desafíos

1. **Calidad de red variable:** Algunas plantas tienen conexiones inestables
   - **Solución:** Ajustar keep-alive a 15 segundos

2. **Gestión de credenciales:** Distribución inicial de claves SSH
   - **Solución:** Proceso de aprovisionamiento automatizado

3. **Identificación de dispositivos:** Rastrear device ID vs ubicación física
   - **Solución:** Sistema de etiquetado con plant_id-device_num

### Mejoras Futuras

- [ ] Dashboard web para visualización
- [ ] API REST para automatización
- [ ] Integración con sistema de monitoreo existente (Grafana/Prometheus)
- [ ] Alertas via email/SMS
- [ ] Gestión de credenciales con Vault

## Código de Ejemplo: Integración con Monitoring

```python
#!/usr/bin/env python3
# monitor_integration.py - Integrar con sistema de monitoring

import subprocess
import json
import requests

def get_tunnel_status():
    """Obtener estado de todos los túneles"""
    result = subprocess.run(
        ['./server/scripts/tunnel_manager.sh', 'export', '/tmp/status.json'],
        capture_output=True
    )

    with open('/tmp/status.json') as f:
        return json.load(f)

def send_to_prometheus(status):
    """Enviar métricas a Prometheus Pushgateway"""
    metrics = []

    for tunnel in status['tunnels']:
        metrics.append(
            f'iot_tunnel_status{{device_id="{tunnel["device_id"]}"}} {1 if tunnel["tunnel_status"] == "active" else 0}'
        )

    payload = '\n'.join(metrics)

    requests.post(
        'http://pushgateway:9091/metrics/job/iot_tunnels',
        data=payload
    )

if __name__ == '__main__':
    status = get_tunnel_status()
    send_to_prometheus(status)
```

## Conclusión

Este deployment demuestra cómo una solución de túneles SSH inversos puede resolver problemas reales de conectividad IoT industrial de forma:

- Segura
- Escalable
- Económica
- Confiable

Con un TCO (Total Cost of Ownership) significativamente menor que soluciones comerciales propietarias.
