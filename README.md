# dotfiles — niri + Noctalia

Конфиги рабочего окружения в git-репозитории. На машине они не копии, а
симлинки в этот репозиторий, поэтому «сохранить» = `git commit`, а переезд на
новую ОС = клонировать + запустить один скрипт.

```
~/dotfiles/
├── install.sh              раскладка конфигов на машину
├── packages.txt            пакеты для чистой установки
├── config/
│   ├── niri/               → ~/.config/niri
│   └── noctalia/           → ~/.config/noctalia
├── local/
│   ├── bin/                → ~/.local/bin  (пофайлово)
│   └── share/noctalia/plugins/niri-windows/  → ~/.local/share/noctalia/plugins/
└── docs/                   заметки об окружении
```

## Переезд на новую ОС

```bash
git clone <url> ~/dotfiles
cd ~/dotfiles
./install.sh -p        # -p = ещё и поставить пакеты из packages.txt
```

Скрипт идемпотентен: существующие файлы не перезаписывает молча, а сначала
кладёт в `~/.local/share/dotfiles-backup/<дата-время>/`. Повторный запуск
ничего не ломает.

Опции: `-n` (dry-run, показать что будет), `-N` (не перезагружать сессию),
`-p` (поставить пакеты), `-h`.

## Сохранение правок

Симлинки двусторонние — правь `~/.config/niri/cfg/keybinds.kdl` как обычно,
файл меняется в репо. Дальше:

```bash
cd ~/dotfiles
git add -A
git commit -m "keybinds: Mod+Y для yawn"
git push
```

Забыть закоммитить невозможно, но забыть *запушить* — легко: коммит живёт
только на этом ноуте, а переезжаешь ты с пушиком. Два варианта.

Разово перед тем как гасить ноут — `git push` руками. Если лень каждый раз,
повесь автопуш на systemd user-таймер:

```bash
mkdir -p ~/.config/systemd/user
cp ~/dotfiles/docs/dotfiles-push.service ~/.config/systemd/user/
cp ~/dotfiles/docs/dotfiles-push.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dotfiles-push.timer
```

Таймер лежит в `docs/` рядом с этим README, его надо один раз скопировать
на целевую машину. Токен для приватного репо — в `~/.config/git-credentials`,
его в репозиторий класть нельзя (проверь, что он не попал в `git status`).

## Раскладка по слоям

| Файл | Что меняет |
|---|---|
| `config/niri/config.kdl` | только `include` остальных файлов |
| `config/niri/cfg/keybinds.kdl` | хоткеи |
| `config/niri/cfg/workspaces.kdl` | список именованных воркспейсов |
| `config/niri/cfg/input.kdl` | клавиатура, тачпад, focus-follows-mouse |
| `config/niri/cfg/misc.kdl` | курсор, blur, prefer-no-csd, environment |
| `config/niri/cfg/rules.kdl` | правила окон (флоат, радиусы, blur) |
| `config/niri/cfg/display.kdl` | мониторы, разрешения, скейлы |
| `config/niri/cfg/layout.kdl` | табы и раздельная ширина |
| `config/niri/cfg/animation.kdl` | анимации |
| `config/niri/cfg/autostart.kdl` | что стартует вместе с niri |
| `config/noctalia/config.toml` | бар, виджеты, плагины |

Конфиг разбит на `include` не просто так: после правки одного файла niri
перечитывает только его, а не весь конфиг. Не склеивай обратно в один файл.

## Плагин winlist

`local/share/noctalia/plugins/niri-windows/` — самописный виджет, показывает
окна текущего воркспейса, разложенные вокруг фокусного.

`plugin_api = 30` в `plugin.toml` подобран под Noctalia 5.1.0 (поддерживает 3–30).
При обновлении Noctalia проверь: `plugin.toml` → `plugin_api`, иначе виджет
молча не загрузится.

Правь **здесь**, в репо. Копия в `~/01_Projects/niri-windows/` — устарела
(в ней нет комментария про `pos_in_scrolling_layout`), её можно удалить.

## Проверка перед коммитом

```bash
niri validate                     # синтаксис KDL
niri msg action load-config-file  # применить на живой сессии
noctalia config validate          # TOML оболочки
```

`niri validate` ловит опечатки в хоткеях. Ошибка парсинга — весь конфиг
не перечитывается, и niri молча продолжает работать на старых настройках,
поэтому проверяй после каждой правки `keybinds.kdl`.

## Перенос на другую машину с нуля

Если нужно не «восстановить», а именно перенести набор пакетов и настройки
дословно, не трогая текущую машину:

```bash
# на новой машине
git clone <url> ~/dotfiles && cd ~/dotfiles && ./install.sh -p
```

Если старый ноут ещё нужен — сначала на нём:

```bash
cd ~/dotfiles && git status   # убедись, что всё закоммичено
git push
```

`git status` с непустым выводом означает, что на новой машине чего-то не
хватит. Пустые `__pycache__`-подобные артефакты в `.gitignore` — не в счёт.
