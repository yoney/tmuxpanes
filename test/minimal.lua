-- test/minimal.lua
-- Minimal test environment for tmuxpanes.nvim without Telescope
-- Usage: nvim --clean -u test/minimal.lua

-- Completely isolate from user's config
vim.opt.runtimepath = {
  vim.env.VIMRUNTIME,
  vim.fn.fnamemodify(vim.env.VIMRUNTIME, ":h:h") .. "/lib/nvim",
}

-- Add plugin directory (parent of test/)
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:append(plugin_root .. "/after")

-- Block telescope
local original_require = _G.require
_G.require = function(modname)
  if modname:match("^telescope") then
    error("Telescope is not installed (simulated)")
  end
  return original_require(modname)
end

-- Basic settings
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.timeoutlen = 1000
vim.g.mapleader = " "

-- Allow selector override via environment variable
local selector = vim.env.SELECTOR or "ui"

-- Setup plugin with fallback selector
require("tmuxpanes").setup({
  selector = selector,
  prefix = "<leader>t",
})

-- Print status
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("Telescope available: " .. (pcall(require, "telescope") and "YES" or "NO"))
    print("Selector: " .. selector)
  end,
})
