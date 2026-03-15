-- tmuxpanes.nvim

-- Ensure the plugin is only loaded once
if vim.g.loaded_tmuxpanes then
  return
end
vim.g.loaded_tmuxpanes = 1

-- Create commands immediately (can be called before setup)
local tmuxpanes = require("tmuxpanes")
tmuxpanes.create_commands()
