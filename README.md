# Better at Gambling

Online casino party game for 2–8 players (Godot 4, typed GDScript). Fictional chips only.

## Setup
```bash
tools/setup_toolchain.sh          # Godot 4.7.2 + export templates (~1.3 GB) + GUT; add --no-templates to skip templates
```

## Test
```bash
scripts/test.sh                   # unit tests
scripts/test.sh all               # lint + unit + sim + integration + smoke + boot smoke
```

## Run
```bash
tools/godot/godot --path .                         # client (main menu)
tools/godot/godot --headless --path . -- --smoke-test   # boots 60 frames, exit 0 if clean
scripts/screenshot.sh res://ui/menus/main_menu.tscn     # PNG under build/screenshots/ (needs xvfb-run)
```

## Export
```bash
scripts/export.sh linux|windows|server
```

## Docs
- `docs/PROGRESS.md` – where the project is and the next step
- `docs/TODO.md` – milestone checklist
- `docs/DECISIONS.md`, `docs/TOOLCHAIN.md`, `docs/ARCHITECTURE.md`, `docs/GDD.md`
- `docs/MASTER_PROMPT.md` – the full design and implementation brief
