# Переносимость: что ставится и что настраивается

Документ отвечает на один вопрос: **как поднять это окружение на чистой
машине** и что делать руками, потому что автоматизировать нельзя.

Коротко: `git clone` → `install.sh`. Остальное — точечно.

```bash
git clone <url> ~/dotfiles
cd ~/dotfiles
./install.sh -p -a      # -p = pacman, -a = flatpak + AppImage
```

---

## 1. Слои установки

Всё, что стоит на машине, лежит в одном из четырёх слоёв. Список слоя —
это и есть список файлов в репозитории.

| Слой | Список в репо | Кто ставит | Что не попадает в репо |
|---|---|---|---|
| Системные пакеты | `packages.txt` | `sudo pacman -S` | — |
| Flatpak | `packages-flatpak.txt` | `flatpak install` | — |
| AppImage | `packages-appimage.txt` + `local/share/appimages-icons/` | `install.sh -A` | сами `.appimage` (1–1 ГБ) |
| Конфиги | `config/`, `local/`, симлинками | `install.sh` | — |
| Состояние Noctalia | `config/noctalia/settings.toml` | `install.sh` (посев) | живой `settings.toml` на машине |

`install.sh` идемпотентен: повторный запуск ничего не ломает, занятые файлы
сначала уходят в `~/.local/share/dotfiles-backup/<дата-время>/`.

Опции: `-n` (dry-run), `-N` (без перезагрузки), `-p` (pacman),
`-f` (flatpak), `-A` (AppImage), `-a` (flatpak + AppImage), `-h`.

---

## 2. Темы: кто откуда берёт цвет

Главный принцип: **один источник правды — `~/.config/kdeglobals`**.
Его переписывает Noctalia при каждой смене темы (шаблон `kcolorscheme` +
действие `kde-color-scheme`).

| Слой приложений | Откуда цвет | Чем настроено | Следует за темой |
|---|---|---|---|
| GTK4/libadwaita | `gsettings color-scheme` | сама Noctalia | да |
| **GTK3** | `gsettings gtk-theme` | `local/bin/gtk3-theme-sync` | **да** (раньше было нет, см. ниже) |
| Qt6/KF6 (Dolphin, диалоги) | `kdeglobals` → `QT_QPA_PLATFORMTHEME=kde` | `cfg/misc.kdl`, `config/environment.d/`, `kdeglobals[color-scheme]` | да, живьём |
| Alacritty | `alacritty.toml` → `import themes/noctalia.toml` | шаблон `alacritty` в Noctalia | да, через `live_config_reload` |
| Обзор воркспейсов niri | `~/.local/state/dotfiles/theme-overview.kdl` | скрипт `noctalia-overview-theme` | да, через `.path`-юнит |
| Панель Noctalia | сама Noctalia | снимок `config/noctalia/settings.toml` | да |

### GTK3: почему нужен синхронизатор

Пакет `cachyos-desktop-settings` (тянется `cachyos-niri-noctalia`) кладёт
системные дефолты в `/etc/dconf/db/local.d/00-cachyos.conf`:

```
color-scheme='prefer-dark'
gtk-theme='adw-gtk3-dark'
```

`color-scheme` Noctalia перезаписывает своим, `gtk-theme` — нет. GTK4
светлеет, GTK3-приложения и нативный диалог выбора файла остаются тёмными
навсегда. Поэтому `local/bin/gtk3-theme-sync` переводит `gtk-theme` по
`color-scheme`: `prefer-dark` → `adw-gtk3-dark`, всё остальное → `adw-gtk3`.

Три решения, которые стоит знать, прежде чем что-то править:

- **Триггер — `~/.config/dconf/user`, а не `kdeglobals`.** При смене темы
  Noctalia пишет `kdeglobals` примерно на 100 мс раньше gsettings; триггер по
  нему успевал бы прочитать старое значение `color-scheme`. dconf пишется
  после — к моменту пробуждения новое уже на месте.
- **Через dconf проходит любое изменение gsettings**, поэтому юнит
  срабатывает часто, а скрипт идемпотентен: пишет, только если значение
  реально отличается.
- **Чужие темы не затираются.** Скрипт работает только с семейством
  `adw-gtk3*`; если стоит Materia или Breeze-gtk, он молча уходит и
  `install.sh` предупреждает об этом. Отключить синхронизацию:
  `systemctl --user disable --now gtk3-theme-sync.path`.

### Шаблоны Noctalia — обязательный шаг

Шаблоны пишут палитру в чужие приложения, и без них три строки таблицы выше
не работают. Включаются руками:

**Settings → Templates → KColorScheme** и **Alacritty**.

`install.sh` проверяет наличие обеих выгрузок и предупредит, если их нет.

### Обзор воркспейсов

niri не умеет менять цвета по IPC, в конфиге только статика. Поэтому
`local/bin/noctalia-overview-theme` читает `kdeglobals` и пишет маленький
файл, подключённый в `config.kdl`:

```kdl
include optional=true "~/.local/state/dotfiles/theme-overview.kdl"
```

`optional=true` — на машине без скрипта конфиг остаётся валидным. Файл лежит
**вне репозитория**: его содержимое меняется на каждый переключатель темы и
засоряло бы git. Срабатывание — `noctalia-overview-theme.path`, он смотрит на
`kdeglobals` и на `noctalia.colors`.

---

## 3. Плагины Noctalia

Десять плагинов из снимка `config/noctalia/settings.toml`, раздел `[plugins]`:

| Плагин | Что делает |
|---|---|
| `davy1ex/niri-windows` | винлист: окна вокруг фокусного (**локальный, лежит в репо**) |
| `cleboost/hotspot` | переключатель точек доступа |
| `h-jangra/keyviz` | визуализация нажатий |
| `kenn/keybind-cheatsheet` | шпаргалка по хоткеям |
| `prponkshe/umbriel-displays` | панель управления дисплеями (в т.ч. блокировка) |
| `teagar/niri-workspace-preview` | превью рабочих областей |
| `damian-ds7/battery-threshold` | порог заряда батареи |
| `alexander/screen-toolkit` | утилиты экрана (яркость, поворот) |
| `noctalia/translator` | перевод выделенного |
| `gabedunn/voxtype` | голосовой ввод |

Девять из десяти тянутся с `noctalia.dev` по id — `install.sh` включает их
командой `noctalia msg plugins enable <id>`, нужна сеть. Десятый
(`davy1ex/niri-windows`) лежит симлинком из `local/share/noctalia/plugins/`
и в каталоге не появляется, но включается той же командой.

---

## 4. Приложения

### Flatpak (`./install.sh -f`)

| id | Что |
|---|---|
| `app.zen_browser.zen` | Zen — браузер |
| `com.obsproject.Studio` | OBS Studio |
| `io.github.nyre221.kiview` | Kiview — Quick Look (нужен шим Klipper, см. ниже) |
| `it.mijorus.gearlever` | Gear Lever — переключатель тем GTK |
| `org.telegram.desktop` | Telegram |

### AppImage (`./install.sh -A`)

Скачиваются в `~/AppImages`, `.desktop` и иконка генерируются скриптом.
Иконки лежат в репо (`local/share/appimages-icons/`), сами файлы — нет:
это 1–1 ГБ каждый.

| Приложение | Версия | Автоматически | Вручную |
|---|---|---|---|
| Obsidian | 1.13.7 | да | [obsidian.md/download](https://obsidian.md/download) |
| LocalSend | 1.18.2 | да | [localsend.org](https://localsend.org/#download) |
| TickTick | 8.0.20 | нет | [ticktick.com/download/linux](https://ticktick.com/download/linux) |
| LM Studio | 0.4.25 | нет | [lmstudio.ai/download](https://lmstudio.ai/download) |
| LM Studio Hub (`bionic`) | 1.1.6 | нет | [lmstudio.ai/hub](https://lmstudio.ai/hub) |

«Нет» означает, что вендор отдаёт файл по подменяемому URL: стабильной
ссылки нет, `install.sh` напечатает страницу. Обновить список:

```bash
noctalia config export > ~/dotfiles/config/noctalia/settings.toml   # состояние
```

Версии AppImage снимаются из `X-AppImage-Version` в `~/.local/share/applications/*.desktop`.

### Системное, что ставится не пакетами

| Что | Пакет / источник | Зачем |
|---|---|---|
| Шрифт панели | `otf-hasklig-nerd` | без него панель Noctalia рисует квадраты вместо иконок |
| Плагин KDE-темы | `plasma-integration` | даёт `KDEPlasmaPlatformTheme6.so` |
| Диалоги портала | `xdg-desktop-portal-kde` | Ctrl+O в редакторах рисует Qt-диалог |
| `kreadconfig6` / `kwriteconfig6` | `kconfig` | ими `install.sh` правит `kdeglobals` |
| Шим Klipper | `config/systemd/user/klipper-shim.service` (в репо) | без него Kiview падает с «The name is not activatable» |
| Пункт Quick Look в Dolphin | `kbuildsycoca6` | иначе пункт не появляется в меню |

---

## 5. Проверка: что всё встало

Готовый чек-лист встроен в установщик — одной командой, ничего не меняя:

```bash
./install.sh -t        # или --self-test
```

Печатает `✓` / `·` / `✗` по разделам (симлинки, niri, тема Qt/KDE, терминал,
обзор, GTK3, Noctalia, приложения, пакеты, репозиторий) и возвращает ненулевой
код, если есть провалы. Скрипт для CI или для «развернул на новой машине и
сразу проверил». Ниже — то же самое руками, для случая когда скрипта нет:

```bash

```bash
niri validate                                   # KDL валиден
niri msg keyboard-layouts                       # us, ru на месте
kreadconfig6 --file ~/.config/kdeglobals --group KDE --key color-scheme       # noctalia
ls /usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so             # тема Qt есть
ls ~/.config/alacritty/themes/noctalia.toml                                    # тема терминала
ls ~/.local/state/dotfiles/theme-overview.kdl                                 # тема обзора
grep backdrop-color ~/.local/state/dotfiles/theme-overview.kdl              # цвет обзора
systemctl --user is-active noctalia-overview-theme.path                        # слушает тему
systemctl --user is-active gtk3-theme-sync.path                                # GTK3 ← color-scheme
gsettings get org.gnome.desktop.interface gtk-theme                            # adw-gtk3(-dark)
xdg-mime query default inode/directory                    # org.kde.dolphin.desktop
noctalia config validate                                  # TOML оболочки
flatpak list --app | wc -l                                # 5
ls ~/AppImages/*.appimage | wc -l                          # 5
```

---

## 6. Что осталось за скобками

- **Сессия и вход.** `niri.desktop` ставится пакетом `niri`, но диспетчер
  рабочих столов и автологин — не наша зона: зависит от того, чем входишь.
- **dconf-дефолты CachyOS.** `cachyos-niri-noctalia` тянет
  `/etc/dconf/db/local.d/00-cachyos.conf` с `color-scheme` и `gtk-theme`.
  Первое Noctalia перезаписывает, второе — нет (см. п. 2).
- **Пресет сообщества `One Dark Two`.** В снимке Noctalia
  `[theme] community_palette`; на новой машине требует синхронизации
  каталога с noctalia.dev.
- **Виджеты на конкретных мониторах.** В снимке есть `eDP-1` / `HDMI-A-1` и
  координаты `cx`/`cy`. На другой машине эти блоки можно удалить — плагин
  `umbriel-displays` создаст локрин свои.
- **Voxtype.** Демон и бинд `Mod+Shift+Space` намеренно не закоммичены
  (см. историю репозитория), поэтому в автоматической установке их нет.
