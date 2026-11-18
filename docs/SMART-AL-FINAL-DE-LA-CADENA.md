# Pruebas SMART después de la cadena nocturna

Las pruebas SMART se inician al terminar las copias, la actualización de Ubuntu, la limpieza de Docker y, cuando corresponde, la verificación cifrada. No tienen una hora independiente.

- Corta, de martes a domingo, en el HDD Datos, el SSD Sistema y el USB WD cuando está conectado.
- Larga, los lunes, en el HDD Datos y el SSD Sistema. Se ejecuta en segundo plano y los discos siguen accesibles. El uso del disco puede ralentizar la prueba y las transferencias.
- La cita mensual redundante se ha retirado. No se recuperan pruebas largas de lunes perdidos.
- La programación `-s` de smartd se retira de la entrada DEVICESCAN del servidor. smartd continúa vigilando salud, temperaturas y errores.
- El servicio corto comparte bloqueo con el largo y comprueba que no haya una prueba de disco en curso antes de iniciar nada.
- La cadena espera la comprobación y registra el fallo si no termina correctamente. Los horarios de Telegram y la verificación cifrada no cambian.

La prueba larga existente mantiene su espera de 340 minutos y su límite de siete horas. La corta tiene un límite de quince minutos. La cadena nocturna ejecuta ambos servicios.

El lunes, la prueba larga va después de la verificación cifrada semanal.
