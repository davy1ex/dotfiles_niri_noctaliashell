#!/usr/bin/env bash
# Quick Look for Dolphin under niri (no Klipper here).
#
# Kiview's own --shortcut mode requires org.kde.klipper (Plasma-only),
# so this script does the Dolphin -> clipboard -> Kiview round-trip itself:
#   1. focused window must be Dolphin (asked from niri, matched by PID)
#   2. trigger Dolphin's copy_location action via DBus (copies file:// URL as text)
#   3. read the URL via wl-paste, decode it to a path
#   4. restore the clipboard, open the path in Kiview (-s = selection mode)
set -u

LOG=/tmp/kiview-quicklook.log
log() { echo "$(date +%H:%M:%S) $*" >>"$LOG"; }
tail -n 50 "$LOG" 2>/dev/null >"$LOG.tmp" && mv "$LOG.tmp" "$LOG" 2>/dev/null || true

info="$(niri msg --json focused-window 2>/dev/null)" || { log "FAIL niri msg"; exit 0; }
app_id="$(printf '%s' "$info" | jq -r '.app_id // empty' 2>/dev/null)"
pid="$(printf '%s' "$info" | jq -r '.pid // empty' 2>/dev/null)"
log "focused app_id=$app_id pid=$pid"
case "$app_id" in
    *dolphin* | *Dolphin*) ;;
    *) log "SKIP not dolphin"; exit 0 ;;
esac
[[ "$pid" =~ ^[0-9]+$ ]] || { log "FAIL bad pid"; exit 0; }

svc="org.kde.dolphin-$pid"
# NB: qdbus6 выводит имена с ведущим пробелом — срезаем его, иначе -x/^ не матчат
bus_list() { qdbus6 --session 2>/dev/null | sed 's/^[[:space:]]*//'; }
found=""
for _ in $(seq 1 25); do
    if bus_list | grep -qxF "$svc"; then found="$svc"; break; fi
    sleep 0.2
done
if [[ -z "$found" ]]; then
    # fallback: любой dolphin с активным окном (как делает сам Kiview)
    for cand in $(bus_list | grep -E '^org\.kde\.dolphin-[0-9]+$'); do
        is_active="$(qdbus6 --session "$cand" /dolphin/Dolphin_1 org.freedesktop.DBus.Properties.Get org.qtproject.Qt.QWidget isActiveWindow 2>/dev/null || true)"
        if [[ "$is_active" == "true" ]]; then found="$cand"; break; fi
    done
fi
[[ -n "$found" ]] || { log "FAIL no bus $svc"; exit 0; }
svc="$found"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
saved_file="$TMP/clip"

# --- save clipboard (type-aware, so images / copied files survive) ---
types="$(wl-paste --list-types 2>/dev/null || true)"
saved_type="$(grep -m1 -E '^(text/uri-list|text/plain)' <<<"$types" || true)"
if [[ -z "$saved_type" ]]; then
    saved_type="$(grep -m1 -iE '^image/' <<<"$types" || true)"
fi
if [[ -z "$saved_type" ]]; then
    saved_type="$(head -n1 <<<"$types" || true)"
fi
if [[ -n "$saved_type" ]]; then
    wl-paste --type "$saved_type" >"$saved_file" 2>/dev/null || saved_type=""
fi

# --- clear, trigger Dolphin copy_location, poll clipboard ---
wl-copy --clear 2>/dev/null || true
enabled="$(qdbus6 --session "$svc" /dolphin/Dolphin_1/actions/copy_location org.freedesktop.DBus.Properties.Get org.qtproject.Qt.QAction enabled 2>&1 || true)"
trigger_err="$(qdbus6 --session "$svc" /dolphin/Dolphin_1/actions/copy_location org.qtproject.Qt.QAction.trigger 2>&1)"
log "copy_location enabled=$enabled trigger_err=$trigger_err"

url=""
for _ in $(seq 1 20); do
    sleep 0.2
    url="$(wl-paste 2>/dev/null | tr -d '\r' | grep -m1 -E '^(file://|/)' || true)"
    [[ -n "$url" ]] && break
done
raw="$(wl-paste 2>/dev/null | head -c 200 | tr '\n' '|')"
log "clipboard_raw=$raw"

# --- restore clipboard ---
if [[ -n "$saved_type" && -s "$saved_file" ]]; then
    wl-copy --type "$saved_type" <"$saved_file" 2>/dev/null || true
else
    wl-copy --clear 2>/dev/null || true
fi

# --- open in Kiview ---
if [[ -z "$url" ]]; then log "FAIL empty clipboard after trigger"; exit 0; fi
if [[ "$url" == file://* ]]; then
    path="$(python3 -c 'import sys,urllib.parse; u=urllib.parse.urlparse(sys.argv[1]); print(urllib.parse.unquote(u.path))' "$url")"
else
    # Dolphin 26 кладёт обычный путь без схемы
    path="$url"
fi
log "url=$url path=$path"
[[ -e "$path" ]] || { log "FAIL path missing"; exit 0; }
log "OPEN $path"
flatpak run io.github.nyre221.kiview -s "$path" >>"$LOG" 2>&1 &
