# Sistema de Túneles SSH Inversos para Dispositivos IoT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)
[![Architecture](https://img.shields.io/badge/Architecture-ARM%20%7C%20x86-orange.svg)](README.md)

Infraestructura de referencia para habilitar acceso remoto seguro a dispositivos IoT a través de túneles SSH inversos endurecidos.

## Contenido del repositorio

- `server/`
  - `configs/sshd_config.d/iot-tunnel.conf`: plantilla de configuración para `/etc/ssh/sshd_config.d/` con restricciones de túneles públicos.
  - `scripts/`: utilidades para registro, monitoreo y contención de túneles.
  - `examples/`: fragmentos como `authorized_keys.example` para vincular claves con puertos autorizados.
  - `security/`: referencias como `ports.allow` para listas blancas.
- `client/`
  - `examples/`: scripts de ejemplo (por ejemplo `autossh-expose-ssh.sh`).
  - `systemd/`: unidades y helpers para ejecutar autossh o scripts heredados.
  - `scripts/`: herramientas para identificar dispositivos y gestionar túneles.
- `security/`: utilidades compartidas para claves (`keygen.sh`, `key_rotation.sh`).
- `scripts/`: comprobaciones adicionales como `lint.sh` para validar configuraciones.
- `docs/`: documentación detallada de arquitectura, despliegue, seguridad y troubleshooting.
- `examples/`: guías para proveedores cloud y casos de uso.

## Documentación principal

- [Despliegue paso a paso](docs/DEPLOYMENT.md)
- [Arquitectura y componentes](docs/ARCHITECTURE.md)
- [Guía de seguridad y hardening](docs/SECURITY_GUIDE.md)
- [Resolución de problemas](docs/TROUBLESHOOTING.md)

## Ejemplos y guías prácticas

- [Scripts de cliente](client/examples/)
- [Unidades systemd de referencia](client/systemd/)
- [Cloud providers (AWS, Azure, GCP)](examples/cloud_providers/)
- [Casos de uso destacados](examples/use_cases/)

## Próximos pasos recomendados

1. Revisa [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) para preparar el servidor y los dispositivos.
2. Aplica la configuración de `server/configs/sshd_config.d/iot-tunnel.conf` en tu host y actualiza `authorized_keys` con las restricciones deseadas.
3. Configura un cliente usando `client/examples/autossh-expose-ssh.sh` o las unidades de `client/systemd/`.
4. Refuerza controles siguiendo [docs/SECURITY_GUIDE.md](docs/SECURITY_GUIDE.md) y revisa las secciones de firewall.

## Contribuciones y soporte

Las contribuciones son bienvenidas mediante issues y pull requests.

- Issues: [GitHub Issues](https://github.com/calderonf/iot-ssh-reverse-tunnel/issues)
- Documentación: [docs/](docs/)
- Ejemplos: [examples/](examples/)

## Licencia

Este proyecto está licenciado bajo la Licencia MIT. Consulta [LICENSE](LICENSE) para más detalles.

---

Proyecto desarrollado con fines educativos e investigación en la Pontificia Universidad Javeriana.
