# Pruebas SMART después de la cadena nocturna

Las pruebas SMART se inician al terminar las copias, la actualización de Ubuntu, la limpieza de Docker y, cuando corresponde, la verificación cifrada. No tienen una hora independiente.

- Corta, de martes a domingo, en el HDD Datos, el SSD Sistema y el USB WD cuando está conectado.
- Larga, los lunes, en el HDD Datos y el SSD Sistema. Se ejecuta en segundo plano y los discos siguen accesibles. El uso del disco puede ralentizar la prueba y las transferencias.
- La cita mensual redundante se ha retirado. No se recuperan pruebas largas de lunes perdidos.
- La programación `-s` de smartd se retira de la entrada DEVICESCAN del servidor. smartd continúa vigilando salud, temperaturas y errores.
- El servicio corto comparte bloqueo con el largo y comprueba que no haya una prueba de disco en curso antes de iniciar nada.
- La cadena espera la comprobación y registra el fallo si no termina correctamente. Los horarios de Telegram y la verificación cifrada no cambian.

La prueba larga consulta el progreso cada cinco minutos, con un máximo de doce horas de espera compartida. Si al llegar al límite sigue en curso, lo indica con un aviso en amarillo. Systemd concede quince minutos adicionales para el arranque y la salida. La corta tiene un límite de quince minutos. La cadena nocturna ejecuta ambos servicios.

El lunes, la prueba larga va después de la verificación cifrada semanal.

## Coordinación con el reposo

En este servidor, `hd-idle-datos.service` y `hd-idle-wd.service` controlan cada disco por separado a tres minutos. La prueba larga suspende el control del HDD Datos. La corta suspende el de los discos que comprueba. Cada servicio reactiva siempre los controles de reposo de los discos implicados al salir, incluido un fallo, una cancelación o el tiempo máximo de ejecución. El SSD carece de temporizador de giro.

Si esas unidades locales de reposo no existen, los servicios SMART continúan sin intentar crearlas. La gestión temporal del reposo se aplica al ejecutar las pruebas mediante sus servicios de systemd.
