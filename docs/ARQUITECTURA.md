# Arquitectura de FumetaOS

FumetaOS automatiza la operación de un servidor Ubuntu con CasaOS. El
[README](../README.md) describe los comandos y la programación de referencia.

## Componentes

- Los comandos de `bin/` usan las funciones comunes de `core/`. Las unidades
  de `services/` programan copias, mantenimiento y monitorización.
- CasaOS administra los proyectos Docker Compose. FumetaOS consulta sus
  contenedores y servicios para generar el informe de salud. El servidor
  conserva los Compose efectivos.
- El servidor monta los recursos de datos y SMB que utilizan las aplicaciones.
  Las máquinas virtuales dependen de libvirt y de sus discos.
- El instalador utiliza el paquete generado por el proyecto. Si la instalación
  enlaza código activo al repositorio local, revisa esos enlaces antes de moverlo.

## Copias y recuperación

La cadena nocturna coordina la copia local, el espejo de Time Capsule al Mac,
la recuperación cifrada y el espejo general al Mac. Después ejecuta el
mantenimiento y las verificaciones programadas.

El espejo sincroniza por separado el repositorio Restic y comparte el bloqueo
de recuperación. Consulta la [guía de recuperación](RECUPERACION.md) y la
[guía del espejo Restic](ESPEJO-RESTIC-SIN-CUPO.md).

Conserva en privado el inventario de red, discos, montajes, Compose e identidades.
Guarda las credenciales de restauración fuera de Git y del repositorio cifrado.
