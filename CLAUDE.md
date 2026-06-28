# CLAUDE.md – Projektregeln XP12-LUA

## Umgebung
- Skriptsprache: Lua (FlyWithLua NG+ für X-Plane 12)
- Entwicklung auf macOS, Ausführung auf Windows (X-Plane 12)

## FlyWithLua: Globale vs. lokale Funktionen

Funktionen die via String registriert werden, müssen **global** sein (kein `local`).
FlyWithLua wertet diese Strings im globalen Scope aus — lokale Funktionen sind dort unsichtbar.

Betrifft alle Registrierungsfunktionen:
- `do_sometimes("func()")`
- `do_often("func()")`
- `do_every_draw("func()")`
- `create_command(..., "func()", ...)`
- `add_macro(..., "code", "code", ...)`

**Richtig:**
```lua
function pitot_tick() ... end
do_sometimes("pitot_tick()")
```

**Falsch:**
```lua
local function pitot_tick() ... end  -- unsichtbar für FlyWithLua
do_sometimes("pitot_tick()")
```

Hilfsfunktionen die nur direkt aufgerufen werden, dürfen `local` bleiben.

## FlyWithLua: Gültige Callback-Funktionen

Nur diese Registrierungsfunktionen existieren in FlyWithLua NG+:

| Funktion | Aufrufhäufigkeit |
|---|---|
| `do_every_draw(s)` | Jeden Frame |
| `do_often(s)` | ~10× pro Sekunde |
| `do_sometimes(s)` | ~1× pro Sekunde |
| `do_on_keystroke(s)` | Bei Tastendruck |
| `do_on_mouse_click(s)` | Bei Mausklick |
| `create_command(name, desc, begin, cont, end)` | Command-Handler |
| `add_macro(name, on, off, default)` | Makro-Eintrag |

**Nicht verwenden** (existiert nicht):
- ~~`do_on_airport_load()`~~
- ~~`do_on_new_flight()`~~
| ~~`do_rarely(s)`~~ | existiert nicht — stattdessen `do_sometimes` mit manuellem Throttle |

## Projekt-Philosophie
- DataRefs nur zurücksetzen wenn sie auf den erwarteten Fehlerwert gesetzt sind
- Schrittweise vorgehen, ein Modul nach dem anderen
