# Experimento de referencia: cadena de medida (PULSO, laboratorio L1).
#
#   julia experimentos/cadena-medida/cadena_medida.jl
#
# Modelo: magnitud física → tensión del sensor → ganancia → convertidor A/D
# (rango ±vfs, `bits` bits, con saturación) → cuentas → magnitud reconstruida.
# Los valores del sensor y del convertidor son de ejemplo: no describen ningún
# equipo concreto. Salida: fixtures/cadena-medida.json.

include(joinpath(@__DIR__, "..", "comun.jl"))

"""
    cadena(x; sensibilidad, ganancia, vfs, bits)

`x` en unidades físicas (aquí, g); `sensibilidad` en V por unidad física;
`vfs` es el fondo de escala del convertidor en V (rango ±vfs).
Devuelve las cuentas, la señal reconstruida y las métricas de la cadena.
"""
function cadena(x::Vector{Float64}; sensibilidad, ganancia, vfs, bits)
    lsb_v = 2 * vfs / 2^bits                    # V por cuenta
    cmax = 2^(bits - 1) - 1
    cmin = -2^(bits - 1)
    lsb = lsb_v / (sensibilidad * ganancia)     # unidades físicas por cuenta
    fondo = vfs / (sensibilidad * ganancia)     # fondo de escala en unidades físicas

    n = length(x)
    cuentas = Vector{Int}(undef, n)
    y = Vector{Float64}(undef, n)
    saturadas = 0
    pico = 0.0
    suma2 = 0.0
    for i in 1:n
        v = x[i] * sensibilidad * ganancia
        c = floor(Int, v / lsb_v + 0.5)         # redondeo al más cercano
        if c > cmax
            c = cmax
            saturadas += 1
        elseif c < cmin
            c = cmin
            saturadas += 1
        end
        cuentas[i] = c
        y[i] = c * lsb
        pico = max(pico, abs(x[i]))
        suma2 += (y[i] - x[i])^2
    end
    return (; cuentas, y, lsb, fondo, pico,
            uso_escala = pico / fondo,
            fraccion_saturada = saturadas / n,
            error_rms = sqrt(suma2 / n),
            error_teorico = lsb / sqrt(12))
end

"Señal de ejemplo en g: dos armónicos y ruido normal (semilla fija)."
function senal(; fs = 200.0, n = 400, semilla = 20261110)
    g = Generador(semilla)
    x = Vector{Float64}(undef, n)
    for i in 1:n
        t = (i - 1) / fs
        x[i] = 0.02 * sin(2 * pi * 2.5 * t) + 0.005 * sin(2 * pi * 11.0 * t) + 0.0005 * normal!(g)
    end
    return x
end

function main()
    fs = 200.0
    x = senal(; fs)
    casos = [
        ("holgado", (sensibilidad = 10.0, ganancia = 1, vfs = 10.0, bits = 24)),
        ("saturado", (sensibilidad = 10.0, ganancia = 100, vfs = 10.0, bits = 24)),
        ("pocos-bits", (sensibilidad = 10.0, ganancia = 1, vfs = 10.0, bits = 12)),
        ("ganancia-ajustada", (sensibilidad = 10.0, ganancia = 32, vfs = 10.0, bits = 12)),
    ]
    resultados = map(casos) do (nombre, p)
        r = cadena(x; p...)
        ["nombre" => nombre,
         "parametros" => ["sensibilidad" => p.sensibilidad, "ganancia" => p.ganancia,
                          "vfs" => p.vfs, "bits" => p.bits],
         "lsb" => r.lsb, "fondo" => r.fondo, "pico" => r.pico, "uso_escala" => r.uso_escala,
         "fraccion_saturada" => r.fraccion_saturada,
         "error_rms" => r.error_rms, "error_teorico" => r.error_teorico,
         "cuentas" => r.cuentas]
    end
    escribir_fixture(joinpath(@__DIR__, "fixtures", "cadena-medida.json"),
        ["experimento" => "cadena-medida",
         "unidades" => "g; sensibilidad en V/g; vfs en V",
         "semilla" => 20261110, "fs" => fs, "x" => x, "casos" => resultados])
end

main()
