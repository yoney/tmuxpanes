-- tmuxpanes.nvim

-- Ensure the plugin is only loaded once
if vim.g.loaded_tmuxpanes then
  return
end
vim.g.loaded_tmuxpanes = 1

if vim.fn.has("nvim-0.7") == 0 then
  vim.notify("tmuxpanes.nvim requires Neovim 0.7+", vim.log.levels.ERROR)
  return
end

-- Create commands immediately (can be called before setup)
local tmuxpanes = require("tmuxpanes")
tmuxpanes.create_commands()
