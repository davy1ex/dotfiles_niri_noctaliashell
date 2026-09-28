# niri-windows

A [Noctalia](https://noctalia.dev) bar plugin for [niri](https://github.com/niri-wm/niri) that shows the current workspace's windows **split around the focused one** — macOS-style.

![screenshot](screenshot.png)

- Focused window **centered** with its icon and title
- Windows to the **left and right** of it flanking on both sides (dimmed)
- **Click any icon** to focus that window
- Sorted by real layout position (not creation order)
- Per-monitor: each bar shows its own output's workspace
- Hides itself on empty workspaces

## Requirements

- [niri](https://github.com/niri-wm/niri) (with `niri msg` IPC)
- [Noctalia](https://noctalia.dev) v5+ (plugin API 30)

## Installation

Copy the plugin into Noctalia's local plugins directory:

```sh
mkdir -p ~/.local/share/noctalia/plugins
cp -r niri-windows ~/.local/share/noctalia/plugins/
```

Then enable it:

```sh
noctalia msg plugins enable davy1ex/niri-windows
```

## Configuration

Add the widget to your bar in `~/.config/noctalia/config.toml`:

```toml
[bar.default]
start  = ["launcher", "wallpaper", "workspaces"]
center = ["winlist"]
end    = ["tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "keyboard_layout", "clock", "session"]

[widget.winlist]
type = "davy1ex/niri-windows:winlist"
```

Config hot-reloads automatically. To force it:

```sh
noctalia msg config-reload
```

## Settings

Edit in **Settings → Plugins → Niri Windows** (gear icon), or in `config.toml`:

| Setting | Type | Default | Description |
|---|---|---|---|
| `icon_size` | int | 18 | Window icon size in pixels (12–32) |
| `max_side` | int | 4 | Max window icons per side (1–8) |
| `title_max_length` | int | 28 | Max characters in the focused title (8–80) |

```toml
[widget.winlist]
type = "davy1ex/niri-windows:winlist"
icon_size = 20
max_side = 5
title_max_length = 40
```

## How it works

- **Service** (`service.luau`) polls `niri msg --json windows` every 500 ms, groups windows by their workspace's output, sorts them by niri's real layout position (`pos_in_scrolling_layout` — column = left→right), resolves app icons, and publishes the result through `noctalia.state`.
- **Widget** (`widget.luau`) watches that state, picks the list for its own monitor (`barWidget.outputName()`), and renders a declarative `ui.*` tree: left icons, focused icon + title, right icons. Clicking an icon runs `niri msg action focus-window --id <id>`.

## Development

Edit the `.luau` files and they hot-reload. Check logs with:

```sh
noctalia msg log-level-set debug   # if needed
```

Validate the plugin manifest:

```sh
noctalia plugins lint ~/.local/share/noctalia/plugins/niri-windows
```
