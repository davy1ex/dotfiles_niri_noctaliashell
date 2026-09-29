#!/usr/bin/env bash
#
# install.sh — раскладывает конфиги niri + Noctalia из этого репозитория
# симлинками. Идемпотентен: можно запускать сколько угодно раз.
#
#   ./install.sh                 связать конфиги и перезагрузить сессию
#   ./install.sh -n              --dry-run, только показать что будет сделано
#   ./install.sh -N              связать, но не перезагружать niri/noctalia
#   ./install.sh -p              дополнительно поставить пакеты из packages.txt
#
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-backup"

DRY_RUN=0
DO_RELOAD=1
DO_PACKAGES=0

if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
    C_SKIP=$'\033[90m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_SKIP=""; C_B=""; C_0=""
fi

ok()   { printf '  %s✓%s %s\n' "$C_OK"   "$C_0" "$*"; }
skip() { printf '  %s·%s %s\n' "$C_SKIP" "$C_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_0" "$*" >&2; }
die()  { printf '%sошибка:%s %s\n' "$C_ERR" "$C_0" "$*" >&2; exit 1; }

run() {
    if (( DRY_RUN )); then
        printf '  %s[dry-run]%s %s\n' "$C_SKIP" "$C_0" "$*"
    else
        "$@"
    fi
}

# Сообщение об успехе — в dry-run тоже помечаем, чтобы не вводить в заблуждение.
done_msg() {
    if (( DRY_RUN )); then
        printf '  %s[dry-run]%s %s\n' "$C_SKIP" "$C_0" "$*"
    else
        ok "$*"
    fi
}

usage() {
    cat <<EOF
Использование: ${0##*/} [опции]

  -n, --dry-run     показать действия, ничего не менять
  -N, --no-reload   не перезагружать niri и noctalia после раскладки
  -p, --packages    поставить пакеты из packages.txt (нужен pacman + sudo)
  -h, --help        эта справка
EOF
}

while (( $# )); do
    case "$1" in
        -n|--dry-run)   DRY_RUN=1 ;;
        -N|--no-reload) DO_RELOAD=0 ;;
        -p|--packages)  DO_PACKAGES=1 ;;
        -h|--help)      usage; exit 0 ;;
        *)              printf 'неизвестный аргумент: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ── что куда раскладываем ───────────────────────────────────────────────
# Формат: <путь внутри репо>|<путь в домашке>
# Порядок важен: сначала каталоги, затем файлы внутри них.
LINKS=(
    "config/niri|$HOME/.config/niri"
    "config/noctalia|$HOME/.config/noctalia"
    "config/environment.d/98-qt-platformtheme.conf|$HOME/.config/environment.d/98-qt-platformtheme.conf"
    "local/share/noctalia/plugins/niri-windows|$HOME/.local/share/noctalia/plugins/niri-windows"
    "local/bin/toggle-kb-layout|$HOME/.local/bin/toggle-kb-layout"
)

BACKUP_DIR=""

# Копирует существующий цель в $BACKUP_DIR, сохраняя путь, если это возможно.
backup_existing() {
    local src="$1" dst="$2" rel="$3"
    dst="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname -- "$dst")"
    if [[ -e "$dst" || -L "$dst" ]]; then
        dst="${dst}.$(date +%H%M%S)"
    fi
    if [[ -L "$src" ]]; then
        # Симлинк копируем как есть — так в бэкапе видно, куда он вёл
        ln -s -- "$(readlink -- "$src")" "$dst"
    else
        cp -a -- "$src" "$dst"
    fi
}

link_one() {
    local rel="$1" target="$2"
    local src="$REPO/$rel"

    if [[ ! -e "$src" ]]; then
        warn "в репо нет $rel — пропускаю"
        return 0
    fi

    # Цель уже указывает на репо — ничего делать не надо
    if [[ -L "$target" ]]; then
        local current
        current="$(readlink -f -- "$target" 2>/dev/null || true)"
        if [[ "$current" == "$(readlink -f -- "$src")" ]]; then
            skip "уже на месте: ${target/#$HOME/\~}"
            return 0
        fi
    fi

    # Занято чем-то настоящим — сначала в бэкап
    if [[ -e "$target" && ! -L "$target" ]]; then
        backup_existing "$target" "$target" "$rel"
        printf '  %s→%s %s (копия: %s)\n' "$C_WARN" "$C_0" \
            "освобождаю: ${target/#$HOME/\~}" \
            "${BACKUP_DIR/#$HOME/\~}/$rel"
    fi

    mkdir -p -- "$(dirname -- "$target")"
    if (( DRY_RUN )); then
        printf '  %s[dry-run]%s %s -> %s\n' "$C_SKIP" "$C_0" \
            "${target/#$HOME/\~}" "$rel"
    else
        rm -rf -- "$target"
        ln -s -- "$src" "$target"
        ok "${target/#$HOME/\~} → ${rel}"
    fi
}

# ── то, что нельзя выразить симлинком ───────────────────────────────────
# kdeglobals переписывает Noctalia при каждой смене темы, поэтому в репо его
# держать нельзя (в истории сыпались бы авто-генерируемые цвета). Но без ключа
# [KDE] color-scheme KF6-приложения (Dolphin, диалоги портала) берут схему
# по умолчанию — Breeze, то есть светлую. Ловим это здесь.
fixups() {
    printf '\n%sДоработки%s\n' "$C_B" "$C_0"

    local kdeglobals="$HOME/.config/kdeglobals"
    local scheme="noctalia"          # имя файла ~/.local/share/color-schemes/noctalia.colors
    local colors="$HOME/.local/share/color-schemes/$scheme.colors"
    local cur

    if ! command -v kwriteconfig6 >/dev/null 2>&1; then
        warn "нет kwriteconfig6 — [KDE] color-scheme не выставлен, поставь kde-config"
    else
        # Файла может ещё не быть (его создаёт Noctalia) — kwriteconfig6
        # создаст его сам, а Noctalia потом допишет свои цвета и сохранит ключ.
        cur="$(kreadconfig6 --file "$kdeglobals" --group KDE --key color-scheme 2>/dev/null || true)"
        if [[ "$cur" == "$scheme" ]]; then
            skip "kdeglobals: color-scheme=$scheme уже на месте"
        else
            # kwriteconfig6 дописывает ключ в существующую группу, остальные
            # ([Colors:*], [General], [KDE] contrast) не трогает — это важно,
            # их потом перезапишет Noctalia.
            run kwriteconfig6 --file "$kdeglobals" --group KDE --key color-scheme "$scheme"
            done_msg "kdeglobals: [KDE] color-scheme=$scheme"
        fi
    fi

    # Палитра Noctalia = шаблон kcolorscheme. Пока он выключен, файла нет и всё
    # выше проставлено вхолостую: KColorScheme не находит схему и молча берёт
    # Breeze (светлую). На чистой машине после установки это ровно тот случай.
    if [[ -f "$colors" ]]; then
        skip "палитра Noctalia на месте"
    else
        warn "нет ${colors/#$HOME/\~} — в Noctalia включи Settings → Templates → KColorScheme,
       иначе Qt-приложения останутся в теме Breeze (светлой)"
    fi
}

# noctalia msg печатает "ok"/"ok (exporting in background)" в stdout —
# гасим, оставляя stderr, чтобы ошибки были видны.
noctalia_q() { run noctalia msg "$@" >/dev/null; }

# ── пакеты ─────────────────────────────────────────────────────────────
install_packages() {
    local list="$REPO/packages.txt"
    [[ -f "$list" ]] || { warn "нет packages.txt, пропускаю"; return 0; }
    command -v pacman >/dev/null 2>&1 || {
        warn "нет pacman — пакеты не ставлю (список в packages.txt)"; return 0; }

    local -a pkgs=()
    local line
    while IFS= read -r line; do
        line="${line%%#*}"                     # убрать комментарий
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [[ -n "$line" ]] && pkgs+=("$line")
    done < "$list"

    (( ${#pkgs[@]} )) || { warn "список пакетов пуст"; return 0; }

    printf '\n%sПакеты%s (%d): %s\n' "$C_B" "$C_0" "${#pkgs[@]}" "${pkgs[*]}"
    if (( DRY_RUN )); then
        printf '  %s[dry-run]%s pacman -S --needed %s\n' "$C_SKIP" "$C_0" "${pkgs[*]}"
        return 0
    fi
    if (( DO_PACKAGES )); then
        # pacman спросит пароль — оставляем sudo на пользователе
        sudo pacman -S --needed --noconfirm "${pkgs[@]}" || warn "установка прервалась"
    else
        printf '  %s·%s пропущено (включи флагом -p)\n' "$C_SKIP" "$C_0"
    fi
}

# ── перезагрузка ───────────────────────────────────────────────────────
reload_session() {
    printf '\n%sПерезагрузка%s\n' "$C_B" "$C_0"

    if command -v niri >/dev/null 2>&1 && niri msg --json version >/dev/null 2>&1; then
        if niri validate >/dev/null 2>&1; then
            run niri msg action load-config-file && done_msg "niri перечитал конфиг"
        else
            warn "конфиг niri невалиден — файл не перечитан, смотри вывод niri validate"
            niri validate || true
        fi
    else
        skip "niri не запущен — перезагрузится при следующем входе"
    fi

    if command -v noctalia >/dev/null 2>&1; then
        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            run noctalia_q config-reload && done_msg "noctalia перечитал конфиг"
        else
            skip "noctalia не запущена (нет WAYLAND_DISPLAY)"
        fi
    else
        skip "noctalia не установлена"
    fi

    # плагин надо не только подложить, но и включить
    if command -v noctalia >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        run noctalia_q plugins enable davy1ex/niri-windows \
            && done_msg "плагин winlist включён" \
            || warn "не смог включить плагин winlist — включи вручную"
    fi

    # Портал (диалоги «открыть/сохранить» — в том числе Ctrl+O в редакторах)
    # живёт как systemd-юнит и не наследует переменные композитора, поэтому
    # перезапускаем его с выставленным вручную окружением. Без этого диалог
    # рисуется дефолтной темой Qt и не совпадает с системной.
    if command -v systemctl >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        reload_portal
    else
        skip "портал не перезапускаю (нет systemctl или WAYLAND_DISPLAY)"
    fi

    skip "уже открытые терминалы держат прежний QT_QPA_PLATFORMTHEME — перезапусти их"
}

# Перезапуск xdg-desktop-portal* с QT_QPA_PLATFORMTHEME=kde. Имена юнитов
# отличаются между дистрибутивами (kde/plasma-…), поэтому берём только те,
# что реально есть в этой системе.
reload_portal() {
    local -a candidates=(
        xdg-desktop-portal.service
        xdg-desktop-portal-kde.service
        plasma-xdg-desktop-portal-kde.service
        xdg-desktop-portal-gtk.service
        xdg-desktop-portal-gnome.service
    )
    local -a present=()
    local unit

    for unit in "${candidates[@]}"; do
        if systemctl --user cat "$unit" >/dev/null 2>&1; then
            present+=("$unit")
        fi
    done

    if (( ! ${#present[@]} )); then
        skip "юниты портала не найдены — поставь xdg-desktop-portal*"
        return 0
    fi

    if run systemctl --user set-environment QT_QPA_PLATFORMTHEME=kde; then
        if run systemctl --user restart "${present[@]}" >/dev/null; then
            done_msg "портал перезапущен: ${#present[@]} юнитов"
        else
            warn "не смог перезапустить портал — диалоги могут остаться в старой теме"
        fi
    else
        warn "не смог выставить окружение для портала"
    fi
}

# ── main ───────────────────────────────────────────────────────────────
printf '%s%s%s  →  %s\n' "$C_B" "${REPO/#$HOME/\~}" "$C_0" "$REPO"

if (( DRY_RUN )); then
    BACKUP_DIR="$BACKUP_ROOT/<dry-run>"
else
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
fi

printf '\n%sРаскладка%s\n' "$C_B" "$C_0"
for entry in "${LINKS[@]}"; do
    link_one "${entry%%|*}" "${entry##*|}"
done

# ~/.local/bin должен быть в PATH
if [[ -d "$HOME/.local/bin" ]]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "~/.local/bin не в PATH — скрипты запускай полным путём или
       добавь в ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
fi

if (( DO_PACKAGES )); then
    printf '\n%sПакеты%s\n' "$C_B" "$C_0"
    install_packages
fi

fixups

(( DO_RELOAD )) && reload_session

printf '\n%sГотово.%s Конфиги живут в репо, правь их прямо — симлинки двусторонние.\n' \
    "$C_OK" "$C_0"
printf 'Список пакетов и «что где лежит» — в README.md\n\n'
