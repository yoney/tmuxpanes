-- tmuxpanes.nvim utilities
-- Helper functions for tmux interaction

local M = {}

-- Execute a tmux command and return the output
function M.tmux_cmd(command)
  local cmd = "tmux " .. command .. " 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  local ok = handle:close()
  if not ok then
    return nil
  end
  if not result then
    return ""
  end
  return (result:gsub("%s+$", ""))
end

-- Get detailed info about a specific pane
function M.get_pane_info(target)
  local format =
    "#{pane_id}\t#{pane_pid}\t#{pane_start_command}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_active}\t#{pane_dead}"
  local output = M.tmux_cmd("display-message -t " .. target .. " -p '" .. format .. "'")

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
  return M.tmux_cmd("display-message -t " .. target .. " -p '#{pane_id}'") ~= nil
end

-- Get pane by pattern (find pane running a specific command)
function M.find_pane_by_command(pattern)
  local cmd = string.format(
    "tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}' 2>/dev/null"
  )

  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  for line in handle:lines() do
    local target, command = line:match("^(.-)\t(.+)$")
    if target and command and command:match(pattern) then
      handle:close()
      return target
    end
  end
  handle:close()

  return nil
end

-- Capture pane output
function M.capture_pane(target, lines)
  lines = lines or 100
  local output = M.tmux_cmd("capture-pane -t " .. target .. " -p -S -" .. lines)
  return output
end

-- Resize pane
function M.resize_pane(target, direction, amount)
  amount = amount or 10
  local resize_cmd = "resize-pane -t " .. target .. " "

  if direction == "up" then
    resize_cmd = resize_cmd .. "-U " .. amount
  elseif direction == "down" then
    resize_cmd = resize_cmd .. "-D " .. amount
  elseif direction == "left" then
    resize_cmd = resize_cmd .. "-L " .. amount
  elseif direction == "right" then
    resize_cmd = resize_cmd .. "-R " .. amount
  end

  return M.tmux_cmd(resize_cmd)
end

-- Zoom pane (toggle)
function M.zoom_pane(target)
  return M.tmux_cmd("resize-pane -t " .. target .. " -Z")
end

-- Send control character (e.g., Ctrl+C)
function M.send_control(target, char)
  vim.fn.system({ "tmux", "send-keys", "-t", target, "C-" .. char })
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
  vim.fn.system({ "tmux", "send-keys", "-t", target, mapped_key })
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
  local session = M.tmux_cmd("display-message -p '#S'")
  if not session then
    return {}
  end

  local output = M.tmux_cmd("list-windows -t " .. session .. " -F '#{window_index}:#{window_name}'")
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
