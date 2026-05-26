#!/usr/bin/env bash
#
# Aplatit l'arborescence : déplace récursivement tous les fichiers des
# sous-dossiers vers le dossier cible, puis (optionnellement) supprime
# les sous-dossiers devenus vides.
#
# Résolution du dossier cible, par ordre de priorité :
#   1. @param target_dir         (saisi dans le dialog QuickScript)
#   2. $QS_CONTEXT_TARGET_PATH   (Quick Action « Exécuter ici »)
#   3. $QS_CONTEXT_FILE_PATH     (clic droit sur un unique dossier dans Finder)
#
# Une liste de dossiers sensibles (/ /Users $HOME /Applications …) est
# rejetée pour éviter tout accident.
#
# @param target_dir=              Dossier cible (laisse vide pour utiliser $QS_CONTEXT_TARGET_PATH)
# @param on_conflict=rename       En cas de conflit : rename / skip / overwrite
# @param remove_empty_dirs=oui    Supprimer les sous-dossiers vides après ? (oui/non)
#
set -euo pipefail

target_param="${1:-}"
on_conflict="${2:-rename}"
remove_empty_dirs="${3:-oui}"

# Résolution du dossier cible
target=""
if [[ -n "$target_param" ]]; then
    target="$target_param"
elif [[ -n "${QS_CONTEXT_TARGET_PATH:-}" ]]; then
    target="$QS_CONTEXT_TARGET_PATH"
elif [[ -n "${QS_CONTEXT_FILE_PATH:-}" ]]; then
    # Cas clic droit sur un (ou plusieurs) item dans Finder.
    # On accepte uniquement si un unique dossier est sélectionné.
    file_count=$(printf '%s\n' "$QS_CONTEXT_FILE_PATH" | grep -c .)
    if [[ "$file_count" -eq 1 ]] && [[ -d "$QS_CONTEXT_FILE_PATH" ]]; then
        target="$QS_CONTEXT_FILE_PATH"
    else
        echo "Erreur : sélection multiple ou non-dossier." >&2
        echo "Sélectionne un unique dossier, ou clique droit dans le vide." >&2
        exit 1
    fi
else
    echo "Erreur : aucun dossier cible." >&2
    echo "Lance le script depuis Finder (clic droit sur un dossier ou dans le vide)," >&2
    echo "ou renseigne le paramètre target_dir." >&2
    exit 1
fi

# Expansion du tilde et résolution du chemin absolu
target="${target/#\~/$HOME}"
if ! target=$(cd "$target" 2>/dev/null && pwd -P); then
    echo "Dossier cible introuvable : ${target_param:-$QS_CONTEXT_TARGET_PATH}" >&2
    exit 1
fi

# Garde-fou : refuse les dossiers sensibles. Sans ça, lancer le script sans
# contexte ($PWD=/ quand l'app est lancée par macOS) ferait des dégâts.
forbidden=(
    "/"
    "/Users"
    "/Applications"
    "/System"
    "/Library"
    "/private"
    "/usr"
    "/etc"
    "/var"
    "/bin"
    "/sbin"
    "/opt"
    "$HOME"
)
for f in "${forbidden[@]}"; do
    if [[ "$target" == "$f" ]]; then
        echo "Refus : « $target » est un dossier sensible." >&2
        echo "Choisis un dossier de travail spécifique." >&2
        exit 2
    fi
done

echo "Cible : $target"

moved=0
skipped=0
overwritten=0

# -mindepth 2 : ignore les fichiers déjà à la racine de $target
while IFS= read -r -d '' src; do
    name=$(basename "$src")
    dest="$target/$name"

    if [[ -e "$dest" ]]; then
        case "$on_conflict" in
            skip)
                echo "Existe déjà, ignoré : $name" >&2
                skipped=$((skipped + 1))
                continue
                ;;
            overwrite)
                mv -f "$src" "$dest"
                overwritten=$((overwritten + 1))
                ;;
            rename|*)
                base="${name%.*}"
                ext=""
                [[ "$name" == *.* && "$name" != .* ]] && ext=".${name##*.}"
                n=1
                while [[ -e "$target/${base}-${n}${ext}" ]]; do
                    n=$((n + 1))
                done
                mv "$src" "$target/${base}-${n}${ext}"
                moved=$((moved + 1))
                ;;
        esac
    else
        mv "$src" "$dest"
        moved=$((moved + 1))
    fi
done < <(find "$target" -mindepth 2 -type f -print0)

if [[ "$remove_empty_dirs" == "oui" ]]; then
    find "$target" -mindepth 1 -type d -empty -delete 2>/dev/null || true
fi

echo "Déplacés    : $moved"
[[ "$on_conflict" == "overwrite" ]] && echo "Écrasés     : $overwritten"
[[ "$on_conflict" == "skip" ]] && echo "Ignorés     : $skipped"
