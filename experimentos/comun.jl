# Utilidades comunes de los experimentos de PULSO (solo biblioteca estándar de Julia).
#
# No son funciones científicas: un generador pseudoaleatorio reproducible en
# cualquier lenguaje y la escritura de fixtures en JSON. Los simuladores OJS de
# pulso-quarto implementan el mismo generador para poder compararse con estos
# resultados.

"""
Generador congruencial de Park-Miller: x ← 16807·x mod (2^31 − 1).

Todos los productos caben en 53 bits, así que la secuencia es idéntica en
Julia (Int64) y en JavaScript (Number).
"""
mutable struct Generador
    x::Int64
end

const MODULO = 2147483647

"Número uniforme en (0, 1)."
function uniforme!(g::Generador)
    g.x = (16807 * g.x) % MODULO
    return g.x / MODULO
end

"Número normal estándar (Box-Muller; consume dos uniformes)."
function normal!(g::Generador)
    u1 = uniforme!(g)
    u2 = uniforme!(g)
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2)
end

# ---------------------------------------------------------------------------
# JSON mínimo. Un objeto se escribe como vector de pares, para fijar el orden.
# ---------------------------------------------------------------------------
json(io::IO, x::Bool) = print(io, x ? "true" : "false")
json(io::IO, x::Integer) = print(io, x)
function json(io::IO, x::AbstractFloat)
    isfinite(x) || error("valor no finito en un fixture")
    print(io, repr(Float64(x)))
end
function json(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        c == '"' ? print(io, "\\\"") : c == '\\' ? print(io, "\\\\") : c == '\n' ? print(io, "\\n") : print(io, c)
    end
    print(io, '"')
end
function json(io::IO, obj::AbstractVector{<:Pair})
    print(io, '{')
    for (i, (clave, valor)) in enumerate(obj)
        i > 1 && print(io, ',')
        json(io, String(clave))
        print(io, ':')
        json(io, valor)
    end
    print(io, '}')
end
function json(io::IO, v::Union{AbstractVector,Tuple})
    print(io, '[')
    for (i, x) in enumerate(v)
        i > 1 && print(io, ',')
        json(io, x)
    end
    print(io, ']')
end

"Escribe `datos` en `ruta` (crea la carpeta si no existe)."
function escribir_fixture(ruta::AbstractString, datos)
    mkpath(dirname(ruta))
    open(ruta, "w") do io
        json(io, datos)
        println(io)
    end
    println("✓ ", relpath(ruta, dirname(@__DIR__)))
end
