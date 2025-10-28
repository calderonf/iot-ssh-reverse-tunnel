# Sistema de Túneles SSH Inversos para Dispositivos IoT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)
[![Architecture](https://img.shields.io/badge/Architecture-ARM%20%7C%20x86-orange.svg)](README.md)

Solución completa y segura para acceso remoto a dispositivos IoT mediante túneles SSH inversos. Permite gestionar y acceder a dispositivos detrás de NAT/firewall de forma simple y segura.

---

## ⚠️ ADVERTENCIA CRÍTICA - Bug de OpenSSH `PermitListen`

**PROBLEMA:** OpenSSH tiene un bug conocido donde múltiples directivas `PermitListen` dentro de un bloque `Match` solo aplican la **primera línea**.

**SÍNTOMA:** Los dispositivos fallan con error: `remote port forwarding failed for listen port XXXXX`

**SOLUCIÓN:** Usar **UNA SOLA LÍNEA** con todos los puertos:

```bash
# ❌ INCORRECTO - Solo funciona el puerto 10000
Match User iot-tunnel
    PermitListen 10000
    PermitListen 10001
    PermitListen 10002

# ✅ CORRECTO - Funcionan todos los puertos
Match User iot-tunnel
    PermitListen localhost:10000 localhost:10001 localhost:10002 localhost:10003
```

**Verificar:** `sudo sshd -T -C user=iot-tunnel | grep permitlisten` debe mostrar **todos** los puertos.

📖 Ver [DEPLOYMENT.md - Troubleshooting](docs/DEPLOYMENT.md#error-remote-port-forwarding-failed-for-listen-port) para más detalles.

---

## 🚀 Inicio Rápido

### ¿Primera vez usando el sistema?

1. **Configura el servidor** (una sola vez) → [Guía Rápida de Servidor](docs/FAST_DEPLOYMENT.md#parte-1-configuración-del-servidor-una-sola-vez)
2. **Agrega dispositivos** (repetir por cada uno) → [Guía Rápida de Dispositivos](docs/FAST_DEPLOYMENT.md#parte-2-agregar-dispositivos-iot-repetir-por-cada-dispositivo)
3. **Accede a tus dispositivos** → [Acceso con tunnel_manager](docs/FAST_DEPLOYMENT.md#acceder-a-los-dispositivos)

**Tiempo estimado:** 15 minutos para el primer dispositivo.

```bash
# En el dispositivo IoT
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh

# En el servidor (después)
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login <device_id>
```

---

## 📖 Documentación

### Para Nuevos Usuarios

| Documento | Descripción | Cuándo usar |
|-----------|-------------|-------------|
| **[FAST_DEPLOYMENT.md](docs/FAST_DEPLOYMENT.md)** | Guía rápida de configuración | Primera instalación, agregar dispositivos rápidamente |
| **[client/scripts/README.md](client/scripts/README.md)** | Documentación de scripts del cliente | Entender setup_client.sh y otros scripts |

### Documentación Detallada

| Documento | Descripción | Cuándo usar |
|-----------|-------------|-------------|
| **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** | Guía completa de despliegue | Configuración avanzada, opciones detalladas |
| **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Arquitectura del sistema | Entender cómo funciona internamente |
| **[SECURITY.md](docs/SECURITY.md)** | Guía de seguridad | Hardening, mejores prácticas de seguridad |

---

## ✨ Características Principales

### 🔐 Seguridad

- ✅ Autenticación basada en claves SSH (ed25519)
- ✅ Usuario dedicado con permisos restringidos
- ✅ Configuración SSH endurecida
- ✅ Puertos autorizados explícitamente
- ✅ Aislamiento de túneles por dispositivo

### 🎯 Facilidad de Uso

- ✅ **Script de configuración automática** para clientes
- ✅ **Comando `login` simplificado** - acceso con solo 5 caracteres del Device ID
- ✅ **Configuración automática de claves SSH** - sin contraseñas después del primer acceso
- ✅ **Gestión centralizada** desde el servidor
- ✅ **Monitoreo en tiempo real** del estado de túneles

### 🛠️ Gestión y Monitoreo

- ✅ Registro automático de dispositivos
- ✅ Asignación dinámica de puertos
- ✅ Estadísticas y reportes de conexión
- ✅ Logs detallados
- ✅ Servicio systemd para inicio automático
- ✅ Reconexión automática con autossh

---

## 🎯 Flujo de Trabajo Típico

### 1️⃣ Configuración Inicial del Servidor (Una sola vez)

```bash
# Instalar sistema
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel
sudo chmod +x server/scripts/*.sh security/*.sh

# Configurar SSH, crear usuario iot-tunnel, etc.
# Ver: docs/FAST_DEPLOYMENT.md - Parte 1
```

### 2️⃣ Agregar un Dispositivo IoT

```bash
# En el dispositivo
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel
sudo chmod +x client/scripts/*.sh

# Configuración automática interactiva
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh

# El script te guiará paso a paso:
# - Generará Device ID único
# - Creará claves SSH
# - Mostrará info para registrar en el servidor
# - Esperará que registres el dispositivo
# - Configurará el túnel y servicio systemd
```

### 3️⃣ Acceder al Dispositivo

```bash
# Desde el servidor
# Primera vez: configura claves SSH automáticamente
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46 usuario password

# Siguientes veces: acceso directo sin contraseña
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46
```

---

## 📊 Estructura del Repositorio

```
iot-ssh-reverse-tunnel/
├── server/                      # Componentes del servidor
│   ├── configs/
│   │   ├── sshd_config.d/      # Configuración SSH endurecida
│   │   ├── device_mapping      # Registro de dispositivos
│   │   └── device_credentials  # Credenciales guardadas (no versionado)
│   └── scripts/
│       ├── device_registry.sh  # Registro de dispositivos
│       ├── tunnel_manager.sh   # Gestión de túneles y login
│       └── connection_monitor.sh # Monitoreo de conexiones
│
├── client/                      # Componentes del cliente (dispositivos IoT)
│   ├── scripts/
│   │   ├── setup_client.sh     # 🌟 Configuración automática
│   │   ├── device_identifier.sh # Generación de Device ID
│   │   ├── ssh_tunnel_setup.sh # Configuración de túnel
│   │   └── README.md           # Documentación de scripts
│   └── systemd/                # Archivos de servicio systemd
│       ├── iot-ssh-tunnel.service
│       ├── iot-tunnel-start.sh
│       └── iot-tunnel-stop.sh
│
├── security/                    # Utilidades de seguridad
│   ├── keygen.sh               # Generación de claves
│   └── key_rotation.sh         # Rotación de claves
│
└── docs/                        # Documentación
    ├── FAST_DEPLOYMENT.md      # 🌟 Guía rápida (15 min)
    ├── DEPLOYMENT.md           # Guía detallada completa
    ├── ARCHITECTURE.md         # Arquitectura del sistema
    └── SECURITY.md             # Guía de seguridad
```

---

## 🔧 Comandos Principales

### En el Servidor

```bash
# Registrar dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/device_registry.sh register <device_id> <public_key_file>

# Listar túneles activos
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh list active

# Estadísticas
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh stats

# Acceder a dispositivo (método simple)
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login <prefix>

# Diagnosticar dispositivo
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh diagnose <prefix> <user> <pass>

# Monitoreo en tiempo real
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh monitor
```

### En el Dispositivo IoT

```bash
# Configuración automática (recomendado)
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh

# Estado del servicio
sudo systemctl status iot-ssh-tunnel

# Logs en tiempo real
sudo journalctl -u iot-ssh-tunnel -f

# Verificar túnel
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh status
```

---

## 💡 Casos de Uso

- **🏭 IoT Industrial**: Acceso remoto a dispositivos en plantas industriales
- **🏠 Smart Home**: Gestión de dispositivos domóticos
- **🌾 Agricultura**: Monitoreo de sensores agrícolas remotos
- **🔬 Laboratorios**: Control de equipos de investigación
- **📡 Telemetría**: Dispositivos de recolección de datos en campo
- **🎓 Educación**: Laboratorios remotos para estudiantes

---

## 🚨 Solución Rápida de Problemas

### El túnel no se conecta

```bash
# En el dispositivo
sudo journalctl -u iot-ssh-tunnel -n 50

# En el servidor
sudo tail -f /var/log/auth.log | grep iot-tunnel
```

### No puedo hacer login al dispositivo

```bash
# Diagnosticar
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh diagnose 18e46 user pass

# Borrar credenciales y reintentar
sudo rm /opt/iot-ssh-reverse-tunnel/server/configs/device_credentials
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login 18e46 user pass
```

**Ver más:** [Troubleshooting Completo](docs/DEPLOYMENT.md#troubleshooting)

---

## 🎓 Guía de Aprendizaje

### Para Principiantes

1. Lee el [FAST_DEPLOYMENT.md](docs/FAST_DEPLOYMENT.md)
2. Configura un servidor de prueba
3. Agrega tu primer dispositivo usando `setup_client.sh`
4. Practica con los comandos de `tunnel_manager.sh`

### Para Usuarios Avanzados

1. Revisa la [Arquitectura](docs/ARCHITECTURE.md)
2. Estudia las opciones avanzadas en [DEPLOYMENT.md](docs/DEPLOYMENT.md)
3. Implementa configuraciones personalizadas de seguridad con [SECURITY.md](docs/SECURITY.md)
4. Considera el deployment masivo (ver sección en DEPLOYMENT.md)

---

## 📈 Ventajas sobre Soluciones Alternativas

| Característica | Este Sistema | VPN tradicional | Cloud IoT Hub |
|----------------|--------------|-----------------|---------------|
| **Configuración** | Muy simple (script automático) | Compleja | Depende del proveedor |
| **Costo** | Gratis (self-hosted) | Variable | Por dispositivo/mensual |
| **Latencia** | Baja (directo) | Media-Alta | Media |
| **Seguridad** | Alta (SSH + hardening) | Alta | Alta |
| **Escalabilidad** | Cientos de dispositivos | Miles | Ilimitada |
| **Control** | Total | Total | Limitado |
| **NAT Traversal** | ✅ Automático | ⚠️ Requiere config | ✅ Automático |

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas!

- **Issues**: [GitHub Issues](https://github.com/calderonf/iot-ssh-reverse-tunnel/issues)
- **Pull Requests**: Revisa el código antes de enviar
- **Documentación**: Mejoras siempre son útiles
- **Ejemplos**: Comparte tus casos de uso

---

## 📝 Licencia

Este proyecto está licenciado bajo la Licencia MIT. Consulta [LICENSE](LICENSE) para más detalles.

---

## 🎓 Proyecto Académico

Desarrollado en la **Pontificia Universidad Javeriana** como parte de investigación en:
- Seguridad en IoT
- Infraestructura de acceso remoto
- Hardening de sistemas Linux
- Arquitecturas distribuidas

---

## 📞 Soporte

- 📖 **Documentación**: [docs/](docs/)
- 🐛 **Reportar bugs**: [GitHub Issues](https://github.com/calderonf/iot-ssh-reverse-tunnel/issues)
- 💬 **Preguntas**: Usa GitHub Discussions
- 📧 **Contacto**: [Tu email/universidad]

---

**¡Empieza ahora!** → [Guía Rápida de 15 minutos](docs/FAST_DEPLOYMENT.md)
