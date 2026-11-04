# Repositorio cifrado fuera del cupo del espejo

El espejo diario al Mac separa tres grupos:

- PS4 & PS5: sin límite de borrados, como antes.
- `backups/fumetaos/recovery-repo`: sin límite de borrados y sin consumir el contador diario.
- Resto de datos: mantiene el máximo persistente de 50 borrados diarios.

Restic elimina y reorganiza sus archivos internos al aplicar la retención. No representan una correspondencia uno a uno con documentos personales. La exención permite reflejar ese mantenimiento sin agotar el cupo del resto de datos.

Antes de copiar, se comprueban el USB, la ruta real del origen, la estructura del repositorio, la presencia de instantáneas y que Restic puede descifrar su configuración. Si el destino ya existe, su configuración debe coincidir con la del repositorio original y no puede haber enlaces simbólicos en la ruta relativa. Si una comprobación falla, no se inicia la transferencia.

El espejo comparte el bloqueo de la copia de recuperación para evitar que Restic modifique el repositorio mientras se refleja al Mac. No cambia la retención de Restic, los horarios, los 30 intentos SSH ni la espera del USB.
