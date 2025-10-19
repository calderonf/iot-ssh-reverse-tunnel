# Scripts del Cliente IoT

Este directorio contiene los scripts para configurar y gestionar el túnel SSH inverso en dispositivos IoT.

## Script de Configuración Automática

### setup_client.sh

Script interactivo que automatiza completamente la configuración del cliente IoT.

**Uso:**

```bash
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh
```

**Qué hace:**

1. ✅ Verifica dependencias del sistema
2. ✅ Solicita información del servidor (IP, puerto, usuario)
3. ✅ Genera automáticamente el Device ID único
4. ✅ Crea claves SSH ed25519
5. ✅ Muestra la información para registrar en el servidor
6. ✅ Espera confirmación del registro
7. ✅ Configura el túnel SSH
8. ✅ Instala el servicio systemd
9. ✅ Habilita e inicia el servicio
10. ✅ Muestra instrucciones de verificación

**Requisitos previos:**

- Sistema operativo Linux
- Privilegios de root (`sudo`)
- Paquetes instalados: `openssh-client`, `autossh`, `git`, `systemd`

**Ejemplo de uso:**

```bash
# Instalación de dependencias
sudo apt-get update
sudo apt-get install -y openssh-client autossh git

# Clonar repositorio
cd /opt
sudo git clone https://github.com/calderonf/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel
sudo chmod +x client/scripts/*.sh

# Ejecutar configuración automática
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/setup_client.sh
```

El script te guiará paso a paso con prompts interactivos y mensajes coloridos.

---

## Otros Scripts

### device_identifier.sh

Genera un identificador único basado en características del hardware del dispositivo.

**Uso:**

```bash
# Generar Device ID
sudo ./device_identifier.sh get

# Con semilla personalizada
sudo ./device_identifier.sh get "mi-semilla-personalizada"
```

### ssh_tunnel_setup.sh

Configura y gestiona el túnel SSH inverso (usado internamente por `setup_client.sh`).

**Uso:**

```bash
# Configurar túnel
sudo ./ssh_tunnel_setup.sh setup <servidor> <puerto_ssh> <usuario> <puerto_tunel>

# Verificar estado
sudo ./ssh_tunnel_setup.sh status

# Probar conectividad
sudo ./ssh_tunnel_setup.sh test

# Detener túnel
sudo ./ssh_tunnel_setup.sh stop
```

---

## Flujo de Trabajo Recomendado

### Para nuevos dispositivos:

1. **Usa `setup_client.sh`** - Es la forma más rápida y segura
2. Sigue las instrucciones en pantalla
3. Registra el dispositivo en el servidor cuando se te indique
4. Verifica la conexión

### Para diagnóstico:

```bash
# Ver estado del servicio
sudo systemctl status iot-ssh-tunnel

# Ver logs
sudo journalctl -u iot-ssh-tunnel -f

# Verificar túnel
sudo /opt/iot-ssh-reverse-tunnel/client/scripts/ssh_tunnel_setup.sh status
```

---

## Solución de Problemas

### El script setup_client.sh falla

Verifica que tengas todas las dependencias:

```bash
# Verificar dependencias
command -v ssh && echo "SSH: OK" || echo "SSH: FALTA"
command -v autossh && echo "AutoSSH: OK" || echo "AutoSSH: FALTA"
command -v systemctl && echo "Systemd: OK" || echo "Systemd: FALTA"
```

### El servicio no inicia

```bash
# Ver logs detallados
sudo journalctl -u iot-ssh-tunnel -n 50 --no-pager

# Verificar archivos de configuración
ls -la /etc/iot-ssh-tunnel/
cat /etc/iot-ssh-tunnel/tunnel.conf
```

### No puedo conectarme desde el servidor

```bash
# En el dispositivo - verificar que el túnel está activo
sudo systemctl status iot-ssh-tunnel

# En el servidor - verificar que el puerto está escuchando
sudo ss -tlnp | grep <puerto_asignado>

# En el servidor - conectarse
sudo /opt/iot-ssh-reverse-tunnel/server/scripts/tunnel_manager.sh login <device_id>
```

---

## Documentación Completa

Para más información, consulta la [Guía de Despliegue](../../docs/DEPLOYMENT.md).
