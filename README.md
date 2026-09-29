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
│   ├── noctalia/           → ~/.config/noctalia
│   └── environment.d/      → ~/.config/environment.d  (пофайлово)
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

### Первый вход: что доделать руками

1. **Включить шаблон `KColorScheme`** в Noctalia: Settings → Templates →
   KColorScheme. Он пишет `~/.local/share/color-schemes/noctalia.colors` и
   `~/.config/kdeglobals` — без него тема Qt/KDE-приложений не работает и
   `install.sh` об этом предупредит. `install.sh` можно перезапустить после.
2. **Создать сессию niri** (WM-сессия / tty). `packages.txt` ставит бинари,
   но не настраивает автозапуск — это зависит от того, чем ты входишь.
   Сама сессия — `niri.desktop` из пакета `niri`.
3. **Перезапустить открытые терминалы**: они держат прежнее окружение.

Проверить, что всё встало:

```bash
niri validate                                        # config is valid
kreadconfig6 --file ~/.config/kdeglobals --group KDE --key color-scheme   # noctalia
kreadconfig6 --file ~/.config/kdeglobals --group Colors:Window --key BackgroundNormal
ls /usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so        # тема Qt есть
xdg-mime query default inode/directory               # org.kde.dolphin.desktop
```

`install.sh` в секции «Доработки» проверяет всё это сам и говорит, чего не
хватает, — в том числе предупреждает, если `plasma-integration` не стоит и
`QT_QPA_PLATFORMTHEME=kde` упирается в пустоту.

### Qt и Dolphin на чистой CachyOS

Из коробки в CachyOS + niri + Noctalia нет ни Qt, ни Dolphin — красить нечего,
пока их не поставить. Всё это в `packages.txt` и ставится ключом `-p`:

- `dolphin` — Qt6/KF6-приложение, ради него вся возня с темой;
- `plasma-integration` — плагин `KDEPlasmaPlatformTheme6.so`, без него
  `QT_QPA_PLATFORMTHEME=kde` молча ничего не делает;
- `xdg-desktop-portal-kde` — бэкенд, который рисует диалоги «открыть/сохранить»;
- `kconfig` — `kreadconfig6`/`kwriteconfig6` для `~/.config/kdeglobals`;
- `cachyos-niri-noctalia` — мета-пакет: niri, noctalia, порталы, курсор, шрифты
  и dconf-дефолты из `/etc/dconf/db/local.d/00-cachyos.conf`.

Nautilus из списка убран: `Mod+E` открывает Dolphin, и `install.sh` ставит его
файловым менеджером по умолчанию через `xdg-mime`.

Оговорка про `00-cachyos.conf`: он задаёт `gtk-theme='adw-gtk3-dark'` и
`color-scheme='prefer-dark'` **системными дефолтами**. `color-scheme` Noctalia
перезаписывает своим, а `gtk-theme` остаётся: GTK3-приложения (не Qt) не
светлеют никогда. Лечится либо своим `gsettings set`, либо синхронизацией с
`color-scheme` — пока не сделано.

### Чего в репозитории нет

**Состояние Noctalia (`~/.local/state/noctalia/settings.toml`) не версионируется.**
В её конфиг-стеке `settings.toml` перекрывает `config/noctalia/config.toml`
(это видно и в живой панели: там ram/cpu/preview из `settings.toml`, а не
layout из `config.toml`). То есть на чистой машине:

- панель, виджеты, плагины, тема и список шаблонов будут дефолтными;
- `config/noctalia/config.toml` из репо применится только к тем ключам, которых
  нет в `settings.toml` (на практике — почти ни к каким).

Снимок текущего состояния снять можно так:

```bash
noctalia config export            # merged: config-dir *.toml + settings.toml
```

Если хочется, чтобы переезд воспроизводил панель и тему один в один —
скажи, добавлю в репо пресет и посев в `install.sh`. Пока этого нет, смотри
на первый пункт выше.

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
| `config/environment.d/98-qt-platformtheme.conf` | тема Qt-приложений для systemd-юнитов |

Конфиг разбит на `include` не просто так: после правки одного файла niri
перечитывает только его, а не весь конфиг. Не склеивай обратно в один файл.

## Темы Qt/KDE-приложений

Dolphin, диалоги портала и прочие KF6/Qt-приложения красятся из **kdeglobals**,
который перезаписывает Noctalia при смене темы (шаблон `kcolorscheme` +
действие `kde-color-scheme`). Проверить, что палитра доехала:

```bash
kreadconfig6 --file ~/.config/kdeglobals --group Colors:Window --key BackgroundNormal
# 31,31,36 — тёмная, 240,237,244 — светлая
```

Три детали, без которых не работает:

1. **`QT_QPA_PLATFORMTHEME "kde"`** в `cfg/misc.kdl` — плагин из
   `plasma-integration`. Значение `gtk3` (было раньше) берёт тему GTK3, у
   которой в системе есть только тёмный вариант, поэтому Qt-окна не
   светлели. Значение `qt6ct` даёт рассинхрон: палитра читается один раз при
   старте приложения, а цвета иконок в KF6 берутся из kdeglobals на лету —
   после смены темы получаются тёмные иконки на тёмном фоне.
2. **`[KDE] color-scheme=noctalia` в `~/.config/kdeglobals`.** Без него
   KColorScheme не находит `~/.local/share/color-schemes/noctalia.colors` и
   откатывается на Breeze (светлую) — тихо, без ошибок. Файл генерируемый,
   симлинком сюда его не положить, поэтому `install.sh` проставляет ключ
   через `kwriteconfig6` (идемпотентно, другие группы не трогает).
3. **`config/environment.d/98-qt-platformtheme.conf`.** Переменная из niri
   попадает только в процессы, которые он сам спавнит. Портал стартует как
   systemd-юнит и её не наследует — отсюда светлые диалоги «открыть/сохнить».
   Файл нужен и для портала, и для всего, что запускается через D-Bus.

Уже открытые терминалы хранят старое значение — после смены конфига их надо
перезапустить, иначе Qt-приложение, запущенное из старого шелла, возьмёт
прежнюю тему.

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
