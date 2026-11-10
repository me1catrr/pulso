# Experimentos de referencia

Cada carpeta contiene un script Julia (solo biblioteca estándar, semilla fija) y el fixture JSON que genera.
Los simuladores del sitio web (en `pulso-quarto`) se comprueban contra estos fixtures.

| Carpeta | Capítulo del sitio | Qué calcula |
|---|---|---|
| `cadena-medida/` | Siemens · cadena de medida | Magnitud física → tensión → cuentas del convertidor: resolución, saturación y error de cuantificación |
| `sincronizacion/` | GeoSIG · tiempo y sincronización | Error de reloj entre dos registradores y su estimación por correlación cruzada |
| `sta-lta/` | GeoSIG · registro y disparo | Cociente STA/LTA clásico, disparos y ventanas con pre y post-evento |

```bash
julia experimentos/cadena-medida/cadena_medida.jl
julia experimentos/sincronizacion/sincronizacion.jl
julia experimentos/sta-lta/sta_lta.jl
```

- `comun.jl` reúne lo que no es científico: el generador pseudoaleatorio (Park-Miller, idéntico en Julia y en
  JavaScript) y la escritura de JSON.
- Los valores de sensores y convertidores son de ejemplo y no describen ningún equipo concreto.
- Cambiar el formato de un fixture obliga a revisar el simulador y la página correspondientes en `pulso-quarto`.
