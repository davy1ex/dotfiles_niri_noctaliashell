# dotfiles — niri + Noctalia

Конфиги рабочего окружения в git-репозитории. На машине они не копии, а
симлинки в этот репозиторий, поэтому «сохранить» = `git commit`, а переезд на
новую ОС = клонировать + запустить один скрипт.

```
~/dotfiles/
├── install.sh              раскладка конфигов на машину
├── packages.txt            пакеты pacman для чистой установки
├── packages-flatpak.txt    приложения из flatpak
├── packages-appimage.txt   приложения из AppImage (+ иконки в local/share/)
├── config/
│   ├── niri/               → ~/.config/niri
│   ├── noctalia/           → ~/.config/noctalia
│   ├── alacritty/          → ~/.config/alacritty  (пофайлово)
│   ├── systemd/user/       → ~/.config/systemd/user  (пофайлово)
│   └── environment.d/      → ~/.config/environment.d  (пофайлово)
├── local/
│   ├── bin/                → ~/.local/bin  (пофайлово)
│   └── share/noctalia/plugins/niri-windows/  → ~/.local/share/noctalia/plugins/
└── docs/
    ├── portability.md      ← подробный разбор переезда
    └── dotfiles-push.*     автопуш по таймеру
```

## Переезд на новую ОС

```bash
git clone <url> ~/dotfiles
cd ~/dotfiles
./install.sh -p -a     # -p = pacman, -a = flatpak + AppImage
```

Скрипт идемпотентен: существующие файлы не перезаписывает молча, а сначала
кладёт в `~/.local/share/dotfiles-backup/<дата-время>/`. Повторный запуск
ничего не ломает. Живое состояние Noctalia и уже скачанные AppImage тоже
не трогает.

Опции: `-n` (dry-run, показать что будет), `-N` (не перезагружать сессию),
`-p` (пакеты из `packages.txt`), `-f` (flatpak), `-A` (AppImage),
`-a` (flatpak + AppImage), `-h`.

**Подробный разбор: [`docs/portability.md`](docs/portability.md)** — слои
установки, кто откуда берёт цвет, плагины Noctalia, инвентарь приложений и
шпаргалка проверки.

### Первый вход: что доделать руками

1. **Включить шаблоны в Noctalia**: Settings → Templates → **KColorScheme**
   и **Alacritty**. Первый пишет `~/.local/share/color-schemes/noctalia.colors`
   и `~/.config/kdeglobals` (тема Qt/KDE-приложений), второй —
   `~/.config/alacritty/themes/noctalia.toml` (тема терминала). Без них
   Dolphin остаётся в Breeze, а терминал — на дефолтной палитре;
   `install.sh` об этом предупредит и его можно перезапустить после.
2. **Скачать AppImage без стабильных ссылок**: TickTick, LM Studio,
   LM Studio Hub. Ссылки — в `packages-appimage.txt` и в
   [`docs/portability.md`](docs/portability.md); `install.sh -A` их напечатает.
3. **Создать сессию niri** (WM-сессия / tty). `packages.txt` ставит бинари,
   но не настраивает автозапуск — это зависит от того, чем ты входишь.
   Сама сессия — `niri.desktop` из пакета `niri`.
4. **Перезапустить открытые терминалы**: они держат прежнее окружение.

Проверить, что всё встало:

```bash
niri validate                                        # config is valid
kreadconfig6 --file ~/.config/kdeglobals --group KDE --key color-scheme   # noctalia
ls /usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so        # тема Qt есть
ls ~/.config/alacritty/themes/noctalia.toml                               # тема терминала
cat ~/.local/state/dotfiles/theme-overview.kdl                            # тема обзора niri
systemctl --user is-active noctalia-overview-theme.path                   # слушает тему
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
перезаписывает своим, а `gtk-theme` — нет, поэтому GTK3-приложения были бы
тёмными навсегда. Лечится синхронизатором
`local/bin/gtk3-theme-sync` (юнит `gtk3-theme-sync.path` следит за dconf):
`prefer-dark` → `adw-gtk3-dark`, иначе `adw-gtk3`. Чужие темы он не трогает —
если поставил не `adw-gtk3`, отключи синхронизацию через
`systemctl --user disable --now gtk3-theme-sync.path`. Подробности в
[`docs/portability.md`](docs/portability.md).

### Состояние Noctalia — теперь в репозитории

Раньше панель, виджеты и плагины жили только в
`~/.local/state/noctalia/settings.toml` и перекрывали `config/noctalia/config.toml`,
из-за чего переезд не воспроизводил вид. Сейчас есть снимок
`config/noctalia/settings.toml` (`noctalia config export`), который `install.sh`
сеет на месте — **только если файла нет**, живое состояние не трогает.

Обновить снимок после правок в Noctalia:

```bash
noctalia config export > ~/dotfiles/config/noctalia/settings.toml
```

Машинно-зависимое внутри снимка (координаты виджетов, имена мониторов
`eDP-1`/`HDMI-A-1`, пресет `One Dark Two`) помечено в шапке файла и на другой
машине безвредно.

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
| `config/alacritty/alacritty.toml` | терминал: шрифт, курсор, бинды, import темы |
| `config/environment.d/98-qt-platformtheme.conf` | тема Qt-приложений для systemd-юнитов |
| `local/bin/kiview-quicklook.sh` | Quick Look: забирает выделение из Dolphin, открывает в Kiview |
| `local/bin/klipper-shim.py` | шим `org.kde.klipper` — без него Kiview вне Plasma не работает |
| `config/systemd/user/klipper-shim.service` | автозапуск шима |
| `local/share/kio/servicemenus/kiview.desktop` | Quick Preview в правом клике Dolphin |

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

## Alacritty: тема и раскладки

Тема приходит из `themes/noctalia.toml` (её пишет шаблон `alacritty` в
Noctalia), а `alacritty.toml` только импортирует её:

```toml
[general]
import = ["~/.config/alacritty/themes/noctalia.toml"]
```

**Своих `[colors]` в этом файле быть не должно.** По `alacritty(5)`: «Imports
are loaded in order… with the importing file being loaded last. If a field is
already present in a previous import, it will be replaced» — то есть
`import` перебивается любым значением, объявленным в самом `alacritty.toml`.
Именно так выглядел залипший Nord: тема обновлялась, а фон перекрывался
хардкодом. По той же причине убран `decorations_theme_variant = "Dark"`:
без него заголовок окна следует за палитрой сам.

**Бинды не работают в русской раскладке.** Alacritty ищет бинд по keysym,
который прислала активная раскладка: физическая `C` в RU даёт `с`, и
`Ctrl+Shift+C` не срабатывает. У буквенных биндов в конфиге есть
кириллические дубли (`V→м`, `C→с`, `F→а`, `B→и`, `L→д`); регистр не важен —
Alacritty приводит и бинд, и ввод к нижнему (`config/bindings.rs`:
`keycode.to_lowercase()`, `alacritty/src/input/keyboard.rs`:
`Key::Character(ch.to_lowercase())`). Небуквенные клавиши (`=`, `-`, `0`,
`PageUp`) в обеих раскладках одинаковы, дублей не требуют.

Сам **niri** от этого не страдает: при резолве латинских клавиш он берёт
первую раскладку из списка (`layout "us,ru"`), поэтому `Mod+E` работает
в любой (`Configuration: Key Bindings` в вики niri).

## Плагин winlist

`local/share/noctalia/plugins/niri-windows/` — самописный виджет, показывает
окна текущего воркспейса, разложенные вокруг фокусного.

`plugin_api = 30` в `plugin.toml` подобран под Noctalia 5.1.0 (поддерживает 3–30).
При обновлении Noctalia проверь: `plugin.toml` → `plugin_api`, иначе виджет
молча не загрузится.

Правь **здесь**, в репо. Копия в `~/01_Projects/niri-windows/` — устарела
(в ней нет комментария про `pos_in_scrolling_layout`), её можно удалить.

## Quick Look (Mod+Space в Dolphin)

Превью файла как в macOS: встать на файл в Dolphin → `Mod+Space`.
Управление в окне: `←/→` — листать, `Esc/q` — закрыть, `Enter/w` — открыть
в родной программе. Голый `Space` не используется осознанно: бинды niri
глобальные, он бы съедал пробел при печати везде.

Цепочка: бинд в `cfg/keybinds.kdl` → `local/bin/kiview-quicklook.sh`
(проверяет фокус на Dolphin, дёргает его `copy_location` по DBus, читает
путь из буфера через `wl-paste`, буфер потом восстанавливает) →
`flatpak io.github.nyre221.kiview -s <путь>`. Правый клик → Quick Preview
работает и без всего этого (путь приходит через `%F` напрямую).

Зачем шим: flatpak-сборка Kiview во всех режимах ходит в
`org.kde.klipper`, а Klipper живёт только в Plasma — без
`klipper-shim.py` окно падает с `The name is not activatable`. Шим висит
systemd-юнитом, `install.sh` включает его сам.

Диагностика — `/tmp/kiview-quicklook.log` (последние 50 строк):
`SKIP` = фокус не на Dolphin, `FAIL no bus` = Dolphin ещё не встал на
шину, `enabled=false` = файл не выделен, `OPEN <путь>` = всё хорошо,
дальше смотреть выхлоп самого Kiview (он тоже пишется в лог).

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
