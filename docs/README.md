# Documentación del Sistema de Túneles SSH Inversos

Bienvenido a la documentación del sistema. Esta guía te ayudará a navegar por todos los documentos disponibles.

---

## 🗺️ Mapa de Documentación

### Para Empezar

| Documento | Audiencia | Tiempo | Descripción |
|-----------|-----------|--------|-------------|
| **[FAST_DEPLOYMENT.md](FAST_DEPLOYMENT.md)** | Principiantes | 15 min | Guía rápida para configuración servidor + clientes |
| **[../client/scripts/README.md](../client/scripts/README.md)** | Usuarios del cliente | 5 min | Documentación de scripts de configuración automática |

### Guías Completas

| Documento | Audiencia | Descripción |
|-----------|-----------|-------------|
| **[DEPLOYMENT.md](DEPLOYMENT.md)** | Todos | Guía completa de despliegue con opciones avanzadas |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Desarrolladores | Arquitectura del sistema y componentes |
| **[SECURITY.md](SECURITY.md)** | Administradores | Guía de seguridad y hardening |

---

## 🎯 ¿Qué guía necesito?

### "Quiero configurar el sistema por primera vez"
→ **[FAST_DEPLOYMENT.md](FAST_DEPLOYMENT.md)**

### "Necesito configurar un dispositivo IoT rápidamente"
→ **[FAST_DEPLOYMENT.md - Parte 2](FAST_DEPLOYMENT.md#parte-2-agregar-dispositivos-iot-repetir-por-cada-dispositivo)**

### "Quiero entender todas las opciones disponibles"
→ **[DEPLOYMENT.md](DEPLOYMENT.md)**

### "Necesito personalizar la configuración"
→ **[DEPLOYMENT.md](DEPLOYMENT.md)** (Método Manual)

### "Quiero entender cómo funciona el sistema"
→ **[ARCHITECTURE.md](ARCHITECTURE.md)**

### "Necesito mejorar la seguridad"
→ **[SECURITY.md](SECURITY.md)**

### "Tengo problemas con el sistema"
→ **[DEPLOYMENT.md - Troubleshooting](DEPLOYMENT.md#troubleshooting)** o **[FAST_DEPLOYMENT.md - Troubleshooting](FAST_DEPLOYMENT.md#troubleshooting-rápido)**

---

## 📖 Resumen de Documentos

### FAST_DEPLOYMENT.md
**Guía de Despliegue Rápido**

Configuración del sistema en menos de 15 minutos con scripts automáticos.

**Contenido:**
- Configuración del servidor (una sola vez)
- Agregar dispositivos IoT (proceso automático)
- Acceso a dispositivos
- Comandos útiles
- Troubleshooting rápido

**Ideal para:** Primera instalación, deployment rápido

---

### DEPLOYMENT.md
**Guía de Despliegue Detallada**

Documentación completa con todas las opciones y configuraciones posibles.

**Contenido:**
- Requisitos detallados
- Configuración manual paso a paso
- Configuración automática
- Acceso a dispositivos (login mejorado)
- Verificación y testing
- Deployment masivo
- Troubleshooting extenso
- Mantenimiento y backups

**Ideal para:** Configuración avanzada, personalización, referencia completa

---

### ARCHITECTURE.md
**Arquitectura del Sistema**

Explicación técnica de cómo funciona el sistema internamente.

**Contenido:**
- Componentes del sistema
- Flujo de comunicación
- Estructura de archivos
- Decisiones de diseño
- Diagramas de arquitectura

**Ideal para:** Desarrolladores, contribuidores, comprensión técnica

---

### SECURITY.md
**Guía de Seguridad**

Mejores prácticas y configuraciones de seguridad.

**Contenido:**
- Hardening del servidor SSH
- Gestión de claves
- Firewall y networking
- Rotación de credenciales
- Auditoría y logs
- Respuesta a incidentes

**Ideal para:** Administradores, ambientes de producción

---

### client/scripts/README.md
**Documentación de Scripts del Cliente**

Guía específica de los scripts de configuración automática.

**Contenido:**
- `setup_client.sh` - Script de configuración automática
- `device_identifier.sh` - Generación de Device ID
- `ssh_tunnel_setup.sh` - Gestión de túneles
- Flujo de trabajo
- Troubleshooting específico

**Ideal para:** Usuarios de dispositivos IoT, automatización

---

## 🔄 Flujo de Lectura Recomendado

### Para Principiantes

1. **README.md** (raíz del proyecto) - Visión general
2. **FAST_DEPLOYMENT.md** - Configuración práctica
3. **client/scripts/README.md** - Entender los scripts
4. **DEPLOYMENT.md - Troubleshooting** - Cuando tengas problemas

### Para Administradores

1. **README.md** (raíz del proyecto) - Visión general
2. **ARCHITECTURE.md** - Entender el sistema
3. **DEPLOYMENT.md** - Configuración detallada
4. **SECURITY.md** - Hardening y mejores prácticas
5. **FAST_DEPLOYMENT.md** - Referencia rápida

### Para Desarrolladores

1. **README.md** (raíz del proyecto) - Visión general
2. **ARCHITECTURE.md** - Arquitectura completa
3. **DEPLOYMENT.md** - Detalles de implementación
4. **client/scripts/README.md** - Scripts del cliente
5. **SECURITY.md** - Consideraciones de seguridad

---

## 📝 Convenciones de Documentación

### Símbolos Usados

- 🚀 **Inicio Rápido**: Contenido para empezar rápidamente
- ⚙️ **Configuración**: Pasos de configuración
- 🔧 **Comandos**: Comandos y ejemplos de uso
- 💡 **Consejo**: Tips y mejores prácticas
- ⚠️ **Advertencia**: Información importante
- 🚨 **Error**: Problemas comunes y soluciones
- ✅ **Verificación**: Pasos de validación
- 📊 **Información**: Datos complementarios

### Formato de Comandos

```bash
# Comentario explicativo
comando a ejecutar

# Output esperado (cuando aplica)
```

### Rutas de Archivos

- Rutas absolutas: `/opt/iot-ssh-reverse-tunnel/...`
- Rutas relativas al proyecto: `server/scripts/...`
- Variables de entorno: `${VARIABLE}`

---

## 🆘 Obtener Ayuda

1. **Revisa la documentación relevante** (usa el mapa arriba)
2. **Busca en el troubleshooting** de FAST_DEPLOYMENT.md o DEPLOYMENT.md
3. **Verifica logs** del sistema y servicios
4. **Abre un issue** en GitHub con:
   - Descripción del problema
   - Logs relevantes
   - Pasos para reproducir
   - Configuración (sin información sensible)

---

## 📚 Documentación Adicional

### En el Repositorio

- `README.md` (raíz) - Descripción general del proyecto
- `LICENSE` - Licencia MIT
- `client/examples/` - Ejemplos de configuración
- `server/configs/` - Archivos de configuración de ejemplo

### Enlaces Externos

- [OpenSSH Documentation](https://www.openssh.com/manual.html)
- [AutoSSH Guide](https://www.harding.motd.ca/autossh/)
- [Systemd Documentation](https://www.freedesktop.org/software/systemd/man/)

---

## 🔄 Actualizaciones de Documentación

La documentación se actualiza regularmente. Verifica la fecha de última modificación de cada archivo.

**Última revisión completa:** [Fecha de hoy]

---

**¿Listo para empezar?** → [FAST_DEPLOYMENT.md](FAST_DEPLOYMENT.md)
