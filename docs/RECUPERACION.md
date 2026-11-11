# Recuperación y migración de FumetaOS

Estado de referencia: FumetaOS 2.4.39, 11/11/2026. Esta guía es un procedimiento
de planificación; no autoriza ni ejecuta una restauración en producción.

Consultar también [arquitectura de FumetaOS](ARQUITECTURA.md).

## Qué protege cada copia

1. **Copia local de FumetaOS:** tar comprimido de configuración, bin, core,
   módulos, VERSION y unidades principales. Destinos: `/mnt/datos/backups/fumetaos`
   y `/var/backups/fumetaos`. Retención 7 diarias, 4 semanales y 3 mensuales.
   No es una copia completa del servidor y no recoge los drop-ins de systemd.
2. **Time Capsule → Mac:** espejo de las carpetas multimedia configuradas bajo
   `/DATA/TimeCapsule/Multimedia` al destino multimedia del USB del Mac.
3. **Recuperación cifrada Restic:** configuración del sistema, usuario, aplicaciones
   y VM; retención 14 diarias, 8 semanales y 12 mensuales.
4. **Espejo general → Mac:** `/mnt/datos` a
   el destino configurado en el USB. El repositorio Restic se sincroniza por
   separado, con el bloqueo de recuperación y fuera del cupo de borrados.
   Consulta la [guía del espejo Restic](ESPEJO-RESTIC-SIN-CUPO.md).

Los espejos reflejan también borrados, dentro de sus protecciones. No equivalen
a un archivo histórico inmutable. El destino del Mac debe resolver realmente al
USB `/Volumes/Data USB`; no basta con que exista una carpeta con ese nombre.

## Programación correcta

La recuperación no tiene actualmente un horario independiente a las 04:00.
Forma parte de `fumetaos-nightly.service`, iniciada diariamente a las 00:30
Europe/Madrid. Se ejecuta tras Time Capsule → Mac y antes del espejo general.
Los timers individuales están desactivados. La cadena verifica Restic los lunes
o si han pasado al menos siete días desde la última verificación correcta. Al
final ejecuta SMART largo los lunes y SMART corto de martes a domingo.

## Repositorio, clave y fuentes

- Restic: `/mnt/datos/backups/fumetaos/recovery-repo`.
- Contraseña: `/etc/fumetaos/restic-password`; guardar una copia privada fuera
  del servidor y del propio repositorio cifrado.
- Caché: `/var/cache/fumetaos-restic`.
- Metadatos: `/var/lib/fumetaos/recovery-metadata`.
- Proyecto: `git@github.com:fumetasing/FumetaOS.git`, rama `main`.
- Plataforma de restauración completa: Ubuntu Server AMD64/x86_64.

El trabajo Restic incluye `/etc`, `/home/server`, `/root`, `/DATA`, `/opt/fumetaos`,
`/usr/local`, `/var/lib/casaos`, metadatos y los archivos temporales de discos VM;
añade `/var/spool/cron` cuando existe. Usa `--one-file-system` y excluye
`/DATA/TimeCapsule`.

No incluye como datos de usuario el contenido de `/mnt/datos` ni de Time Capsule.
No es una imagen arrancable del SSD. Tampoco hace una copia general de `/usr/bin`
ni de `/var/lib/docker`. Conserva por separado el binario parcheado
`/usr/bin/casaos` o los materiales necesarios para reconstruirlo.

## Consistencia y máquinas virtuales

El proceso identifica las VM de `qemu:///system`, solicita el apagado de las que
están encendidas y espera hasta 300 segundos por VM; no fuerza su destrucción.
Detecta discos de archivo, los empaqueta con tar sparse bajo
`/var/cache/fumetaos-recovery-vms` y guarda XML y correspondencias de discos.

Detiene temporalmente el servicio principal CasaOS y los contenedores que estaban
activos. Al salir intenta recuperar esos servicios y las VM previamente encendidas.
Esto produce una interrupción real de las aplicaciones: no programar otra copia
consistente o actualización de contenedores simultáneamente.

El inventario de paquetes, XML de VM, montajes, unidades, imágenes y `docker inspect`
está dentro de los metadatos de recuperación. Puede contener secretos y debe
mantenerse privado, aunque la documentación de arquitectura no los contenga.

## Comprobaciones de consulta

```bash
sudo /opt/fumetaos/bin/fumetaos-recovery-backup list
sudo /opt/fumetaos/bin/fumetaos-recovery-backup stats
```

`verify` ejecuta `restic check --read-data`: no restaura, pero lee el repositorio
completo y puede consumir mucho tiempo y E/S. Planificarlo:

```bash
sudo /opt/fumetaos/bin/fumetaos-recovery-backup verify
```

## Orden recomendado de migración

1. Inventariar el estado real y confirmar copias utilizables y contraseña externa.
2. Reservar ventana de mantenimiento y evitar ejecuciones simultáneas de la cadena.
3. Preservar, de forma privada, credenciales, Compose, XML de VM y
   artefactos no cubiertos por Restic. No publicar una exportación de `docker inspect`.
4. Preparar Ubuntu AMD64, usuario `server` UID/GID 1000 y discos identificados por
   UUID o by-id. Revisar LVM y EFI; no copiar a ciegas el fstab antiguo.
5. Recuperar un snapshot primero a un directorio de ensayo, **nunca directamente
   sobre `/`**. Revisar sus archivos y reconstruir paquetes y servicios por etapas.
6. Montar el HDD y establecer las rutas `/mnt/datos`, `/DATA` y permisos.
7. Recuperar proyecto y runtime respetando los enlaces de `/opt/fumetaos`.
8. Instalar CasaOS y aplicar/verificar el parche de memoria conocido; no restaurar
   simplemente un binario oficial v0.4.15 como si incluyera el arreglo.
9. Configurar SMB de Time Capsule y su bind de CasaOS antes de iniciar Jellyfin.
10. Instalar Docker y Compose, recrear las redes y obtener las imágenes con los
    digests del inventario de recuperación.
11. Restaurar datos y Compose bajo `/var/lib/casaos/apps`, manteniendo proyectos,
    servicios, puertos, credenciales, healthchecks y digests.
12. Restaurar libvirt y discos VM con rutas y permisos correctos; el contenedor
    `maquinas-virtuales` no contiene las máquinas virtuales.
13. Recuperar configuración privada de Telegram y SMB, confianza SSH, Restic y
    estado del contador diario. Revisar Tailscale y No-IP de forma independiente.
14. Validar UFW y reglas Docker IPv4/IPv6 antes de exponer servicios.
15. Hacer consultas y simulaciones; después una copia real controlada y una
    restauración de prueba de archivos y VM.
16. Activar solo los timers correctos al final. `Persistent=true` puede recuperar
    una ejecución perdida inmediatamente: no activar los timers antes de estar listo.

No tener dos equipos con la misma IP, nombre o acceso de escritura simultáneo al
mismo destino de copia. No llevar automáticamente las claves de identidad de
Tailscale a dos servidores activos.

## Límites que hay que conservar

- Apertura SSH al Mac: 30 intentos, 15 segundos entre ellos; no garantiza despertar.
- Espejo general: hasta 50 borrados por día natural del servidor fuera de
  `PS4 & PS5` y del repositorio Restic. Ambos se sincronizan fuera del cupo.
- Contador: `/var/lib/fumetaos-mac-delete-budget/contador.json`, root, directorio
  0700 y archivo 0600. La reserva se registra antes de copiar; una interrupción
  no concede automáticamente otro cupo. No borrarlo para intentar reparar una copia.
- Time Capsule: 20 borrados por carpeta, sin convertirlo en un cupo diario global.
- Código rsync 25: copia parcial por límite; no anunciar copia completa.
- USB del Mac: al menos 50 GiB libres y montaje real validado. Tras conectar
  por SSH, los espejos esperan hasta 180 segundos a que aparezca el montaje.

## Material privado que no debe faltar

- Contraseña Restic, token y chat de Telegram.
- Credenciales SMB de Time Capsule y credenciales Samba del servidor.
- Claves SSH y known_hosts necesarios, con permisos y passphrases correctos.
- Configuraciones de aplicaciones, usuarios CasaOS y contraseñas RPC/web.
- Acceso de GitHub necesario para publicar; claves de Tailscale y No-IP según
  su propio procedimiento de recuperación.

Un documento de traspaso o un clon Git no sustituye estos materiales.
