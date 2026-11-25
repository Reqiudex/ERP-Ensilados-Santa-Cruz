"""Pone el hash del contenido en el nombre de main.dart.js y flutter_bootstrap.js (carpeta dada).

Cloudflare guarda en caché los .js sin hash hasta 4 h; con el nombre versionado un despliegue nuevo
nunca mezcla un index.html nuevo con un main.dart.js viejo. index.html se sirve sin caché.
"""
import hashlib, pathlib, sys

web = pathlib.Path(sys.argv[1])
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()[:10]

main = web / 'main.dart.js'
nuevo_main = f'main.dart.{h(main)}.js'
main.rename(web / nuevo_main)
boot = web / 'flutter_bootstrap.js'
boot.write_text(boot.read_text().replace('"main.dart.js"', f'"{nuevo_main}"'))
nuevo_boot = f'flutter_bootstrap.{h(boot)}.js'
boot.rename(web / nuevo_boot)
index = web / 'index.html'
texto = index.read_text()
assert '<script src="flutter_bootstrap.js" async></script>' in texto
index.write_text(texto.replace('<script src="flutter_bootstrap.js" async></script>', f'<script src="{nuevo_boot}" async></script>'))
print(nuevo_main, nuevo_boot)
