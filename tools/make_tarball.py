"""Empaqueta un ejecutable de Linux en .tar.gz con permiso de ejecución (755), desde Windows.
Uso: python tools/make_tarball.py <binario> <salida.tar.gz>"""
import sys
import tarfile
from pathlib import Path

src, dest = Path(sys.argv[1]), sys.argv[2]
with tarfile.open(dest, "w:gz") as tar:
    info = tar.gettarinfo(str(src), arcname=src.name)
    info.mode = 0o755
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    with open(src, "rb") as f:
        tar.addfile(info, f)
print("wrote", dest)
