# PULSO (público) — instrucciones permanentes

## Propósito
Código reproducible público de PULSO (instrumentación y adquisición de datos para monitorización estructural, UCO): experimentos de referencia en Julia, fixtures y datos sintéticos. El texto del sitio vive en el repositorio **privado** `me1catrr/pulso-quarto` (carpeta hermana `../pulso-quarto`); aquí solo llega su HTML, en la rama `gh-pages`.

## Separación con pulso-quarto
- Aquí no se escriben ni renderizan `.qmd`, `_quarto.yml`, `_freeze/`, bibliografía ni simuladores: todo eso está en pulso-quarto.
- La rama `gh-pages` (sin historia común con `main`) solo la escribe `scripts/publicar.sh` de pulso-quarto. No editarla a mano.
- pulso-quarto lee los fixtures de este repo. Cambiar su formato obliga a revisar los simuladores y las páginas afectadas.

## Autorizaciones (obligatorio)
Requieren confirmación expresa de Rafa en el momento, cada vez: crear o cambiar la visibilidad del repositorio, cada `git push`, cambiar GitHub Pages, crear releases.

## Arquitectura
- `experimentos/<nombre>/`: script Julia de referencia (semilla fija) → `fixtures/*.json` y figuras. Uno por experimento: cadena de medida, sincronización, disparo STA/LTA.
- Sin paquete hasta que dos experimentos compartan funciones; entonces se extrae a `julia/Pulso.jl/`.
- Python solo con justificación científica: ObsPy como referencia (miniSEED, StationXML, respuesta del instrumento) o implementación independiente de contraste con tolerancia declarada. No traducir código por traducir.
- `datos/sinteticos/`: solo datos generados por script versionado, cada conjunto con su ficha `.meta.toml`.

## Material protegido y datos sensibles
- Nunca: manuales o documentación de fabricantes, registros experimentales reales sin autorización, configuraciones de equipos, fotos o capturas sin permiso, números de serie, IPs, nombres de personas o clientes.
- La lista privada de términos vetados vive fuera de cualquier repositorio (`~/.config/pulso/terminos-vetados.txt` o `$PULSO_VETADOS`); el guardián la aplica si existe.
- Licencias: código MIT (`LICENSE`); datos sintéticos CC BY 4.0 (`LICENSE-DATOS.md`).

## Integridad científica
- No inventar resultados, especificaciones, referencias ni datos. Lo no verificado se marca `[VERIFICAR]`.
- Semillas fijas; entornos fijados (`Project.toml`/`Manifest.toml`). No instalar dependencias ni cambiar versiones sin autorización.

## Git
- Ganchos: `git config core.hooksPath .githooks` (una vez por clon). `scripts/check-publication.sh` es idéntico al de pulso-quarto.
- Antes de cada commit: `git status`, `git diff --staged`. Nunca `git add .` ni `git add -A`: añadir por ruta.
- No desactivar ganchos (`--no-verify`) ni el workflow `publication-guard`.
- Commits en español, en imperativo.
