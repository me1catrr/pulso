#!/usr/bin/env bash
# =====================================================================
# check-publication.sh — Guardián de publicación de PULSO
#
# Idéntico en pulso-quarto (privado) y pulso (público). Impide que
# documentación de fabricantes, registros no autorizados, archivos
# sensibles, secretos, rutas locales o identificadores de equipos
# entren en Git o en el sitio Quarto. Derivado del de NeuroRiemann.
#
# Uso:
#   scripts/check-publication.sh [--staged] [--tracked] [--history] [--site DIR]
#   Sin argumentos equivale a --tracked.
#
#   --staged   archivos preparados para commit (gancho pre-commit)
#   --tracked  archivos versionados en el índice
#   --history  todas las rutas, tamaños y contenidos de todo el historial
#   --site DIR árbol renderizado (p. ej. _site) antes de publicar
#
# Lista privada de términos vetados (números de serie, nombres, IPs
# concretas...): NUNCA dentro de un repositorio. Por defecto
# ~/.config/pulso/terminos-vetados.txt, o la ruta de $PULSO_VETADOS.
# Un término por línea; '#' inicia comentario. Si existe, se aplica en
# todos los modos. Con PULSO_REQUIERE_VETADOS=1 su ausencia es un error
# (lo exige check-site.sh antes de publicar). Nunca se imprime el término.
#
# Excepciones de extensión: rutas exactas en scripts/publication-allowlist.txt
# (una por línea, sin comodines). Las rutas privadas no admiten excepciones.
#
# Compatible con bash 3.2 (macOS). Sin dependencias externas.
# Salida: 0 = OK; 1 = violaciones; 2 = error de uso.
# =====================================================================
set -u

MAX_BYTES=$((5 * 1024 * 1024))

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "check-publication: no es un repositorio Git" >&2
  exit 2
}
cd "$ROOT" || exit 2
ALLOWLIST="scripts/publication-allowlist.txt"
VETADOS="${PULSO_VETADOS:-$HOME/.config/pulso/terminos-vetados.txt}"

# Patrones construidos por concatenación para que este archivo no se
# detecte a sí mismo. Nunca se imprime el contenido coincidente (solo
# archivo y línea), para no filtrar secretos en los registros de CI.
P_KEY='-----BEGIN [A-Z ]*PRIV''ATE KEY'
P_GH='gh[pousr]''_[A-Za-z0-9]{36,}'
P_GHPAT='github''_pat_[A-Za-z0-9_]{40,}'
P_AWS='AK''IA[0-9A-Z]{16}'
P_SLACK='xox''[baprs]-[A-Za-z0-9-]{10,}'
P_SK='(^|[^A-Za-z0-9])s''k-[A-Za-z0-9_-]{20,}'
SECRET_RE="$P_KEY|$P_GH|$P_GHPAT|$P_AWS|$P_SLACK|$P_SK"
HOME_RE='/Us''ers/[A-Za-z0-9._-]+/|/ho''me/[a-z][a-z0-9_-]*/'
# Redes de equipos: IPv4 privadas (10/8, 172.16/12, 192.168/16) y direcciones MAC.
O='[0-9]{1,3}'
P_IP="(^|[^0-9.])(1""0\\.$O\\.$O\\.$O|19""2\\.168\\.$O\\.$O|17""2\\.(1[6-9]|2[0-9]|3[01])\\.$O\\.$O)([^0-9.]|\$)"
H='[0-9A-Fa-f]{2}'
P_MAC="(^|[^0-9A-Fa-f:])$H:$H:$H:$H:$H:$H([^0-9A-Fa-f:]|\$)"
NET_RE="$P_IP|$P_MAC"

FAIL=0
fail() { printf '  ✗ %s\n' "$1"; FAIL=1; }

is_allowlisted() {
  [ -f "$ALLOWLIST" ] && grep -qxF -- "$1" "$ALLOWLIST"
}

# Lista privada limpia (sin comentarios ni líneas vacías) en un temporal.
TERMS=""
cleanup() { if [ -n "$TERMS" ]; then rm -f "$TERMS"; fi; }
trap cleanup EXIT
if [ -f "$VETADOS" ]; then
  TERMS=$(mktemp "${TMPDIR:-/tmp}/pulso-vetados.XXXXXX")
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$VETADOS" | grep -v '^$' >"$TERMS"
  [ -s "$TERMS" ] || { rm -f "$TERMS"; TERMS=""; }
fi
if [ -z "$TERMS" ] && [ "${PULSO_REQUIERE_VETADOS:-0}" = 1 ]; then
  echo "check-publication: falta la lista privada de términos vetados ($VETADOS)." >&2
  echo "  Sin ella no se publica. Créala fuera de cualquier repositorio." >&2
  exit 1
fi

# check_path RUTA CONTEXTO [site]
check_path() {
  local p="$1" ctx="$2" mode="${3:-repo}" low base
  low=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  base=${low##*/}

  if [ "$mode" = site ]; then
    case "$low" in
      auditoria/*|*/auditoria/*) fail "$ctx: auditoría privada en el sitio: $p"; return ;;
      sitemap.xml) return ;;   # lo genera Quarto
    esac
  fi

  case "$low" in
    docs/*|*/docs/*|fuentes/*|_notas/*|manuales/*|*/manuales/*|tickets*|*/tickets*|\
    private/*|*/private/*|confidential/*|*/confidential/*|bibliografia-privada/*)
      fail "$ctx: ruta privada: $p"; return ;;
    datos/sinteticos/*) ;;
    data/*|datos/*|raw/*|registros/*|*/registros/*)
      fail "$ctx: datos no publicables: $p"; return ;;
  esac

  case "$base" in
    .env.example) ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|credentials*|\
    secrets*|.netrc|*.secret|*.token|*_private.*|terminos-vetados*)
      fail "$ctx: archivo sensible: $p"; return ;;
    img_[0-9]*|dsc[0-9_]*|captura\ de\ pantalla*|screenshot*|screen\ shot*)
      fail "$ctx: foto o captura sin revisar (renómbrala y regístrala en assets/MANIFEST.tsv): $p"; return ;;
  esac

  # Tres familias: documentación (manuales, artículos, presentaciones de
  # fabricantes), registros y formatos de adquisición, y configuraciones de equipos.
  case "$low" in
    *.pdf|*.epub|*.djvu|*.ps|*.doc|*.docx|*.ppt|*.pptx|*.xls|*.xlsx|*.odt|*.odp|*.ods|\
    *.pages|*.numbers|*.heic|\
    *.mseed|*.miniseed|*.msd|*.seed|*.sac|*.gse|*.gsbu|*.evt|*.sta|*.dat|*.raw|*.bin|\
    *.tdms|*.uff|*.unv|*.mat|*.h5|*.hdf5|*.nc|*.npy|*.npz|*.pkl|*.jld2|*.sqlite|*.db|\
    *.xml|*.cfg|*.conf|*.ini)
      is_allowlisted "$p" || fail "$ctx: extensión no publicable: $p" ;;
  esac
}

check_size() {
  local p="$1" size="$2" ctx="$3"
  if [ -n "$size" ] && [ "$size" -gt "$MAX_BYTES" ]; then
    fail "$ctx: archivo > 5 MB ($size bytes): $p"
  fi
}

# report CONTEXTO MENSAJE <<< "archivo:línea" por línea
report() {
  local ctx="$1" msg="$2" h
  while IFS= read -r h; do [ -n "$h" ] && fail "$ctx: $msg en $h"; done
}

# Busca patrones en el índice (git grep --cached). Argumentos opcionales: rutas.
check_content_index() {
  local ctx="$1"; shift
  report "$ctx" "posible secreto" < <(git grep --cached -I -n -E -e "$SECRET_RE" -- "$@" 2>/dev/null | cut -d: -f1,2)
  report "$ctx" "ruta local absoluta" < <(git grep --cached -I -n -E -e "$HOME_RE" -- "$@" 2>/dev/null | cut -d: -f1,2)
  report "$ctx" "IP privada o MAC" < <(git grep --cached -I -n -E -e "$NET_RE" -- "$@" 2>/dev/null | cut -d: -f1,2)
  if [ -n "$TERMS" ]; then
    report "$ctx" "término vetado" < <(git grep --cached -I -n -i -F -f "$TERMS" -- "$@" 2>/dev/null | cut -d: -f1,2)
  fi
}

run_staged() {
  echo "▸ Archivos preparados (--staged)"
  local files=() f
  while IFS= read -r -d '' f; do
    files+=("$f")
    check_path "$f" staged
    check_size "$f" "$(git cat-file -s ":$f" 2>/dev/null)" staged
  done < <(git diff --cached --name-only -z --diff-filter=ACMR)
  if [ "${#files[@]}" -gt 0 ]; then
    check_content_index staged "${files[@]}"
  fi
}

run_tracked() {
  echo "▸ Archivos versionados (--tracked)"
  local info path sha
  while IFS= read -r -d '' info; do
    path=${info#*$'\t'}
    sha=$(printf '%s' "$info" | cut -d' ' -f2)
    check_path "$path" tracked
    check_size "$path" "$(git cat-file -s "$sha" 2>/dev/null)" tracked
  done < <(git ls-files -s -z)
  check_content_index tracked
}

run_history() {
  echo "▸ Historial completo (--history)"
  git rev-parse --verify -q HEAD >/dev/null || { echo "  (sin commits)"; return; }
  local p line type size rest
  while IFS= read -r p; do
    [ -n "$p" ] && check_path "$p" history
  done < <(git log --all --name-only --format= | sort -u)

  while IFS= read -r line; do
    type=${line%% *}; rest=${line#* }
    size=${rest%% *}; p=${rest#* }
    [ "$type" = blob ] && check_size "$p" "$size" history
  done < <(git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)')

  hist_grep() { git rev-list --all | xargs git grep -I -l "$@" 2>/dev/null | sed 's/^\(.\{12\}\)[^:]*:/\1…:/'; }
  report history "posible secreto" < <(hist_grep -E -e "$SECRET_RE")
  report history "ruta local absoluta" < <(hist_grep -E -e "$HOME_RE"  )
  report history "IP privada o MAC" < <(hist_grep -E -e "$NET_RE"   )
  [ -n "$TERMS" ] && report history "término vetado" < <(hist_grep -i -F -f "$TERMS")
}

run_site() {
  local dir="$1" f rel
  echo "▸ Sitio renderizado (--site $dir)"
  [ -d "$dir" ] || { echo "check-publication: no existe $dir" >&2; exit 2; }
  while IFS= read -r -d '' f; do
    rel=${f#"$dir"/}
    check_path "$rel" site site
    check_size "$rel" "$(wc -c <"$f" | tr -d ' ')" site
  done < <(find "$dir" -type f -print0)
  report site "posible secreto" < <(grep -rIlE -e "$SECRET_RE" "$dir" 2>/dev/null)
  report site "ruta local absoluta" < <(grep -rIlE -e "$HOME_RE"   "$dir" 2>/dev/null)
  report site "IP privada o MAC" < <(grep -rIlE -e "$NET_RE"    "$dir" 2>/dev/null)
  [ -n "$TERMS" ] && report site "término vetado" < <(grep -rIli -F -f "$TERMS" "$dir" 2>/dev/null)
}

[ $# -eq 0 ] && set -- --tracked
while [ $# -gt 0 ]; do
  case "$1" in
    --staged)  run_staged ;;
    --tracked) run_tracked ;;
    --history) run_history ;;
    --site)    [ $# -ge 2 ] || { echo "Uso: --site DIR" >&2; exit 2; }; run_site "$2"; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "check-publication: opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -z "$TERMS" ] && echo "  (aviso: sin lista privada de términos vetados; solo patrones genéricos)"
if [ "$FAIL" -ne 0 ]; then
  echo "✗ check-publication: se han detectado violaciones. Corrige antes de continuar."
  exit 1
fi
echo "✓ check-publication: sin violaciones."
exit 0
