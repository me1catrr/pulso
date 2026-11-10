# Experimento de referencia: disparo STA/LTA (PULSO, laboratorio L4).
#
#   julia experimentos/sta-lta/sta_lta.jl
#
# STA/LTA clásico sobre la energía de la señal (x²): cociente entre la media de
# una ventana corta (STA) y la de una larga (LTA), ambas terminadas en la
# muestra actual. El cociente vale 0 hasta que la ventana larga está completa.
# El disparo se activa al superar `umbral_on` y se desactiva al bajar de
# `umbral_off`; cada disparo se guarda con su pre-evento y su post-evento.
# Salida: fixtures/sta-lta.json (índices de muestra contados desde 0).

include(joinpath(@__DIR__, "..", "comun.jl"))

"Cociente STA/LTA clásico; `nsta` y `nlta` en muestras."
function sta_lta(x::Vector{Float64}, nsta::Int, nlta::Int)
    n = length(x)
    cociente = zeros(n)
    suma_sta = 0.0
    suma_lta = 0.0
    for i in 1:n
        e = x[i]^2
        suma_sta += e
        suma_lta += e
        if i > nsta
            suma_sta -= x[i - nsta]^2
        end
        if i > nlta
            suma_lta -= x[i - nlta]^2
        end
        if i >= nlta && suma_lta > 0
            cociente[i] = (suma_sta / nsta) / (suma_lta / nlta)
        end
    end
    return cociente
end

"Disparos como pares (inicio, fin) de índices contados desde 0."
function disparos(cociente, umbral_on, umbral_off)
    pares = Vector{Vector{Int}}()
    activo = false
    inicio = 0
    for i in eachindex(cociente)
        if !activo && cociente[i] > umbral_on
            activo = true
            inicio = i - 1
        elseif activo && cociente[i] < umbral_off
            activo = false
            push!(pares, [inicio, i - 1])
        end
    end
    activo && push!(pares, [inicio, length(cociente) - 1])
    return pares
end

"Ventanas guardadas: cada disparo con su pre y post-evento (en muestras), fusionando solapes."
function ventanas(pares, npre, npost, n)
    v = Vector{Vector{Int}}()
    for (a, b) in pares
        ini = max(0, a - npre)
        fin = min(n - 1, b + npost)
        if !isempty(v) && ini <= v[end][2]
            v[end][2] = max(v[end][2], fin)
        else
            push!(v, [ini, fin])
        end
    end
    return v
end

"Ruido normal más transitorios amortiguados: (instante s, amplitud, frecuencia Hz, constante de tiempo s)."
function senal(; fs, n, ruido, eventos, semilla)
    g = Generador(semilla)
    x = Vector{Float64}(undef, n)
    for i in 1:n
        t = (i - 1) / fs
        s = ruido * normal!(g)
        for (t0, amplitud, f, tau) in eventos
            if t >= t0
                s += amplitud * exp(-(t - t0) / tau) * sin(2 * pi * f * (t - t0))
            end
        end
        x[i] = s
    end
    return x
end

function main()
    fs = 100.0
    n = 3000
    eventos = [(10.0, 0.6, 4.0, 0.8), (20.0, 0.15, 4.0, 0.8)]
    x = senal(; fs, n, ruido = 0.05, eventos, semilla = 20261110)
    casos = [
        ("referencia", (sta = 0.5, lta = 5.0, umbral_on = 4.0, umbral_off = 1.5, pre = 2.0, post = 3.0)),
        ("umbral-bajo", (sta = 0.5, lta = 5.0, umbral_on = 2.5, umbral_off = 1.5, pre = 2.0, post = 3.0)),
        ("sta-larga", (sta = 2.0, lta = 5.0, umbral_on = 4.0, umbral_off = 1.5, pre = 2.0, post = 3.0)),
    ]
    resultados = map(casos) do (nombre, p)
        nsta = round(Int, p.sta * fs)
        nlta = round(Int, p.lta * fs)
        c = sta_lta(x, nsta, nlta)
        d = disparos(c, p.umbral_on, p.umbral_off)
        v = ventanas(d, round(Int, p.pre * fs), round(Int, p.post * fs), n)
        ["nombre" => nombre,
         "parametros" => ["sta" => p.sta, "lta" => p.lta, "umbral_on" => p.umbral_on,
                          "umbral_off" => p.umbral_off, "pre" => p.pre, "post" => p.post],
         "cociente_maximo" => maximum(c), "disparos" => d, "ventanas" => v, "cociente" => c]
    end
    escribir_fixture(joinpath(@__DIR__, "fixtures", "sta-lta.json"),
        ["experimento" => "sta-lta",
         "unidades" => "amplitud en mg; tiempos en s; índices de muestra desde 0",
         "semilla" => 20261110, "fs" => fs, "n" => n, "ruido" => 0.05,
         "eventos" => [[e...] for e in eventos], "x" => x, "casos" => resultados])
end

main()
