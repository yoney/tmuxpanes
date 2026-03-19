# Testing tmuxpanes.nvim

## Minimal Test (without Telescope)

Run the isolated test environment:

```bash
# From repo root (requires --clean for proper isolation)
nvim --clean -u test/minimal.lua

# Or with the helper script
./test/scripts/test.sh
```

This environment:
- Isolates from your personal Neovim config
- Blocks Telescope from loading (simulates missing dependency)
- Uses `selector = "ui"` by default (or override with `SELECTOR` env var)
- Provides status on startup

## Testing Different Selectors

Set the `SELECTOR` environment variable:

```bash
# Test with inputlist (command-line numbered list)
SELECTOR=inputlist nvim --clean -u test/minimal.lua

# Test with ui (vim.ui.select clean fallback, shows built-in floating picker)
SELECTOR=ui nvim --clean -u test/minimal.lua
```
