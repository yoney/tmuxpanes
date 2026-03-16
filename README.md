# tmuxpanes.nvim

A Neovim plugin for sending text from Neovim to another tmux pane.

Repository: <https://github.com/yoney/tmuxpanes>

## Requirements

- Neovim >= 0.9.0
- tmux (must be running inside a tmux session)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yoney/tmuxpanes",
  dependencies = {
    -- Optional: for better UI
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("tmuxpanes").setup()
  end,
}
```

## Configuration

```lua
require("tmuxpanes").setup({
  -- Default keymap prefix (set to false to disable default keymaps)
  prefix = "<leader>t",

  -- Direct picker mapping, kept off the bare prefix to avoid conflicts
  picker_mapping = "<leader>tt",

  -- Session scope for pane pickers: "all" or "current"
  session_scope = "all",

  -- Whether to include current pane in the list
  include_current = false,

  -- Format for pane display using tmux format strings
  -- See: https://man7.org/linux/man-pages/man1/tmux.1.html#FORMATS
  format = "[#{session_name}] #{window_name}:#{pane_index} - #{pane_current_command}",

  -- Picker backend: "auto", "telescope", "ui", or "inputlist"
  -- "auto" prefers Telescope when installed, then falls back.
  selector = "auto",

  -- Number of pane lines shown in Telescope preview windows
  preview_lines = 120,

  -- Prepend path and line number to line/selection sends
  include_location = true,

  -- Path style for location prefixes: "absolute", "git_relative", or "cwd_relative"
  location_path = "absolute",
})
```

## Usage

### Default Keymaps (if `prefix = "<leader>t"`)

| Keymap | Mode | Description |
|--------|------|-------------|
| `<leader>tt` | Normal | Show tmux panes using configured session scope |
| `<leader>ta` | Normal | Show tmux panes from all sessions |
| `<leader>tl` | Normal | Show tmux panes from current session |
| `<leader>ts` | Normal/Visual | Send current line/selection to selected pane |
| `<leader>tS` | Normal/Visual | Send current line/selection with Enter |
| `<leader>tc` | Normal | Send a typed command to pane |
| `<leader>te` | Normal/Visual | Open editable draft before sending |
| `<leader>tr` | Normal/Visual | Send to last saved pane |
| `<leader>tR` | Normal/Visual | Send to last saved pane with Enter |
| `<leader>tp` | Normal | Show which pane is saved as last used |

### Commands

| Command | Description |
|---------|-------------|
| `:TmuxPaneList` | List tmux panes using configured session scope |
| `:TmuxPaneListAll` | List tmux panes from all sessions |
| `:TmuxPaneListCurrent` | List tmux panes from current session |
| `:TmuxPaneSend <text>` | Send text to a selected pane |
| `:TmuxPaneSendLine` | Send current line to a pane |
| `:'<,'>TmuxPaneSendVisual` | Send visual selection to a pane |
| `:TmuxPaneEdit` | Open an editable draft from the current line or active selection |
| `:TmuxPaneLast` | Show the last used pane |
| `:TmuxPaneRepeat` | Send current line to the last used pane |
| `:TmuxPaneRepeatEnter` | Send current line to the last used pane with Enter |

## Behavior

- `<leader>tt` uses `session_scope`; `<leader>ta` forces all sessions and `<leader>tl` limits to the current session.
- `<leader>ts` and `<leader>tr` send text only; `<leader>tS` and `<leader>tR` also press Enter.
- `<leader>te` opens a floating draft editor so you can edit the payload before sending it.
- Line and visual sends prepend `path:line` or `path:start-end` when `include_location = true`; unnamed buffers send raw text without a fake path prefix.
- If the current buffer has unsaved changes, the location line is prefixed with `[modified]` so the receiver does not assume disk content matches exactly.
- `location_path = "absolute"` and `session_scope = "all"` are the defaults.
- In the draft editor, use `<C-s>` to send, `<C-e>` to send with Enter, `<C-r>` to send to the last pane, `<C-t>` to send to the last pane with Enter, and `q` to close.

### Telescope Extension

If you have `telescope.nvim` installed, the default picker will use it automatically when `selector = "auto"` or `selector = "telescope"`.
The preview window shows a snapshot of the highlighted tmux pane using `tmux capture-pane`.
Entries are numbered, and the Telescope keybindings (`<C-s>`, `<C-e>`, `<C-x>`) work in both the default picker and the dedicated extension.

You can also use the dedicated extension directly:

```lua
require("telescope").load_extension("tmuxpanes")

-- List panes with Telescope
require("telescope").extensions.tmuxpanes.tmuxpanes()

-- Or use the shortcut
require("telescope").extensions.tmuxpanes.list()
```

Keybindings in the Telescope picker:
- `<CR>` - Select pane (sets as last used)
- `<C-s>` - Send active visual selection, or current line if no visual selection exists
- `<C-e>` - Send active visual selection or current line, then press Enter
- `<C-x>` - Send custom command

### Lua API

```lua
local tmuxpanes = require("tmuxpanes")

-- List all panes
local panes = tmuxpanes.list_panes()

-- Get current line with file location prefix
local payload = tmuxpanes.get_current_line_payload()

-- Get visual selection with file location prefix
local visual_payload = tmuxpanes.get_selection_payload_from_marks()

-- Interactive pane selection and send
tmuxpanes.select_pane_and_send({
  text = "echo hello",
  send_enter = true
})

-- Open an editable floating draft before sending
tmuxpanes.open_send_editor({
  text = tmuxpanes.get_context_payload()
})

-- Send to last used pane
tmuxpanes.send_to_last_pane({ send_enter = true })
```

## License

MIT
