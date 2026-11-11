import ctypes
import os
import stat
import sys

source, target = sys.argv[1:]
try:
    target_mode = os.lstat(target).st_mode
except FileNotFoundError:
    flags = 1  # RENAME_NOREPLACE
else:
    if not stat.S_ISDIR(target_mode):
        raise SystemExit("El destino dejó de ser un directorio normal.")
    flags = 2  # RENAME_EXCHANGE

libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
renameat2.restype = ctypes.c_int
at_fdcwd = -100
if renameat2(at_fdcwd, os.fsencode(source), at_fdcwd, os.fsencode(target), flags) != 0:
    raise SystemExit(f"No se pudo publicar el paquete: {os.strerror(ctypes.get_errno())}")
