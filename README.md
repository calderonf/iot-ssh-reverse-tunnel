# Sistema de Túneles SSH Inversos para Dispositivos IoT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)
[![Architecture](https://img.shields.io/badge/Architecture-ARM%20%7C%20x86-orange.svg)](README.md)

Sistema completo de conectividad remota para dispositivos IoT mediante túneles SSH inversos con autossh, diseñado para proporcionar acceso seguro y persistente a dispositivos ubicados detrás de NAT.

## Características Principales

- **Túneles SSH Inversos**: Conectividad desde dispositivos detrás de NAT sin configuración de router
- **Reconexión Automática**: Uso de autossh para mantener conexiones persistentes
- **Gestión Centralizada**: Sistema de registro y monitoreo de dispositivos
- **Identificación Única**: Device ID basado en machine-id para rastreo consistente
- **Alta Seguridad**: Autenticación por claves SSH, cifrado end-to-end, sin contraseñas
- **Escalable**: Soporte para miles de dispositivos simultáneos
- **Monitoreo Integrado**: Sistema de alertas y métricas de disponibilidad
- **Rotación de Claves**: Gestión automatizada de credenciales

## Arquitectura

```
                    Internet
                       │
                       │
             ┌─────────▼─────────┐
             │  Servidor Central │
             │  IP Pública       │
             │  Puertos: 10000+  │
             └─────────┬─────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼────┐    ┌────▼────┐   ┌────▼────┐
   │ Túnel   │    │ Túnel   │   │ Túnel   │
   │ 10001   │    │ 10002   │   │ 10003   │
   └────┬────┘    └────┬────┘   └────┬────┘
        │              │              │
   ┌────▼────┐    ┌────▼────┐   ┌────▼────┐
   │ NAT/FW  │    │ NAT/FW  │   │ NAT/FW  │
   └────┬────┘    └────┬────┘   └────┬────┘
        │              │              │
   ┌────▼────┐    ┌────▼────┐   ┌────▼────┐
   │  IoT    │    │  IoT    │   │  IoT    │
   │Device #1│    │Device #2│   │Device #3│
   └─────────┘    └─────────┘   └─────────┘
```

## Inicio Rápido

### Requisitos del Sistema

**Servidor:**
- Debian 11+ o Ubuntu 20.04+
- 2 vCPU, 4GB RAM mínimo
- OpenSSH Server 8.0+
- IP pública accesible

**Dispositivos IoT:**
- Linux embebido (Debian, Ubuntu, Yocto, etc.)
- 256MB RAM, 500MB disco disponible
- OpenSSH Client 7.0+
- Autossh (recomendado)

### Instalación del Servidor

```bash
# 1. Clonar repositorio
cd /opt
git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# 2. Crear usuario dedicado
sudo useradd -r -m -d /home/iot-tunnel -s /bin/bash iot-tunnel

# 3. Configurar SSH
sudo cp server/configs/ssh_config /etc/ssh/sshd_config.d/iot-tunnel.conf
sudo systemctl restart sshd

# 4. Establecer permisos
sudo chmod +x server/scripts/*.sh
sudo chmod +x security/*.sh
sudo mkdir -p /var/log/iot-ssh-tunnel
sudo chown iot-tunnel:iot-tunnel /var/log/iot-ssh-tunnel
```

### Instalación en Dispositivo IoT

```bash
# 1. Clonar repositorio
cd /opt
git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# 2. Generar Device ID
sudo ./client/scripts/device_identifier.sh get
# Guardar el output (ej: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6)

# 3. Generar claves SSH
sudo mkdir -p /etc/iot-ssh-tunnel
sudo ./security/keygen.sh generate /etc/iot-ssh-tunnel/tunnel_key ed25519

# 4. Mostrar clave pública para registro
sudo cat /etc/iot-ssh-tunnel/tunnel_key.pub
```

### Registrar Dispositivo

En el **servidor**:

```bash
# Guardar clave pública del dispositivo en archivo temporal
cat > /tmp/device_key.pub << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... iot-device-xxx
EOF

# Registrar dispositivo (usar el device_id del paso anterior)
sudo ./server/scripts/device_registry.sh register \
    a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6 \
    /tmp/device_key.pub

# El sistema asignará un puerto (ej: 10001)
```

### Configurar Túnel

En el **dispositivo**:

```bash
# Configurar túnel con el puerto asignado
sudo ./client/scripts/ssh_tunnel_setup.sh setup \
    tunnel.example.com 22 iot-tunnel 10001

# Probar conectividad
sudo ./client/scripts/ssh_tunnel_setup.sh test

# Instalar como servicio systemd
sudo cp client/systemd/iot-ssh-tunnel.service /etc/systemd/system/
sudo cp client/systemd/iot-tunnel-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/iot-tunnel-*.sh
sudo systemctl daemon-reload
sudo systemctl enable iot-ssh-tunnel
sudo systemctl start iot-ssh-tunnel
```

### Acceder al Dispositivo

En el **servidor**:

```bash
# Listar dispositivos conectados
./server/scripts/tunnel_manager.sh list active

# Conectar al dispositivo (usar puerto asignado)
ssh -p 10001 localhost
```

## Estructura del Proyecto

```
iot-ssh-reverse-tunnel/
├── docs/                      # Documentación técnica
│   ├── ARCHITECTURE.md        # Diseño de arquitectura
│   ├── DEPLOYMENT.md          # Guía de despliegue
│   ├── SECURITY_GUIDE.md      # Guía de seguridad
│   └── TROUBLESHOOTING.md     # Resolución de problemas
│
├── server/                    # Componentes del servidor
│   ├── scripts/
│   │   ├── device_registry.sh     # Registro de dispositivos
│   │   ├── tunnel_manager.sh      # Gestión de túneles
│   │   └── connection_monitor.sh  # Monitoreo de conexiones
│   └── configs/
│       ├── ssh_config             # Configuración SSH
│       └── device_mapping.example # Ejemplo de mapeo
│
├── client/                    # Componentes del cliente
│   ├── scripts/
│   │   ├── device_identifier.sh   # Identificación de dispositivo
│   │   ├── ssh_tunnel_setup.sh    # Configuración de túnel
│   │   └── auto_reconnect.sh      # Reconexión automática
│   └── systemd/
│       ├── iot-ssh-tunnel.service # Servicio systemd
│       ├── iot-tunnel-start.sh    # Script de inicio
│       └── iot-tunnel-stop.sh     # Script de detención
│
├── security/                  # Herramientas de seguridad
│   ├── keygen.sh              # Generación de claves SSH
│   └── key_rotation.sh        # Rotación de claves
│
└── examples/                  # Ejemplos y casos de uso
    ├── cloud_providers/       # Configuraciones de cloud
    │   ├── azure_firewall.md
    │   ├── aws_security_group.md
    │   └── gcp_network.md
    └── use_cases/            # Casos de uso reales
        └── industrial_iot.md
```

## Guías de Uso

### Scripts del Servidor

#### device_registry.sh
Gestión de registro de dispositivos.

```bash
# Registrar nuevo dispositivo
./device_registry.sh register <device_id> <public_key_file>

# Listar dispositivos
./device_registry.sh list [active|inactive|all]

# Ver información de dispositivo
./device_registry.sh info <device_id>

# Desactivar dispositivo
./device_registry.sh deactivate <device_id>

# Eliminar dispositivo
./device_registry.sh remove <device_id>
```

#### tunnel_manager.sh
Gestión y monitoreo de túneles activos.

```bash
# Listar túneles
./tunnel_manager.sh list [active|inactive|all]

# Ver estadísticas
./tunnel_manager.sh stats

# Verificar salud de túnel
./tunnel_manager.sh check <device_id>

# Cerrar túnel
./tunnel_manager.sh close <device_id>

# Exportar estado a JSON
./tunnel_manager.sh export /tmp/status.json
```

#### connection_monitor.sh
Monitoreo continuo de conexiones.

```bash
# Verificación única
./connection_monitor.sh check

# Modo daemon
./connection_monitor.sh daemon [interval_seconds]

# Detener daemon
./connection_monitor.sh stop

# Ver estado
./connection_monitor.sh status

# Generar reporte
./connection_monitor.sh report [days]
```

### Scripts del Cliente

#### device_identifier.sh
Gestión de identificación de dispositivo.

```bash
# Obtener device ID
./device_identifier.sh get

# Regenerar device ID
./device_identifier.sh regenerate

# Ver información del dispositivo
./device_identifier.sh info
```

#### ssh_tunnel_setup.sh
Configuración y gestión del túnel SSH.

```bash
# Configurar túnel
./ssh_tunnel_setup.sh setup <server> [port] [user] [tunnel_port]

# Iniciar túnel
./ssh_tunnel_setup.sh start

# Detener túnel
./ssh_tunnel_setup.sh stop

# Ver estado
./ssh_tunnel_setup.sh status

# Probar conectividad
./ssh_tunnel_setup.sh test
```

### Scripts de Seguridad

#### keygen.sh
Generación de claves SSH.

```bash
# Generar clave individual
./keygen.sh generate <output_path> [ed25519|rsa|ecdsa]

# Generación batch
./keygen.sh batch <output_dir> <count> [type] [prefix]

# Verificar clave
./keygen.sh verify <key_path>

# Formatear para authorized_keys
./keygen.sh format <public_key> [port] [restrictions]
```

#### key_rotation.sh
Rotación de claves SSH.

```bash
# Rotar clave individual
./key_rotation.sh rotate <device_id> <key_path> [type]

# Rotación batch
./key_rotation.sh batch <device_list_file> [type]

# Ver historial
./key_rotation.sh history [device_id]

# Verificar edad de clave
./key_rotation.sh check-age <key_path> [warning_days]
```

## Seguridad

### Mejores Prácticas

1. **Usar claves Ed25519** para nuevos deployments (más seguras y eficientes)
2. **Rotar claves cada 90 días** como mínimo
3. **Aplicar restricciones** en authorized_keys (no-pty, no-agent-forwarding)
4. **Monitorear logs** de autenticación y conexiones
5. **Usar firewall** para limitar acceso SSH a IPs conocidas
6. **Habilitar fail2ban** para prevenir brute force
7. **Mantener sistema actualizado** con parches de seguridad

### Configuración de Firewall

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 22/tcp
sudo ufw enable

# iptables
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

Ver [SECURITY_GUIDE.md](docs/SECURITY_GUIDE.md) para detalles completos.

## Deployment en Cloud

Guías específicas para proveedores de cloud:

- [**AWS**](examples/cloud_providers/aws_security_group.md) - EC2 con Security Groups
- [**Azure**](examples/cloud_providers/azure_firewall.md) - VM con Network Security Groups
- [**GCP**](examples/cloud_providers/gcp_network.md) - Compute Engine con Firewall Rules

## Casos de Uso

### IoT Industrial

Sistema de monitoreo remoto para maquinaria industrial distribuida en múltiples plantas.

[Ver caso de uso completo](examples/use_cases/industrial_iot.md)

**Resultados:**
- 487 dispositivos desplegados
- 99.7% uptime
- 85% reducción en visitas en sitio
- $120,000 USD ahorro anual

## Troubleshooting

### Problemas Comunes

**El túnel no se establece:**
```bash
# Verificar conectividad
ping server.example.com
telnet server.example.com 22

# Ver logs
journalctl -u iot-ssh-tunnel -n 50

# Probar SSH manualmente con verbose
ssh -vvv -i /etc/iot-ssh-tunnel/tunnel_key iot-tunnel@server.example.com
```

**Túnel se desconecta frecuentemente:**
```bash
# Ajustar keep-alive en tunnel.conf
SSH_OPTIONS="-o ServerAliveInterval=15 -o ServerAliveCountMax=5"

# Reiniciar servicio
systemctl restart iot-ssh-tunnel
```

Ver [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) para guía completa.

## Monitoreo y Métricas

### Dashboard de Estado

```bash
# Ver estadísticas en tiempo real
watch -n 5 './server/scripts/tunnel_manager.sh stats'

# Exportar métricas para Prometheus
./server/scripts/tunnel_manager.sh export /var/lib/prometheus/iot_tunnels.json
```

### Alertas

El sistema de monitoreo genera alertas automáticas para:
- Dispositivos desconectados por más de 5 minutos
- Fallos repetidos de reconexión
- Cambios en fingerprints de claves SSH

## Rendimiento y Escalabilidad

### Límites

- **Dispositivos simultáneos**: ~10,000 (basado en rango de puertos)
- **Conexiones concurrentes**: Limitado por configuración de SSH server
- **Recursos recomendados**: 2 vCPU + 4GB RAM por cada 1000 dispositivos

### Optimización

```bash
# En /etc/ssh/sshd_config
MaxSessions 1000
MaxStartups 100:30:200
ClientAliveInterval 30
```

## Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crear branch de feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -m 'Agregar nueva funcionalidad'`)
4. Push al branch (`git push origin feature/nueva-funcionalidad`)
5. Abrir Pull Request

## Licencia

Este proyecto está licenciado bajo la Licencia MIT. Ver archivo [LICENSE](LICENSE) para detalles.

## Soporte

Para preguntas, problemas o sugerencias:

- **Issues**: [GitHub Issues](https://github.com/your-org/iot-ssh-reverse-tunnel/issues)
- **Documentación**: [docs/](docs/)
- **Ejemplos**: [examples/](examples/)

## Agradecimientos

- Proyecto basado en SSH y autossh
- Inspirado en mejores prácticas de seguridad de NIST y CIS
- Contribuciones de la comunidad IoT

## Roadmap

- [ ] Dashboard web para gestión visual
- [ ] API REST para automatización
- [ ] Integración nativa con Prometheus/Grafana
- [ ] Soporte para múltiples servidores (HA)
- [ ] Cliente Docker para despliegues containerizados
- [ ] Gestión de secretos con HashiCorp Vault

---

Desarrollado con fines educativos y de investigación para la Pontificia Universidad Javeriana.
