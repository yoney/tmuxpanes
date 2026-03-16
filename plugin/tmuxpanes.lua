-- tmuxpanes.nvim

-- Ensure the plugin is only loaded once
if vim.g.loaded_tmuxpanes then
  return
end
vim.g.loaded_tmuxpanes = 1

local tmuxpanes = require("tmuxpanes")

if not tmuxpanes.check_version() then
  return
end

-- Create commands immediately (can be called before setup)
tmuxpanes.create_commands()
