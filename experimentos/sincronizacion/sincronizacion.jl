# Experimento de referencia: sincronización entre dos registradores (PULSO, laboratorio L3).
#
#   julia experimentos/sincronizacion/sincronizacion.jl
#
# Dos registradores miden la misma vibración. El reloj de B adelanta respecto
# al de A un tiempo τ(t) = τ0 + deriva·1e-6·(t0 + t): desfase inicial más deriva
# acumulada desde la última sincronización (t0 segundos antes del registro).
# La muestra que B etiqueta con t se tomó en t − τ, así que B aparece retrasado.
# El retardo se estima con la correlación cruzada y un ajuste parabólico del
# máximo. Salida: fixtures/sincronizacion.json.

include(joinpath(@__DIR__, "..", "comun.jl"))

const FRECUENCIAS = (1.3, 2.9, 4.7, 7.1)     # Hz
const AMPLITUDES = (1.0, 0.7, 0.5, 0.3)      # unidades arbitrarias
const FASES = (0.0, 1.1, 2.3, 0.6)           # rad

"Vibración común a los dos puntos de medida."
function vibracion(t)
    s = 0.0
    for k in 1:4
        s += AMPLITUDES[k] * sin(2 * pi * FRECUENCIAS[k] * t + FASES[k])
    end
    return s
end

"Error de reloj de B (s) en el instante t del registro."
desfase(t; tau0, deriva_ppm, t0) = tau0 + deriva_ppm * 1e-6 * (t0 + t)

"Error de fase (grados) que un retardo τ produce a la frecuencia f."
error_fase(f, tau) = 360 * f * tau

"Registros de A y B: `n` muestras a `fs` Hz, con ruido independiente de desviación `ruido`."
function registros(; fs, n, tau0, deriva_ppm, t0, ruido, semilla)
    g = Generador(semilla)
    a = Vector{Float64}(undef, n)
    b = Vector{Float64}(undef, n)
    for i in 1:n
        t = (i - 1) / fs
        a[i] = vibracion(t) + ruido * normal!(g)
        b[i] = vibracion(t - desfase(t; tau0, deriva_ppm, t0)) + ruido * normal!(g)
    end
    return a, b
end

"""
    retardo_xcorr(a, b, fs, max_muestras)

Retardo de `b` respecto a `a` (s): máximo de r[k] = Σ a[n]·b[n+k] para
|k| ≤ max_muestras, afinado con una parábola por los tres puntos del máximo.
"""
function retardo_xcorr(a, b, fs, max_muestras)
    n = length(a)
    r = Vector{Float64}(undef, 2 * max_muestras + 1)
    for k in -max_muestras:max_muestras
        s = 0.0
        for i in max(1, 1 - k):min(n, n - k)
            s += a[i] * b[i + k]
        end
        r[k + max_muestras + 1] = s
    end
    j = 1
    for i in 2:length(r)
        if r[i] > r[j]
            j = i
        end
    end
    delta = 0.0
    if 1 < j < length(r)
        den = r[j - 1] - 2 * r[j] + r[j + 1]
        if den != 0
            delta = 0.5 * (r[j - 1] - r[j + 1]) / den
        end
    end
    return (j - max_muestras - 1 + delta) / fs
end

function main()
    fs = 100.0
    n = 1024
    max_muestras = 40
    casos = [
        ("sincronizados", (tau0 = 0.0, deriva_ppm = 0.0, t0 = 0.0)),
        ("desfase-3ms", (tau0 = 0.003, deriva_ppm = 0.0, t0 = 0.0)),
        ("desfase-25ms", (tau0 = 0.025, deriva_ppm = 0.0, t0 = 0.0)),
        ("deriva-20ppm-30min", (tau0 = 0.0, deriva_ppm = 20.0, t0 = 1800.0)),
    ]
    resultados = map(casos) do (nombre, p)
        a, b = registros(; fs, n, p..., ruido = 0.05, semilla = 20261110)
        centro = (n - 1) / (2 * fs)
        real = desfase(centro; p...)
        estimado = retardo_xcorr(a, b, fs, max_muestras)
        ["nombre" => nombre,
         "parametros" => ["tau0" => p.tau0, "deriva_ppm" => p.deriva_ppm, "t0" => p.t0],
         "retardo_real" => real, "retardo_estimado" => estimado,
         "error_fase_4_7_hz" => error_fase(4.7, real),
         "a" => a, "b" => b]
    end
    escribir_fixture(joinpath(@__DIR__, "fixtures", "sincronizacion.json"),
        ["experimento" => "sincronizacion",
         "unidades" => "tiempos en s; deriva en ppm; fase en grados",
         "semilla" => 20261110, "fs" => fs, "n" => n, "ruido" => 0.05,
         "max_muestras" => max_muestras, "casos" => resultados])
end

main()
