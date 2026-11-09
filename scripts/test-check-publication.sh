#!/usr/bin/env bash
# =====================================================================
# test-check-publication.sh — Pruebas del guardián de publicación
#
# Crea repositorios temporales en $TMPDIR y comprueba que
# scripts/check-publication.sh bloquea cada caso prohibido y acepta
# los casos legítimos. No toca el repositorio real ni la lista privada
# real de términos vetados (usa una lista ficticia temporal).
# =====================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
GUARD="$HERE/check-publication.sh"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/pulso-guard-test.XXXXXX")
trap 'rm -rf "$BASE"' EXIT

# Nunca la lista real durante las pruebas
export PULSO_VETADOS="$BASE/sin-lista.txt"
unset PULSO_REQUIERE_VETADOS

PASS=0; FAILS=0
G() { git -c core.hooksPath=/dev/null -c commit.gpgsign=false \
          -c user.name=test -c user.email=test@example.invalid "$@"; }

new_repo() {
  local d="$BASE/$1"
  mkdir -p "$d/scripts" && cp "$GUARD" "$d/scripts/" && cd "$d" && G init -q -b main
  G add scripts/check-publication.sh
}

# expect <ok|fail> <descripción> <argumentos del guardián...>
expect() {
  local want="$1" desc="$2"; shift 2
  local got=fail
  bash scripts/check-publication.sh "$@" >/dev/null 2>&1 && got=ok
  if [ "$got" = "$want" ]; then
    printf '  ✓ %s\n' "$desc"; PASS=$((PASS + 1))
  else
    printf '  ✗ %s (esperado %s, obtenido %s)\n' "$desc" "$want" "$got"; FAILS=$((FAILS + 1))
  fi
}

FAKE_TOKEN="gh""p_$(printf 'a%.0s' $(seq 1 36))"
FAKE_HOME="$(printf '/%s/%s/proyecto' Users alguien)"
FAKE_IP="$(printf '%s.%s.%s.%s' 192 168 7 42)"
FAKE_MAC="$(printf '%s:%s:%s:%s:%s:%s' 00 1a 2b 3c 4d 5e)"
FAKE_SERIE="ZZ-SERIE-999001"

echo "▸ Pruebas de check-publication.sh"

new_repo clean
echo "# ok" > README.md; G add README.md
expect ok   "repositorio limpio aceptado" --staged

new_repo version
echo "Quarto 1.10.19, firmware 2.3.1, IP pública 8.8.8.8" > notas.md; G add notas.md
expect ok   "números de versión e IP pública no se confunden con IP privada" --staged

new_repo manual
mkdir equipos && echo x > equipos/GS_GMSplus_UserManual.pdf; G add -f equipos/GS_GMSplus_UserManual.pdf
expect fail "manual del fabricante (.pdf) bloqueado" --staged

new_repo keynote
echo x > guia.key; G add -f guia.key
expect fail "presentación Keynote (.key) bloqueada" --staged

new_repo fuentes
mkdir fuentes && echo x > fuentes/notas.md; G add -f fuentes/notas.md
expect fail "cualquier archivo en fuentes/ bloqueado" --staged

new_repo mseed
echo x > GS1.mseed; G add -f GS1.mseed
expect fail "registro miniSEED bloqueado" --staged

new_repo xml
echo "<a/>" > GS1.xml; G add -f GS1.xml
expect fail "configuración XML bloqueada" --staged

new_repo xml_allow
mkdir -p experimentos/sinc && echo "<a/>" > experimentos/sinc/ejemplo.xml
echo "experimentos/sinc/ejemplo.xml" > scripts/publication-allowlist.txt
G add -f experimentos/sinc/ejemplo.xml scripts/publication-allowlist.txt
expect ok   "XML revisado en lista de excepciones aceptado" --staged

new_repo datos
mkdir -p datos/reales && echo "t,a" > datos/reales/gs1.csv; G add -f datos/reales/gs1.csv
expect fail "datos/ no sintéticos bloqueados" --staged

new_repo sinteticos
mkdir -p datos/sinteticos && echo "t,a" > datos/sinteticos/cadena.csv; G add -f datos/sinteticos/cadena.csv
expect ok   "datos/sinteticos/ aceptado" --staged

new_repo foto
mkdir fig && echo x > fig/IMG_8388.jpg; G add -f fig/IMG_8388.jpg
expect fail "foto sin renombrar (IMG_*) bloqueada" --staged

new_repo captura
echo x > "Captura de pantalla 2024-11-22.png"; G add -f "Captura de pantalla 2024-11-22.png"
expect fail "captura de pantalla sin revisar bloqueada" --staged

new_repo ip
echo "estación en $FAKE_IP" > notas.md; G add notas.md
expect fail "IP privada bloqueada" --staged

new_repo mac
echo "mac $FAKE_MAC" > notas.md; G add notas.md
expect fail "dirección MAC bloqueada" --staged

new_repo token
echo "token=$FAKE_TOKEN" > notas.txt; G add notas.txt
expect fail "token de GitHub bloqueado" --staged

new_repo pkey
printf -- '-----BEGIN RSA %s KEY-----\nabc\n' "PRIVATE" > clave.txt; G add clave.txt
expect fail "clave privada bloqueada" --staged

new_repo home
echo "ver $FAKE_HOME/x" > notas.md; G add notas.md
expect fail "ruta local absoluta bloqueada" --staged

new_repo vetado
printf '# lista ficticia\n\n%s\n' "$FAKE_SERIE" > "$BASE/vetados.txt"
echo "equipo $FAKE_SERIE instalado" > notas.md; G add notas.md
expect ok   "sin lista privada, el término específico no se conoce" --staged
PULSO_VETADOS="$BASE/vetados.txt" expect fail "término de la lista privada bloqueado" --staged
echo "equipo GS1 instalado" > notas.md; G add notas.md
PULSO_VETADOS="$BASE/vetados.txt" expect ok "alias GS1 aceptado con lista privada" --staged
PULSO_REQUIERE_VETADOS=1 expect fail "lista privada exigida y ausente: falla" --staged

new_repo env
echo "A=1" > .env; G add -f .env
expect fail ".env bloqueado" --staged

new_repo big
dd if=/dev/zero of=grande.png bs=1048576 count=6 2>/dev/null; G add grande.png
expect fail "archivo > 5 MB bloqueado" --staged

new_repo hist_ip
echo "ip $FAKE_IP" > n.md; G add n.md; G commit -q -m "error"
echo "limpio" > n.md; G add n.md; G commit -q -m "limpieza"
expect ok   "IP retirada: --tracked limpio" --tracked
expect fail "IP retirada: --history la detecta" --history

new_repo history
mkdir docs && echo x > docs/a.pdf; G add -f docs/a.pdf; G commit -q -m "error"
G rm -q --cached docs/a.pdf; G commit -q -m "retirada"
expect ok   "historial: --tracked limpio tras retirar" --tracked
expect fail "historial: --history detecta docs/ pasado" --history

new_repo site
mkdir -p _site/auditoria && echo x > _site/auditoria/geosig-xml.html
expect fail "sitio con auditoria/ bloqueado" --site _site
mkdir -p _site2 && echo "<p>ok</p>" > _site2/index.html && echo "<urlset/>" > _site2/sitemap.xml
expect ok   "sitio limpio con sitemap.xml aceptado" --site _site2
mkdir -p _site3 && echo "<p>$FAKE_IP</p>" > _site3/index.html
expect fail "sitio con IP privada bloqueado" --site _site3
mkdir -p _site4 && echo "<p>$FAKE_SERIE</p>" > _site4/index.html
PULSO_VETADOS="$BASE/vetados.txt" expect fail "sitio con término vetado bloqueado" --site _site4

echo "Resultado: $PASS correctas, $FAILS fallidas."
[ "$FAILS" -eq 0 ]
