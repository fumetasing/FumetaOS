# FumetaOS Changelog

## v2.4.41

- `fumetaos doctor` compara la versión y los directorios `bin`, `core` y `modules` del paquete con la instalación activa.
- Cuatro pruebas cubren la antigüedad de las copias, la consulta del historial y la verificación cifrada.
- GitHub Actions usa Ubuntu 26.04 y `actions/checkout` v7.0.1 con Node.js 24.

## v2.4.40

- `fumetaos doctor` muestra la última ejecución correcta de cada copia y de la verificación Restic, y avisa cuando están atrasadas.
- GitHub Actions ejecuta las pruebas de FumetaOS al subir cambios y al abrir o actualizar solicitudes de cambio.
- `fumetaos config` muestra la ruta de la configuración. `fumetaos update` indica cómo aplicar un paquete preparado.
- Se actualizan el README y las guías de arquitectura y recuperación.

## v2.4.39

- El informe distingue en amarillo las aplicaciones cuyo healthcheck de Docker todavía está en curso.

## v2.4.38

- El monitor de FileZilla reconoce las imágenes oficiales de LinuxServer en lscr.io y compara el manifiesto instalado con las variantes del índice remoto.

## v2.4.37

### Changed

- El espejo al Mac sincroniza por separado el repositorio cifrado de recuperación, fuera del cupo de borrados.
- El resto conserva el máximo persistente de 50 borrados diarios. PS4 & PS5 mantiene su exención.
- Se valida el repositorio de destino y se comparte el bloqueo de Restic durante el espejo.

## v2.4.36

### Changed

- Las pruebas SMART de HDD y SSD se ejecutan al final de la cadena nocturna, sin hora independiente: cortas de martes a domingo y larga los lunes, después de la verificación cifrada.
- Se retira la cita larga mensual redundante. Si se pierde un lunes, la siguiente larga queda para el siguiente lunes.
- El servicio corto comparte bloqueo con el largo y comprueba sus resultados; ambos evitan interrumpir pruebas ya en curso.
- Se conserva la vigilancia continua de smartd; en este despliegue se ha retirado su programación fija de pruebas.

Validados trece escenarios simulados de la cadena y nueve del SMART corto, sintaxis y análisis estático. Código, servicios y VERSION sincronizados en proyecto, instalación activa y paquete. Sin iniciar copias o pruebas SMART reales ni cambiar los horarios de Telegram.

## v2.4.35

### Added

- Guía del perfil DNS de Movistar para Ubuntu, Docker, AdGuard Home, macOS y Tailscale, con comprobaciones y límites de alcance.
- Perfil opcional de respaldo DNS para systemd-resolved; requiere instalación explícita del administrador.

Los cambios DNS de este despliegue se conservan fuera del repositorio; no se publican credenciales ni se cambia automáticamente el proveedor de otras instalaciones. Se conservan los nombres internos, las copias, los horarios y el parche de CasaOS.

## v2.4.34

### Added

- CasaOS aparece en el apartado Actualizaciones del informe mediante consulta de la última release estable oficial de IceWhaleTech.
- El aviso distingue versiones nuevas, ausencia de una nueva release y errores de consulta; excluye betas y borradores y compara versiones numéricamente.
- Cuando hay una versión superior, indica revisar el parche local antes de actualizar. No sustituye el binario instalado ni activa actualizaciones automáticas.

Validados once escenarios aislados, sintaxis Bash y consulta oficial real. Comprobador e informe sincronizados en proyecto, instalación y paquete. Sin reinicios, copias ni envío de informes.

## v2.4.33

### Fixed

- El informe y ambas copias al Mac esperan hasta 180 segundos al montaje del USB después de autenticar SSH, con comprobaciones cada 10 segundos y protección temporal contra reposo.
- La comprobación del USB valida su punto de montaje real y diferencia errores de conexión, montaje, permisos y espacio disponible.

### Changed

- AdGuard Home aparece en Actualizaciones mediante consulta de la imagen estable oficial de Docker Hub, sin descargar ni instalar imágenes. Se compara la imagen realmente ejecutada para detectar también reconstrucciones de una misma versión.
- Se retira el análisis histórico de fallos de CasaOS de las últimas 24 horas; se mantiene la comprobación del estado del servicio.
- La prueba de la cadena nocturna contempla el paso de limpieza Docker y su posible fallo.

Se conservan los 30 intentos SSH, horarios, reintentos de transferencias y cupos de borrado. Pruebas aisladas de USB y AdGuard, ocho escenarios de la cadena nocturna y cinco pruebas del guardián de Jellyfin superados. Proyecto, instalación y paquete comprobados. Esta publicación no ejecuta copias ni envía informes.

## v2.4.32

### Changed

- La apertura de la sesión SSH protegida con el Mac pasa de 20 a 30 intentos en ambas copias: Time Capsule y espejo general.
- Se mantienen los 15 segundos entre intentos, los demás tiempos de espera y la protección temporal contra reposo.
- Sin cambios de horarios, reintentos de transferencias ni límites de borrado: 50 diarios fuera de PS4 & PS5, PS4 & PS5 exenta y 20 por carpeta de Time Capsule.

Validado el cambio exacto de dos líneas, la sintaxis Bash, la coincidencia del código entre proyecto, instalación y paquete y una prueba aislada de 30 intentos fallidos, 29 pausas y limpieza de sesiones. La prueba no utiliza la red ni inicia copias. Aumentar los intentos no garantiza despertar macOS. Sin reinicios al publicar.

La prueba antigua tests/test-nightly.sh mantiene el fallo preexistente por no contemplar el paso de limpieza Docker; no se modifica en esta versión.

## v2.4.31

### Changed

- Ambas copias al Mac (Time Capsule y espejo general) permiten hasta 20 intentos para establecer la sesión SSH protegida.
- Se conservan los 15 segundos entre intentos, la sesión persistente y la protección temporal contra reposo.
- VERSION se actualiza a 2.4.31 y esta publicación incorpora el código de los 20 intentos.
- Sin cambios en horarios, reintentos de transferencias o límites de borrado: 50 diarios fuera de PS4 & PS5, carpeta PS4 & PS5 exenta y 20 por carpeta de Time Capsule.

El código de los 20 intentos ya estaba aplicado; esta versión lo consolida en una publicación nueva. Validado previamente con una prueba aislada de 20 intentos fallidos, 19 pausas y limpieza de sesiones, sin conexiones reales. Sintaxis y coincidencia del código entre proyecto, instalación y paquete comprobadas de nuevo. Aumentar los intentos no garantiza el despertar de macOS. Sin reinicios ni copias al publicar.

La prueba antigua tests/test-nightly.sh mantiene un fallo preexistente: no contempla el paso de limpieza Docker ya presente en la cadena. No se modifica en esta versión.

## v2.4.30

### Changed

- La apertura de la sesión SSH protegida con el Mac pasa de 10 a 20 intentos en ambas copias.
- Se mantienen los 15 segundos entre intentos y los demás tiempos de espera.
- Sin cambios en reintentos de transferencias, horarios ni límites de borrado: 50 diarios en el espejo general, PS4 & PS5 exenta y 20 por carpeta de Time Capsule.

Validado el cambio exacto de dos líneas, la sintaxis Bash y una prueba aislada de 20 intentos fallidos, 19 pausas y limpieza de sesiones, sin red ni copias reales. No garantiza el despertar de macOS. La prueba antigua tests/test-nightly.sh falla también en HEAD porque no contempla el paso ya existente de limpieza Docker; no se modifica en esta versión.

## v2.4.29

### Changed

- La apertura de la sesión SSH protegida con el Mac pasa de 3 a 10 intentos, tanto para Time Capsule como para el espejo general.
- Se mantienen los 15 segundos entre intentos y los demás tiempos de espera.
- No se añaden reintentos de transferencias ni borrados. Se conservan el cupo diario de 50, PS4 & PS5 exenta y los 20 borrados por carpeta de Time Capsule.

Validado el cambio exacto de dos líneas, la sintaxis Bash y la sincronización entre proyecto, instalación y paquete. No se ha forzado un fallo real de diez intentos; aumentar los intentos no garantiza que macOS despierte. Sin cambios de horarios o ajustes de energía.

## v2.4.28

### Fixed

- El espejo general al Mac mantiene una sesión SSH persistente con protección temporal contra reposo, igual que la copia Time Capsule → Mac.
- La sesión se cierra al terminar, fallar o recibir INT/TERM; si no se establece, no comienza la copia.
- Las comprobaciones de conexión utilizan la sesión compartida y reintentos limitados para errores SSH de transporte.
- Se mantienen el cupo persistente de 50 borrados diarios, la excepción PS4 & PS5 y la ausencia de reintentos automáticos de transferencias.

Validado con pruebas aisladas de cierre y fallo de sesión, sintaxis Bash/Python y una simulación programada en el servidor el 13/10/2026, terminada con código 0. Pendiente validar una transferencia prolongada y la siguiente copia nocturna. Sin cambios de horarios ni ajustes de energía del Mac.

## v2.4.27

### Added

- FileZilla aparece en el apartado Actualizaciones del informe, junto a Jellyfin y Transmission.
- La comprobación consulta el digest de la imagen LinuxServer publicada en Docker Hub y muestra la compilación instalada completa.
- Se distinguen los estados al día, actualización disponible y consulta no completada, sin descargar imágenes ni actualizar contenedores.
- La integración se incluye en el paquete de instalación y actualización mediante los directorios bin y modules existentes.

Validado con ocho pruebas aisladas y una consulta real: FileZilla 3.69.6-1-ls38 al día. Sin cambios de horarios, límites de borrado ni reinicios al publicar. La configuración privada de FileZilla no se publica.

## v2.4.26

### Fixed

- Time Capsule → Mac mantiene una sesión SSH persistente y una protección temporal contra reposo durante la copia.
- Las cuatro carpetas de destino se comprueban en una sola sesión, con reintentos limitados para fallos SSH de transporte.
- Los errores de conexión ya no se anuncian como carpetas inexistentes.
- La sesión temporal se cierra al finalizar o interrumpir la ejecución.
- Sin cambios de horarios ni límites: Time Capsule conserva 20 borrados por carpeta; el espejo general, 50 diarios con PS4 & PS5 exenta.

Validado mediante pruebas aisladas y simulaciones en el servidor, sin transferir ni borrar datos. Pendiente de comprobar una copia nocturna prolongada; no se certifica el despertar inicial de un Mac dormido.

## v2.4.20

### Fixed

- Corregido el contador preventivo de borrados de las copias espejo al Mac.
- La protección reconoce ahora las dos formas de salida utilizadas por rsync.
- Las copias se bloquean correctamente cuando se superarían los 50 borrados.
- Añadida una validación aislada del contador antes de publicar la corrección.


## v2.4.19

### Fixed

- Añadidos cinco reintentos antes de declarar inaccesible el USB del Mac.
- Evitados falsos avisos rojos provocados por fallos SSH transitorios en macOS 27.0.1.
- La comprobación realiza hasta seis intentos totales antes de afectar al estado general.



# Changelog

## v2.3.25

### Fixed

- Fixed FumetaOS backup script error handling.
- Fixed backup creation failure handling.
- Improved backup file ownership consistency.
- Backup files are now assigned to the `server` user and group.

## v2.3.24

### Fixed

- Fixed CasaOS crash caused by invalid SMB connection state.
- Improved stability after removing stale network mount references.
- Prevented SMB client state from breaking FumetaOS service operation.

## v2.3.23

### Improved

- Improved FumetaOS Watch service monitoring.
- Added warning state before reporting service failures.
- Prevented repeated Telegram alerts during persistent service outages.
- Improved service recovery detection.## v2.3.22

### Added

- Added application health monitoring.
- Added Jellyfin health validation.
- Added Transmission health validation.

### Improved

- Improved Telegram daily report formatting.
- Fixed duplicated Telegram report header.
- Improved application status reporting.

## v2.3.21

### Added

- Added application health monitoring.
- Added Docker health detection.
- Added custom health validation for Transmission.
- Added Jellyfin health validation.

### Improved

- Application reports now show real service health state.
- Jellyfin monitoring updated for CasaOS port mapping.

# 2.3.20

## Aplicaciones

- Corregida integración de Jellyfin con CasaOS.
- Migrada gestión de Jellyfin a instalación controlada por CasaOS.
- Corregidos montajes persistentes de biblioteca multimedia.
- Manteniendo configuración de usuario y datos mediante AppData.
- Actualizado Jellyfin a versión 10.11.10.

## Mantenimiento

- Eliminadas configuraciones antiguas de Jellyfin que podían interferir con CasaOS.
- Limpieza de definiciones duplicadas de aplicaciones.

# 2.3.0

## Nuevas funciones

- Añadido sistema de eventos persistente
- Añadido registro local de eventos del sistema
- Añadido visor de eventos FumetaOS Events
- Mejorado el sistema FumetaOS Watch
- Mejorado FumetaOS Doctor con nuevas comprobaciones


## Monitorización

- Añadida monitorización de timers FumetaOS
- Mejor integración entre Watch y Events
- Mejoras en diagnóstico del sistema
- Mejoras en comprobaciones de servicios


## Instalación y actualización

- Mejorado instalador FumetaOS
- Unificada gestión de timers en instalación y actualización
- Mejorado sistema de construcción de paquetes


## Interfaz

- Mejoras visuales en herramientas de consola
- Nuevos paneles de estado
- Preparación de vistas tipo dashboard


---

# 2.2.5

## Sistema

- Añadido gestor de servicios FumetaOS
- Añadido comando:
  - `fumetaos services`

## Monitorización

- Añadido sistema Watch
- Añadidas alertas Telegram
- Añadida monitorización de:
  - Servicios
  - Temperatura
  - Discos
  - Aplicaciones


## Dashboard

- Integración de servicios en Dashboard
- Mejoras en presentación del estado general


## Instalación

- Añadido generador de paquetes FumetaOS
- Mejoras en servicios systemd


---

# 2.2.0

## Base del sistema

- Nueva estructura modular FumetaOS
- Sistema de módulos de monitorización
- Gestión de aplicaciones Docker
- Configuración centralizada


## Monitorización

- Estado del sistema
- Memoria
- Temperaturas
- Discos
- SMART
- Aplicaciones


## Herramientas

- Dashboard principal
- Health check
- Doctor
- Backup
- History
- Update
