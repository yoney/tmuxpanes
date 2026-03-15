-- Telescope extension for tmuxpanes.nvim
-- Provides a fuzzy finder interface for tmux panes

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("This extension requires telescope.nvim")
end

local tmuxpanes = require("tmuxpanes")

-- Telescope picker for tmux panes
local function tmux_panes_picker(opts)
  opts = opts or {}

  return tmuxpanes.open_telescope_picker(vim.tbl_extend("force", opts, {
    prompt = opts.prompt or "Tmux Panes",
  }))
end

-- Register the extension
return telescope.register_extension({
  exports = {
    tmuxpanes = tmux_panes_picker,
    list = tmux_panes_picker,
  },
})
