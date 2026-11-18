# FumetaOS

Framework de administración y automatización de un servidor doméstico Ubuntu,
integrado con CasaOS, Docker, almacenamiento SMB, copias y Telegram.
No es una distribución Linux ni sustituye a Ubuntu o CasaOS.

La versión se lee de `VERSION`. El nombre utilizado en las publicaciones es
**FumetaOS vX.Y.Z**; las rutas y comandos mantienen `fumetaos`.

## Documentación actual

- [Arquitectura de FumetaOS](docs/ARQUITECTURA.md).
- [Recuperación y migración](docs/RECUPERACION.md).
- [Historial de cambios](CHANGELOG.md).

La guía describe el código y las dependencias. El inventario de cada servidor
se conserva por separado.

## Componentes

- `bin/`: interfaz y tareas de operación.
- `core/`: configuración común, servicios, aplicaciones, eventos y sesiones SSH.
- `modules/monitor/`: comprobaciones que alimentan el informe de salud.
- `apps/`: definiciones históricas de Jellyfin y Transmission; **no son los
  Compose de producción actuales**. No usarlas para recrear los contenedores sin
  revisar sus rutas, imagen y puertos.
- `services/`: unidades y timers de systemd.
- `install/`: instalación y actualización desde el paquete preparado.
- `config/`: estructura y ejemplos; la configuración efectiva está en
  `/opt/fumetaos/config` y puede contener secretos.
- `sudoers/`: permisos limitados para consultas concretas.
- `tests/`: pruebas aisladas, sin iniciar copias reales.

En una instalación de desarrollo, `/opt/fumetaos/{bin,core,modules,apps,VERSION}` pueden ser enlaces al
repositorio de trabajo. **No borrar ni mover el proyecto sin
desacoplar primero esos enlaces.** La configuración y el paquete son independientes.

## Programación efectiva de esta instalación

Zona horaria: Europe/Madrid.

- Cadena nocturna a las 00:30: copia local → Time Capsule a Data WD → recuperación
  cifrada y VM → espejo general a Data WD → actualización de Ubuntu → limpieza Docker.
- Verificación Restic los lunes o recuperación de una cita semanal perdida.
- Prueba SMART corta al final de la cadena de martes a domingo, en el HDD Datos,
  el SSD Sistema y el USB WD si está conectado.
- Prueba SMART larga los lunes, después de la verificación cifrada, en el HDD
  Datos y el SSD Sistema. Se ejecuta en segundo plano y los discos siguen
  accesibles durante la prueba. Consulta la [guía de SMART](docs/SMART-AL-FINAL-DE-LA-CADENA.md).
- Los informes de Telegram de las 07:00 y 21:30 muestran el último resultado
  SMART nocturno del USB WD sin despertarlo. La sección Discos agrupa Data WD y
  Time Capsule. Si falla la recuperación automática de Time Capsule, se envía
  un aviso separado con el diagnóstico.
- Watch cada 5 minutos; histórico cada 10; recuperación de Time Capsule cada 3;
  retirada de torrents terminados e inactivos cada 5; limpieza de histórico a las 02:00.

La cadena nocturna concentra las copias, la actualización de Ubuntu, la
verificación y SMART. El instalador retira los temporizadores individuales
de FumetaOS al actualizar una instalación anterior. Los temporizadores de
APT de Ubuntu se desactivan para evitar actualizaciones fuera de la cadena.

## Comandos principales

```text
fumetaos help
fumetaos version
fumetaos doctor
fumetaos config
fumetaos status
fumetaos health
fumetaos services
fumetaos history
fumetaos app list
```

`fumetaos report` envía Telegram: no es una consulta sin efectos.
`fumetaos doctor` muestra la última ejecución correcta de cada copia y de la
verificación Restic. Usa el historial local de systemd y los mismos límites
que el informe. También compara la versión y los directorios `bin`, `core` y
`modules` del paquete con la instalación activa.

`fumetaos config` muestra la ruta de la configuración.

## Construcción y despliegue

`bin/fumetaos-build` prepara `/opt/fumetaos/install/package` a partir del proyecto.
`install/install.sh` y `install/update.sh` consumen ese paquete. No basta con
clonar el repositorio y ejecutar el instalador: antes debe existir un paquete
correctamente preparado y la configuración privada correspondiente.

Usa `sudo /opt/fumetaos/install/package/install/update.sh --check` para comprobar
la compatibilidad del paquete con la instalación. Si una ruta activa enlaza al
proyecto, la comprobación exige que coincida con el paquete antes de actualizar.

Para una instalación inicial, prepara `fumetaos.conf` a partir de
`fumetaos.conf.example` en `/opt/fumetaos/config/` o en `config/` dentro del
paquete. El instalador conserva la configuración existente y requiere que
sea legible y tenga contenido.

Estos procesos pueden copiar directorios, modificar unidades y activar servicios;
no son pruebas inocuas. Un clon del repositorio no instala por sí solo Ubuntu,
CasaOS parcheado, credenciales, aplicaciones de CasaOS, Samba, redes o datos.

## Pruebas

```bash
bash -n bin/fumetaos-nightly
bash -n core/mac-mirror-common.sh
bash tests/test-nightly.sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_jellyfin_mount_guard.py
```

GitHub Actions ejecuta las pruebas de Bash y Python en los cambios del
repositorio. El test nocturno simula systemd y valida trece escenarios, incluido el paso de
limpieza Docker. No se deben sustituir estas pruebas por iniciar la cadena real.
`bin/fumetaos-quality` requiere Bash, Git, ShellCheck y shfmt.

## Seguridad y recuperación

Nunca publicar tokens de Telegram, contraseña Restic, claves SSH, configuraciones
completas de contenedores o credenciales SMB. Restaurar primero en una ubicación
aislada y revisar propietarios, rutas, arquitectura y redes antes de arrancar.

El README y la guía antigua mencionaban recuperación a las 04:00, una rama
`feature/system-manager-v2` y AFP como montaje principal. La instalación actual
utiliza la cadena de las 00:30, la rama `main` y SMB 3.1.1 para Time Capsule.

## Licencia

MIT, según la declaración del proyecto. Conservar los avisos de licencia de las
dependencias y de cualquier componente reconstruido por separado.
