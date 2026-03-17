-- tmuxpanes.nvim utilities
-- Helper functions for tmux interaction

local M = {}

local function trim_trailing_whitespace(text)
  return (text or ""):gsub("%s+$", "")
end

local function run_tmux(args)
  local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
  if result.code ~= 0 then
    return nil, result
  end

  return trim_trailing_whitespace(result.stdout), result
end

-- Execute a tmux command and return the output
function M.tmux_cmd(command)
  if type(command) == "table" then
    return run_tmux(command)
  end

  local result = vim
    .system({ "sh", "-c", "tmux " .. command .. " 2>/dev/null" }, { text = true })
    :wait()
  if result.code ~= 0 then
    return nil
  end

  return trim_trailing_whitespace(result.stdout)
end

-- Get detailed info about a specific pane
function M.get_pane_info(target)
  local format =
    "#{pane_id}\t#{pane_pid}\t#{pane_start_command}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}\t#{pane_dead}"
  local output = M.tmux_cmd({ "display-message", "-t", target, "-p", format })

  if not output then
    return nil
  end

  local parts = vim.split(output, "\t", { plain = true, trimempty = false })

  return {
    pane_id = parts[1],
    pid = parts[2],
    start_command = parts[3],
    current_command = parts[4],
    current_path = parts[5],
    is_active = parts[6] == "1",
    is_dead = parts[7] == "1",
  }
end

-- Check if a pane exists
function M.pane_exists(target)
  return M.tmux_cmd({ "display-message", "-t", target, "-p", "#{pane_id}" }) ~= nil
end

-- Get pane by pattern (find pane running a specific command)
function M.find_pane_by_command(pattern)
  local output = M.tmux_cmd({
    "list-panes",
    "-a",
    "-F",
    "#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}",
  })
  if not output then
    return nil
  end

  for _, line in ipairs(vim.split(output, "\n", { plain = true, trimempty = true })) do
    local target, command = line:match("^(.-)\t(.+)$")
    if target and command and command:match(pattern) then
      return target
    end
  end

  return nil
end

-- Capture pane output
function M.capture_pane(target, lines)
  lines = lines or 100
  local output = M.tmux_cmd({ "capture-pane", "-t", target, "-p", "-S", "-" .. lines })
  return output
end

-- Resize pane
function M.resize_pane(target, direction, amount)
  amount = amount or 10
  if direction == "up" then
    return M.tmux_cmd({ "resize-pane", "-t", target, "-U", tostring(amount) })
  elseif direction == "down" then
    return M.tmux_cmd({ "resize-pane", "-t", target, "-D", tostring(amount) })
  elseif direction == "left" then
    return M.tmux_cmd({ "resize-pane", "-t", target, "-L", tostring(amount) })
  elseif direction == "right" then
    return M.tmux_cmd({ "resize-pane", "-t", target, "-R", tostring(amount) })
  end
  return nil
end

-- Zoom pane (toggle)
function M.zoom_pane(target)
  return M.tmux_cmd({ "resize-pane", "-t", target, "-Z" })
end

-- Send control character (e.g., Ctrl+C)
function M.send_control(target, char)
  vim.system({ "tmux", "send-keys", "-t", target, "C-" .. char }, { text = true }):wait()
end

-- Send special key
function M.send_key(target, key)
  local key_map = {
    ["enter"] = "Enter",
    ["return"] = "Enter",
    ["space"] = "Space",
    ["tab"] = "Tab",
    ["escape"] = "Escape",
    ["up"] = "Up",
    ["down"] = "Down",
    ["left"] = "Left",
    ["right"] = "Right",
    ["home"] = "Home",
    ["end"] = "End",
    ["pageup"] = "PageUp",
    ["pagedown"] = "PageDown",
    ["delete"] = "Delete",
    ["insert"] = "Insert",
    ["backspace"] = "BSpace",
  }

  local mapped_key = key_map[key:lower()] or key
  vim.system({ "tmux", "send-keys", "-t", target, mapped_key }, { text = true }):wait()
end

-- Clear pane (send Ctrl+L or 'clear' command)
function M.clear_pane(target)
  M.send_control(target, "l")
end

-- Interrupt pane (send Ctrl+C)
function M.interrupt_pane(target)
  M.send_control(target, "c")
end

-- Kill process in pane
function M.kill_pane_process(target)
  M.send_control(target, "c")
  -- Also try sending multiple interrupts
  for i = 1, 3 do
    vim.defer_fn(function()
      M.send_control(target, "c")
    end, i * 100)
  end
end

-- Get all windows in current session
function M.list_windows()
  local session = M.tmux_cmd({ "display-message", "-p", "#S" })
  if not session then
    return {}
  end

  local output =
    M.tmux_cmd({ "list-windows", "-t", session, "-F", "#{window_index}:#{window_name}" })
  if not output then
    return {}
  end

  local windows = {}
  for line in output:gmatch("[^\n]+") do
    local index, name = line:match("^(%d+):(.+)$")
    if index and name then
      table.insert(windows, {
        index = index,
        name = name,
        target = session .. ":" .. index,
      })
    end
  end

  return windows
end

return M
