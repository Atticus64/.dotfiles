#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/devel"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

has_config() {
    local dir="$1"
    [ -f "$dir/package.json" ]       && return 0
    [ -f "$dir/Cargo.toml" ]         && return 0
    [ -f "$dir/go.mod" ]             && return 0
    [ -f "$dir/mix.exs" ]            && return 0
    [ -f "$dir/CMakeLists.txt" ]     && return 0
    [ -f "$dir/Makefile" ]           && return 0
    [ -f "$dir/setup.py" ]           && return 0
    [ -f "$dir/pyproject.toml" ]     && return 0
    [ -f "$dir/Package.swift" ]      && return 0
    [ -f "$dir/deno.json" ]          && return 0
    [ -f "$dir/deno.jsonc" ]         && return 0
    [ -f "$dir/Dockerfile" ]         && return 0
    [ -f "$dir/docker-compose.yml" ] && return 0
    [ -f "$dir/requirements.txt" ]   && return 0
    find "$dir" -maxdepth 1 -name "*.csproj" -print -quit 2>/dev/null | grep -q . && return 0
    find "$dir" -maxdepth 1 -name "*.sln"    -print -quit 2>/dev/null | grep -q . && return 0
    find "$dir" -maxdepth 1 -name "*.iml"    -print -quit 2>/dev/null | grep -q . && return 0
    [ -f "$dir/.project" ] && return 0
    return 1
}

has_source() {
    local dir="$1"
    for ext in py js ts tsx jsx go rs c cpp cxx hpp java swift cs lisp el ex s asm; do
        find "$dir" -maxdepth 1 -name "*.$ext" -print -quit 2>/dev/null | grep -q . && return 0
    done
    return 1
}

is_likely_project_dir() {
    local name="$1"
    case "$name" in
        src|app|lib|tests|test|docs|scripts|build|dist|public|assets|resources|config) return 1 ;;
        pages|routes|components|hooks|utils|helpers|types|styles|css|images) return 1 ;;
        include|source|static|db|out|obj|bin|migrations|seeds|data) return 1 ;;
        *) return 0 ;;
    esac
}

depth_from() {
    local path="$1"
    local base="$2"
    local rel="${path#$base/}"
    if [ "$rel" = "$path" ]; then
        echo 0
        return
    fi
    echo "$rel" | tr '/' '\n' | wc -l
}

# Check if any ancestor directory has a project config file
has_parent_with_config() {
    local dir="$1"
    local check="$dir"
    while true; do
        check=$(dirname "$check")
        [ "$check" == "/" ] && return 1
        [ "$check" == "$BASE" ] && return 1
        has_config "$check" && return 0
    done
}

# ---------------------------------------------------------------------------
# Language detection
# ---------------------------------------------------------------------------

detect_language() {
    local dir="$1"

    [ -f "$dir/Cargo.toml" ]       && echo "Rust"     && return
    [ -f "$dir/go.mod" ]           && echo "Go"       && return
    [ -f "$dir/mix.exs" ]          && echo "Elixir"   && return
    [ -f "$dir/Package.swift" ]    && echo "Swift"    && return
    [ -f "$dir/deno.json" ]        && echo "TypeScript" && return
    [ -f "$dir/deno.jsonc" ]       && echo "TypeScript" && return

    if [ -f "$dir/package.json" ]; then
        if grep -qi '"typescript' "$dir/package.json" 2>/dev/null || \
           [ -f "$dir/tsconfig.json" ]; then
            echo "TypeScript"
        else
            echo "JavaScript"
        fi
        return
    fi

    [ -f "$dir/pyproject.toml" ]     && echo "Python" && return
    [ -f "$dir/setup.py" ]           && echo "Python" && return
    [ -f "$dir/CMakeLists.txt" ]     && echo "C++"    && return
    [ -f "$dir/requirements.txt" ]   && echo "Python" && return

    find "$dir" -maxdepth 1 -name "*.csproj" -print -quit 2>/dev/null | grep -q . && echo "C#" && return
    find "$dir" -maxdepth 1 -name "*.sln"    -print -quit 2>/dev/null | grep -q . && echo "C#" && return

    for ext_pair in \
        "go:Go" "rs:Rust" "py:Python" "ts:TypeScript" "tsx:TypeScript" \
        "js:JavaScript" "jsx:JavaScript" "java:Java" \
        "cpp:C++" "cxx:C++" "hpp:C++" "c:C" \
        "swift:Swift" "cs:C#" "lisp:Lisp" "el:Emacs Lisp" \
        "ex:Elixir" "s:Assembly" "asm:Assembly"; do
        ext="${ext_pair%%:*}"
        lang="${ext_pair##*:}"
        find "$dir" -maxdepth 1 -name "*.$ext" -print -quit 2>/dev/null | grep -q . && echo "$lang" && return
    done

    echo "Unknown"
}

# ---------------------------------------------------------------------------
# Project discovery
# ---------------------------------------------------------------------------

EXCLUDE_PATHS=(
    '-not' '-path' '*/\.*'
    '-not' '-path' '*/node_modules'
    '-not' '-path' '*/node_modules/*'
    '-not' '-path' '*/build/*'
    '-not' '-path' '*/target/*'
    '-not' '-path' '*/__pycache__/*'
    '-not' '-path' '*/.venv/*'
    '-not' '-path' '*/vendor/*'
    '-not' '-path' '*/dist/*'
    '-not' '-path' '*/.git/*'
)

scan_and_filter() {
    local scan_root="$1"
    local max_source_depth="$2"
    local max_scan_depth="$3"
    shift 3

    local -a candidates=()
    local -A is_cand=()

    while IFS= read -r -d '' subdir; do
        # Config-based: always a project at any depth
        if has_config "$subdir"; then
            candidates+=("$subdir")
            is_cand["$subdir"]=1
            continue
        fi

        local depth
        depth=$(depth_from "$subdir" "$scan_root")

        # Source-only: only at shallow depths
        if [ "$depth" -le "$max_source_depth" ]; then
            if has_source "$subdir"; then
                local name
                name=$(basename "$subdir")
                if is_likely_project_dir "$name" || [ "$depth" -eq 1 ]; then
                    if ! has_parent_with_config "$subdir"; then
                        candidates+=("$subdir")
                        is_cand["$subdir"]=1
                    fi
                fi
            fi
        fi
    done < <(find "$scan_root" -mindepth 1 -maxdepth "$max_scan_depth" -type d \
        "${EXCLUDE_PATHS[@]}" \
        -print0 2>/dev/null)

    # Ancestor filter: skip if any ancestor is also a candidate
    for cand in "${candidates[@]}"; do
        local check="$cand"
        local skip=0
        while true; do
            check=$(dirname "$check")
            [ "$check" == "/" ] && break
            [ "$check" == "$scan_root" ] && break
            if [[ -n "${is_cand[$check]:-}" ]]; then
                skip=1
                break
            fi
        done
        [ "$skip" -eq 0 ] && echo "$cand"
    done
}

find_projects_in_category() {
    local cat_dir="$1"
    while IFS= read -r proj_path; do
        local lang
        lang=$(detect_language "$proj_path")
        local name
        name=$(basename "$proj_path")
        local rel
        rel="${proj_path#$cat_dir/}"
        echo "$lang|$name|$rel|$proj_path"
    done < <(scan_and_filter "$cat_dir" 2 4)
}

find_projects_in_lang() {
    local lang_dir="$1"
    while IFS= read -r proj_path; do
        local name
        name=$(basename "$proj_path")
        local rel
        rel="${proj_path#$lang_dir/}"
        echo "$name|$rel|$proj_path"
    done < <(scan_and_filter "$lang_dir" 2 3)
}

# ---------------------------------------------------------------------------
# Rofi menus
# ---------------------------------------------------------------------------

ROFI_THEME="$HOME/.config/rofi/catppuccin-latte.rasi"

rofi_prompt() {
    local prompt="$1"
    local -n _display="$2"
    local -n _values="$3"
    local matching="${4:-normal}"
    local out
    if [[ "$XDG_CURRENT_DESKTOP" == "GNOME" ]]; then
        out=$(printf '%s\n' "${_display[@]}" | WAYLAND_DISPLAY= rofi -dmenu -p "$prompt" -i -matching "$matching" -theme "$ROFI_THEME")
    else
        out=$(printf '%s\n' "${_display[@]}" | rofi -dmenu -p "$prompt" -i -matching "$matching" -theme "$ROFI_THEME")
    fi
    [ -z "$out" ] && echo "" && return
    local idx=0
    for i in "${!_display[@]}"; do
        if [ "${_display[$i]}" = "$out" ]; then
            idx=$i
            break
        fi
    done
    echo "${_values[$idx]}"
}

confirm_cancel() {
    local -a display=("Sí, salir" "No, continuar")
    local -a values=("exit" "back")
    local choice
    choice=$(rofi_prompt "¿Cancelar?" display values)
    [ "$choice" = "exit" ] && exit 0
}

# ---------------------------------------------------------------------------
# Level 1 – Category
# ---------------------------------------------------------------------------

choose_category() {
    while true; do
        local -a display=()
        local -a values=()
        display+=("󰢷  Search all    Fuzzy search every project"); values+=("search_all")
        display+=("󰚰  experiments    Prototypes & experiments"); values+=("experiments")
        display+=("󰌠  langs         Learning / practice by language"); values+=("langs")
        display+=("󰡭  polyglot      Same program in multiple languages"); values+=("polyglot")
        display+=("󰂖  projects      Main projects"); values+=("projects")
        display+=("󰆨  university    University coursework"); values+=("university")

        local sel
        sel=$(rofi_prompt "Categoria" display values)
        [ -n "$sel" ] && echo "$sel" && return
        confirm_cancel
    done
}

# ---------------------------------------------------------------------------
# Level 2 – Language (for langs category)
# ---------------------------------------------------------------------------

choose_language() {
    while true; do
        local -a display=()
        local -a values=()
        for lang_dir in "$BASE/langs/"*/; do
            [ -d "$lang_dir" ] || continue
            local lang
            lang=$(basename "$lang_dir")
            display+=("$lang")
            values+=("$lang_dir")
        done

        local sel
        sel=$(rofi_prompt "Lenguaje" display values)
        [ -n "$sel" ] && echo "$sel" && return
        confirm_cancel
    done
}

# ---------------------------------------------------------------------------
# Level 2/3 – Choose project
# ---------------------------------------------------------------------------

choose_project_in_category() {
    local cat_name="$1"
    local cat_dir="$BASE/$cat_name"

    while true; do
        local -a display=()
        local -a values=()

        while IFS='|' read -r lang name rel path; do
            [ -z "$path" ] && continue
            display+=("$lang  ─  $name")
            values+=("$path")
        done < <(find_projects_in_category "$cat_dir" | sort -t'|' -k1,1 -k2,2)

        if [ ${#display[@]} -eq 0 ]; then
            echo "No se encontraron proyectos en $cat_name"
            exit 1
        fi

        local sel
        sel=$(rofi_prompt "Proyecto" display values)
        [ -n "$sel" ] && echo "$sel" && return
        confirm_cancel
    done
}

choose_project_in_lang() {
    local lang_dir="$1"
    local lang_name
    lang_name=$(basename "$lang_dir")

    while true; do
        local -a display=()
        local -a values=()

        while IFS='|' read -r name rel path; do
            [ -z "$path" ] && continue
            display+=("$rel")
            values+=("$path")
        done < <(find_projects_in_lang "$lang_dir" | sort -t'|' -k2,2)

        if [ ${#display[@]} -eq 0 ]; then
            echo "No se encontraron proyectos en $lang_name"
            exit 1
        fi

        local sel
        sel=$(rofi_prompt "$lang_name" display values)
        [ -n "$sel" ] && echo "$sel" && return
        confirm_cancel
    done
}

# ---------------------------------------------------------------------------
# Level 3/4 – Editor
# ---------------------------------------------------------------------------

choose_editor() {
    local proj_path="$1"

    while true; do
        local -a display=()
        local -a values=()
        display+=("󰨞  VSCode     code"); values+=("code")
        display+=("  Neovim     nvim"); values+=("nvim")
        display+=("󰧨  Zed        zed");   values+=("zed")

        local cmd
        cmd=$(rofi_prompt "Abrir con" display values)
        if [ -z "$cmd" ]; then
            confirm_cancel
            continue
        fi

        case "$cmd" in
            code) "$cmd" "$proj_path" ;;
            nvim) "$cmd" "$proj_path" ;;
            zed)  "$cmd" "$proj_path" ;;
            *)    "$cmd" "$proj_path" ;;
        esac
        return
    done
}

# ---------------------------------------------------------------------------
# Level 2 – Search all (fuzzy across every category)
# ---------------------------------------------------------------------------

search_all_projects() {
    local -a display=()
    local -a values=()

    # Categories with flat project listing
    for cat in experiments polyglot projects university; do
        local cat_dir="$BASE/$cat"
        [ -d "$cat_dir" ] || continue
        while IFS='|' read -r lang name rel path; do
            [ -z "$path" ] && continue
            display+=("$cat  │  $name  ($lang)")
            values+=("$path")
        done < <(find_projects_in_category "$cat_dir" | sort -t'|' -k1,1 -k2,2)
    done

    # langs category has an extra level (language subdirectories)
    for lang_dir in "$BASE/langs/"*/; do
        [ -d "$lang_dir" ] || continue
        local lang_name
        lang_name=$(basename "$lang_dir")
        while IFS='|' read -r name rel path; do
            [ -z "$path" ] && continue
            display+=("langs/$lang_name  │  $name")
            values+=("$path")
        done < <(find_projects_in_lang "$lang_dir" | sort -t'|' -k2,2)
    done

    if [ ${#display[@]} -eq 0 ]; then
        echo "No se encontraron proyectos"
        exit 1
    fi

    while true; do
        local sel
        sel=$(rofi_prompt "Buscar" display values "fuzzy")
        [ -n "$sel" ] && echo "$sel" && return
        confirm_cancel
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local category
    category=$(choose_category)
    [ -z "$category" ] && exit 0

    if [ "$category" = "langs" ]; then
        local lang_dir
        lang_dir=$(choose_language)
        [ -z "$lang_dir" ] && exit 0
        local proj_path
        proj_path=$(choose_project_in_lang "$lang_dir")
        [ -z "$proj_path" ] && exit 0
        choose_editor "$proj_path"
    elif [ "$category" = "search_all" ]; then
        local proj_path
        proj_path=$(search_all_projects)
        [ -z "$proj_path" ] && exit 0
        choose_editor "$proj_path"
    else
        local proj_path
        proj_path=$(choose_project_in_category "$category")
        [ -z "$proj_path" ] && exit 0
        choose_editor "$proj_path"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
