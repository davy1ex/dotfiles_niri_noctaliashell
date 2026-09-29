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
DO_FLATPAK=0
DO_APPIMAGE=0

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
  -f, --flatpak     поставить приложения из packages-flatpak.txt
  -A, --appimage    поставить AppImage из packages-appimage.txt
  -a, --apps        и flatpak, и AppImage
  -h, --help        эта справка
EOF
}

while (( $# )); do
    case "$1" in
        -n|--dry-run)   DRY_RUN=1 ;;
        -N|--no-reload) DO_RELOAD=0 ;;
        -p|--packages)  DO_PACKAGES=1 ;;
        -f|--flatpak)   DO_FLATPAK=1 ;;
        -A|--appimage)  DO_APPIMAGE=1 ;;
        -a|--apps)      DO_FLATPAK=1; DO_APPIMAGE=1 ;;
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
    "config/alacritty/alacritty.toml|$HOME/.config/alacritty/alacritty.toml"
    "config/environment.d/98-qt-platformtheme.conf|$HOME/.config/environment.d/98-qt-platformtheme.conf"
    "local/share/noctalia/plugins/niri-windows|$HOME/.local/share/noctalia/plugins/niri-windows"
    "local/bin/toggle-kb-layout|$HOME/.local/bin/toggle-kb-layout"
    "local/bin/noctalia-overview-theme|$HOME/.local/bin/noctalia-overview-theme"
    "local/bin/gtk3-theme-sync|$HOME/.local/bin/gtk3-theme-sync"
    "local/bin/kiview-quicklook.sh|$HOME/.local/bin/kiview-quicklook.sh"
    "local/bin/klipper-shim.py|$HOME/.local/bin/klipper-shim.py"
    "local/share/kio/servicemenus/kiview.desktop|$HOME/.local/share/kio/servicemenus/kiview.desktop"
    "config/systemd/user/klipper-shim.service|$HOME/.config/systemd/user/klipper-shim.service"
    "config/systemd/user/noctalia-overview-theme.service|$HOME/.config/systemd/user/noctalia-overview-theme.service"
    "config/systemd/user/noctalia-overview-theme.path|$HOME/.config/systemd/user/noctalia-overview-theme.path"
    "config/systemd/user/gtk3-theme-sync.service|$HOME/.config/systemd/user/gtk3-theme-sync.service"
    "config/systemd/user/gtk3-theme-sync.path|$HOME/.config/systemd/user/gtk3-theme-sync.path"
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

    # Плагин темы ставит plasma-integration. Без него QT_QPA_PLATFORMTHEME=kde
    # не находит что включать — Qt молча берёт дефолтную палитру.
    if [[ -e /usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so ]]; then
        skip "плагин KDE-темы на месте"
    else
        warn "нет KDEPlasmaPlatformTheme6.so — поставь plasma-integration (и Qt6 вообще),
       иначе Qt-приложения останутся без темы"
    fi

    # Dolphin — файловый менеджер по умолчанию (Mod+E в keybinds.kdl).
    if command -v xdg-mime >/dev/null 2>&1 && [[ -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
        local current
        current="$(xdg-mime query default inode/directory 2>/dev/null || true)"
        if [[ "$current" == "org.kde.dolphin.desktop" ]]; then
            skip "файловый менеджер по умолчанию: Dolphin"
        else
            run xdg-mime default org.kde.dolphin.desktop inode/directory
            done_msg "файловый менеджер по умолчанию: Dolphin (было ${current:-нет})"
        fi
    fi

    # Alacritty импортирует themes/noctalia.toml (его пишет шаблон alacritty в
    # Noctalia). Без шаблона файла нет, и терминал остаётся на дефолтной палитре.
    local alc_theme="$HOME/.config/alacritty/themes/noctalia.toml"
    if [[ -f "$alc_theme" ]]; then
        skip "тема Alacritty на месте"
    else
        warn "нет ${alc_theme/#$HOME/\~} — в Noctalia включи Settings → Templates → Alacritty,
       иначе терминал не переключится между светлой и тёмной"
    fi

    # Quick Look (Mod+Space в Dolphin): Kiview + шим Klipper.
    # Kiview — flatpak, в packages.txt его нет (там только pacman).
    if command -v flatpak >/dev/null 2>&1; then
        if flatpak info io.github.nyre221.kiview >/dev/null 2>&1; then
            skip "flatpak: io.github.nyre221.kiview уже стоит"
        else
            run flatpak install -y flathub io.github.nyre221.kiview \
                && done_msg "flatpak: io.github.nyre221.kiview поставлен" \
                || warn "не смог поставить Kiview — Quick Look не заработает"
        fi
    else
        warn "нет flatpak — Kiview (Quick Look) не ставлю"
    fi

    # Пункт «Quick Preview» в правом клике Dolphin подхватывается только
    # после перестройки kbuildsycoca.
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        run kbuildsycoca6 >/dev/null 2>&1 \
            && done_msg "kbuildsycoca: меню Dolphin обновлено" \
            || warn "kbuildsycoca6 упал — пункт Quick Preview может не появиться"
    else
        warn "нет kbuildsycoca6 — пункт Quick Preview в Dolphin не подхватится"
    fi

    # Шим org.kde.klipper для Kiview (вне Plasma Klipper'а нет, без шима
    # Kiview падает с «The name is not activatable»). Юнит уже лежит
    # симлинком из репо, здесь только daemon-reload + enable.
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl --user daemon-reload
        if systemctl --user is-enabled klipper-shim.service >/dev/null 2>&1; then
            skip "klipper-shim уже включён"
        else
            run systemctl --user enable --now klipper-shim.service \
                && done_msg "klipper-shim включён и запущен" \
                || warn "не смог включить klipper-shim — Quick Look не заработает"
        fi
    else
        warn "нет systemctl — klipper-shim не включаю"
    fi
}

# noctalia msg печатает "ok"/"ok (exporting in background)" в stdout —
# гасим, оставляя stderr, чтобы ошибки были видны.
noctalia_q() { run noctalia msg "$@" >/dev/null; }

# Разбирает список пакетов: убирает комментарий и пробелы, пропускает пустые.
# Общий для packages.txt, packages-flatpak.txt и packages-appimage.txt.
read_list() {
    local line
    [[ -f "$1" ]] || return 0
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [[ -n "$line" ]] && printf '%s\n' "$line"
    done < "$1"
}

# ── пакеты ─────────────────────────────────────────────────────────────
install_packages() {
    local list="$REPO/packages.txt"
    [[ -f "$list" ]] || { warn "нет packages.txt, пропускаю"; return 0; }
    command -v pacman >/dev/null 2>&1 || {
        warn "нет pacman — пакеты не ставлю (список в packages.txt)"; return 0; }

    local -a pkgs=()
    mapfile -t pkgs < <(read_list "$list")

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

# ── приложения не из pacman ────────────────────────────────────────────
install_flatpak() {
    local list="$REPO/packages-flatpak.txt"
    if ! command -v flatpak >/dev/null 2>&1; then
        warn "нет flatpak — пропускаю (список в packages-flatpak.txt)"
        return 0
    fi

    local -a ids=()
    mapfile -t ids < <(read_list "$list")
    (( ${#ids[@]} )) || { skip "список flatpak пуст"; return 0; }

    printf '\n%sFlatpak%s (%d): %s\n' "$C_B" "$C_0" "${#ids[@]}" "${ids[*]}"
    local id
    for id in "${ids[@]}"; do
        if flatpak info "$id" >/dev/null 2>&1; then
            skip "уже стоит: $id"
        elif (( DRY_RUN )); then
            printf '  %s[dry-run]%s flatpak install -y flathub %s\n' "$C_SKIP" "$C_0" "$id"
        elif flatpak install -y flathub "$id" >/dev/null 2>&1; then
            ok "$id"
        else
            warn "не поставился: $id"
        fi
    done
}

# AppImage: файла нет в pacman, поэтому ставим файлом + генерируем .desktop
# и иконку. Список — packages-appimage.txt (формат описан в шапке файла).
install_appimages() {
    local list="$REPO/packages-appimage.txt"
    local icons="$REPO/local/share/appimages-icons"
    local dir="$HOME/AppImages"
    local applications="$HOME/.local/share/applications"

    if [[ ! -f "$list" ]]; then
        warn "нет packages-appimage.txt, пропускаю"
        return 0
    fi

    printf '\n%sAppImage%s\n' "$C_B" "$C_0"
    local line
    while IFS= read -r line; do
        IFS='|' read -r id version name wmclass mimetype args url page <<<"$line"
        [[ "$wmclass" == "-" ]] && wmclass=""
        [[ "$mimetype" == "-" ]] && mimetype=""
        [[ "$args" == "-" ]] && args=""

        local appimage="$dir/$id.appimage"

        if [[ -f "$appimage" ]]; then
            skip "уже есть: ${appimage/#$HOME/\~}"
        elif [[ "$url" == "-" ]]; then
            # Вендор отдаёт AppImage по подменяемому URL — качать нечем.
            warn "$name $version: качай вручную → $page"
        elif (( DRY_RUN )); then
            printf '  %s[dry-run]%s curl -fL -o %s %s\n' "$C_SKIP" "$C_0" \
                "${appimage/#$HOME/\~}" "$url"
        elif ! command -v curl >/dev/null 2>&1; then
            warn "нет curl — $name не скачать, иди вручную: $page"
        else
            mkdir -p "$dir"
            printf '  %s↓%s %s %s\n' "$C_SKIP" "$C_0" "$name" "$version"
            if curl -fL --progress-bar -o "$appimage.part" "$url" 2>/dev/null; then
                mv "$appimage.part" "$appimage"
                ok "${appimage/#$HOME/\~}"
            else
                rm -f "$appimage.part"
                warn "не скачался $name: $url"
            fi
        fi

        # Иконка и .desktop генерируем всегда: даже для уже скачанного файла
        # на новой машине их может не быть.
        if [[ -f "$icons/$id" ]]; then
            mkdir -p "$dir/.icons"
            if [[ ! -f "$dir/.icons/$id" ]] || (( DRY_RUN )); then
                if (( DRY_RUN )); then
                    printf '  %s[dry-run]%s иконка → %s\n' "$C_SKIP" "$C_0" "${dir/#$HOME/\~}/.icons/$id"
                else
                    cp "$icons/$id" "$dir/.icons/$id" && done_msg "иконка: .icons/$id"
                fi
            fi
        else
            warn "нет иконки для $name в local/share/appimages-icons/$id"
        fi

        # Свой .desktop не трогаем, если он уже есть: приложения на Electron
        # сами пишут богатые файлы (Comment, StartupWMClass). Наш генератор —
        # запасной вариант для чистой машины.
        if [[ -f "$applications/$id.desktop" ]] && ! (( DRY_RUN )); then
            skip ".desktop уже есть: ${applications/#$HOME/\~}/$id.desktop"
            continue
        fi
        if (( DRY_RUN )); then
            printf '  %s[dry-run]%s .desktop → %s\n' "$C_SKIP" "$C_0" "${applications/#$HOME/\~}/$id.desktop"
            continue
        fi
        mkdir -p "$applications"
        {
            printf '[Desktop Entry]\n'
            printf 'Type=Application\n'
            printf 'Name=%s\n' "$name"
            printf 'Icon=%s/.icons/%s\n' "$dir" "$id"
            printf 'TryExec=%s\n' "$appimage"
            printf 'Exec=env DESKTOPINTEGRATION=1 %s %s%%U\n' "$appimage" "${args:+$args }"
            printf 'Terminal=false\n'
            [[ -n "$wmclass" ]] && printf 'StartupWMClass=%s\n' "$wmclass"
            printf 'Categories=Office;\n'
            [[ -n "$mimetype" ]] && printf 'MimeType=%s\n' "$mimetype"
            printf 'X-AppImage-Version=%s\n' "$version"
            printf 'X-AppImage-Name=%s\n' "$name"
        } >"$applications/$id.desktop"
        ok ".desktop: ${applications/#$HOME/\~}/$id.desktop"
    done < <(read_list "$list")

    if command -v update-desktop-database >/dev/null 2>&1; then
        run update-desktop-database "$applications" >/dev/null
    fi
}

# Состояние Noctalia (панель, виджеты, плагины) живёт в
# ~/.local/state/noctalia/settings.toml и перекрывает config/noctalia/config.toml,
# поэтому без него переезд не воспроизводит вид и плагины. Посев — только если
# файла нет: живое состояние не затираем никогда.
seed_noctalia() {
    local seed="$REPO/config/noctalia/settings.toml"
    local live="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/settings.toml"

    printf '\n%sСостояние Noctalia%s\n' "$C_B" "$C_0"

    if [[ ! -f "$seed" ]]; then
        skip "нет снимка config/noctalia/settings.toml"
        return 0
    fi

    if [[ -f "$live" ]]; then
        skip "settings.toml на месте — не трогаю (обновить: noctalia config export > ~/dotfiles/config/noctalia/settings.toml)"
    elif (( DRY_RUN )); then
        printf '  %s[dry-run]%s посев %s → %s\n' "$C_SKIP" "$C_0" \
            "config/noctalia/settings.toml" "${live/#$HOME/\~}"
    else
        mkdir -p "$(dirname -- "$live")"
        cp "$seed" "$live"
        ok "посеял ${live/#$HOME/\~}"
    fi

    enable_noctalia_plugins "$seed"
}

# Плагины Noctalia тянутся с noctalia.dev по id, поэтому восстанавливаются
# одной командой. Исключение — локальный davy1ex/niri-windows: он лежит
# симлинком из репо и в каталоге не появляется.
enable_noctalia_plugins() {
    local seed="${1:-$REPO/config/noctalia/settings.toml}"
    command -v noctalia >/dev/null 2>&1 || { skip "noctalia не установлена — плагины не включаю"; return 0; }
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        skip "noctalia не запущена — плагины включатся при следующем входе"
        return 0
    fi

    local -a ids=()
    mapfile -t ids < <(awk '/^\[plugins\]/{f=1;next} /^\[/{f=0} f' "$seed" | grep -o '"[^"]*"' | tr -d '"')
    (( ${#ids[@]} )) || { skip "в снимке нет списка плагинов"; return 0; }

    local id
    for id in "${ids[@]}"; do
        if noctalia_q plugins enable "$id"; then
            done_msg "плагин: $id"
        else
            warn "не включился плагин $id — включи вручную (нет сети или нет в каталоге)"
        fi
    done
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

    # Обзор воркспейсов красится скриптом под текущую тему Noctalia.
    # Юниты уже симлинками из репо, включаем .path — он и слушает kdeglobals.
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl --user daemon-reload
        if systemctl --user is-enabled noctalia-overview-theme.path >/dev/null 2>&1; then
            run systemctl --user restart noctalia-overview-theme.path 2>/dev/null || true
            skip "noctalia-overview-theme.path уже включён"
        else
            run systemctl --user enable --now noctalia-overview-theme.path \
                && done_msg "тема обзора воркспейсов: слежу за kdeglobals" \
                || warn "не смог включить noctalia-overview-theme.path — обзор останется серым"
        fi
    else
        warn "нет systemctl — тему обзора воркспейсов не включаю"
    fi

    # Синхронизация GTK3-темы с color-scheme. Нужна, потому что CachyOS
    # задаёт gtk-theme='adw-gtk3-dark' системным дефолтом и цвет, заданный
    # пользователем, его не перебивает.
    if command -v gsettings >/dev/null 2>&1; then
        local gtk_theme
        gtk_theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
        case "$gtk_theme" in
            "" | adw-gtk3 | adw-gtk3-dark | adw-gtk3-high-contrast | adw-gtk3-high-contrast-dark)
                if command -v systemctl >/dev/null 2>&1; then
                    if systemctl --user is-enabled gtk3-theme-sync.path >/dev/null 2>&1; then
                        run systemctl --user restart gtk3-theme-sync.path 2>/dev/null || true
                    else
                        run systemctl --user enable --now gtk3-theme-sync.path \
                            && done_msg "GTK3-тема синхронизируется с color-scheme" \
                            || warn "не смог включить gtk3-theme-sync.path"
                    fi
                    # Разовая синхронизация: на новой машине события ещё не было.
                    run "$HOME/.local/bin/gtk3-theme-sync" || true
                else
                    warn "нет systemctl — синхронизацию GTK3-темы не включаю"
                fi
                ;;
            *)
                warn "gtk-theme=${gtk_theme:-<пусто>} — не adw-gtk3, синхронизация не тронет
       (это твой выбор темы; GTK3 останется на adw-gtk3-dark из dconf CachyOS)"
                ;;
        esac
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

# Состояние Noctalia сеется всегда (идемпотентно: живой файл не трогаем) —
# без него панель, виджеты и плагины на новой машине будут дефолтными.
seed_noctalia

if (( DO_FLATPAK )); then
    install_flatpak
else
    printf '\n%sFlatpak%s\n' "$C_B" "$C_0"
    printf '  %s·%s пропущено (включи флагом -f)\n' "$C_SKIP" "$C_0"
fi

if (( DO_APPIMAGE )); then
    install_appimages
else
    printf '\n%sAppImage%s\n' "$C_B" "$C_0"
    printf '  %s·%s пропущено (включи флагом -A)\n' "$C_SKIP" "$C_0"
fi

fixups

(( DO_RELOAD )) && reload_session

printf '\n%sГотово.%s Конфиги живут в репо, правь их прямо — симлинки двусторонние.\n' \
    "$C_OK" "$C_0"
printf 'Список пакетов и «что где лежит» — в README.md\n\n'
