-- tmuxpanes.nvim - Interact with tmux panes from Neovim
-- Main module

local M = {}

-- Default configuration
M.config = {
  -- Default keymap prefix (set to false to disable default keymaps)
  prefix = "<leader>t",
  -- Optional direct picker mapping. Set to false to disable.
  picker_mapping = "<leader>tt",
  -- Session scope for pane pickers: "all" or "current"
  session_scope = "all",
  -- Whether to include current pane in the list
  include_current = false,
  -- Format for pane display: [#{session_name}] #{window_name}:#{pane_index} - #{pane_current_command}
  format = "[#{session_name}] #{window_name}:#{pane_index} - #{pane_current_command}",
  -- Picker backend: "auto", "telescope", "ui", or "inputlist"
  selector = "auto",
  -- Number of lines to show in Telescope pane previews
  preview_lines = 120,
  -- Prepend buffer path and line range to line/selection sends
  include_location = true,
  -- Path style for location prefixes: "absolute", "git_relative", or "cwd_relative"
  location_path = "absolute",
}

-- Store panes list for the session
M.panes = {}
M.last_used_pane = nil
M.last_used_pane_display = nil
M._commands_created = false

function M.check_version()
  if vim.fn.has("nvim-0.9") == 1 then
    return true
  end

  vim.notify("tmuxpanes.nvim requires Neovim 0.9+", vim.log.levels.ERROR)
  return false
end

-- Get current tmux session
local function get_tmux_session()
  local handle = io.popen("tmux display-message -p '#S' 2>/dev/null")
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:gsub("%s+$", "")
end

-- Check if running inside tmux
local function is_in_tmux()
  return os.getenv("TMUX") ~= nil
end

-- List all tmux panes
function M.list_panes(scope)
  if not is_in_tmux() then
    vim.notify("Not running inside tmux", vim.log.levels.ERROR)
    return {}
  end

  scope = scope or M.config.session_scope or "all"

  local cmd = string.format(
    "tmux list-panes -a -F '%s\t%s' 2>/dev/null",
    M.config.format,
    "#{session_name}:#{window_index}.#{pane_index}"
  )

  local handle = io.popen(cmd)
  if not handle then
    vim.notify("Failed to list tmux panes", vim.log.levels.ERROR)
    return {}
  end

  local panes = {}
  local current_session = get_tmux_session()
  local current_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub("%s+$", "")

  for line in handle:lines() do
    local display, target = line:match("^(.-)\t(.+)$")
    if display and target then
      local session_name = target:match("^([^:]+)")
      -- Filter to the requested session scope, and optionally exclude current pane.
      if scope == "all" or session_name == current_session then
        local pane_id =
          vim.fn.system("tmux display-message -t " .. target .. " -p '#{pane_id}'"):gsub("%s+$", "")
        if M.config.include_current or pane_id ~= current_pane then
          table.insert(panes, {
            display = display,
            target = target,
            pane_id = pane_id,
          })
        end
      end
    end
  end
  handle:close()

  M.panes = panes
  return panes
end

-- Send keys to a specific tmux pane using literal mode (-l flag)
function M.send_to_pane(target, text)
  if not text or text == "" then
    return false
  end

  -- Use argv form so pane ids like %1 and literal text avoid shell quoting issues.
  vim.fn.system({ "tmux", "send-keys", "-t", target, "-l", "--", text })

  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to send to pane: " .. target, vim.log.levels.ERROR)
    return false
  else
    vim.notify("Sent to " .. target, vim.log.levels.INFO)
    return true
  end
end

-- Send keys with Enter key
function M.send_to_pane_with_enter(target, text)
  if not text or text == "" then
    return false
  end
  if not M.send_to_pane(target, text) then
    return false
  end
  -- Send Enter key
  vim.fn.system({ "tmux", "send-keys", "-t", target, "Enter" })
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to send Enter to pane: " .. target, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Get current line (for normal mode)
function M.get_current_line()
  return vim.fn.getline(".")
end

local function get_buffer_path()
  local absolute_path = vim.fn.expand("%:p")
  if absolute_path == "" then
    return nil
  end

  if M.config.location_path == "cwd_relative" then
    return vim.fn.fnamemodify(absolute_path, ":.")
  end

  if M.config.location_path == "git_relative" then
    local git_root = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
    if vim.v.shell_error == 0 and git_root and git_root ~= "" then
      local escaped_root = vim.pesc(git_root .. "/")
      local relative_path = absolute_path:gsub("^" .. escaped_root, "")
      if relative_path ~= absolute_path then
        return relative_path
      end
    end
  end

  return absolute_path
end

function M.format_text_with_location(text, start_line, end_line)
  if not text or text == "" or not M.config.include_location then
    return text
  end

  local path = get_buffer_path()
  if not path or path == "" then
    return text
  end
  local location
  if end_line and end_line ~= start_line then
    location = string.format("%s:%d-%d", path, start_line, end_line)
  else
    location = string.format("%s:%d", path, start_line)
  end

  if vim.bo.modified then
    location = "[modified] " .. location
  end

  return string.format("%s\n%s", location, text)
end

function M.get_current_line_payload()
  return M.format_text_with_location(M.get_current_line(), vim.fn.line("."))
end

local function get_text_from_positions(start_pos, end_pos, mode)
  local start_row = start_pos[2] - 1
  local end_row = end_pos[2] - 1
  local start_char_col = start_pos[3]
  local end_char_col = end_pos[3]

  if start_row > end_row or (start_row == end_row and start_char_col > end_char_col) then
    start_row, end_row = end_row, start_row
    start_char_col, end_char_col = end_char_col, start_char_col
  end

  mode = mode or vim.fn.visualmode() or "v"
  if mode == "V" then
    local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
    return table.concat(lines, "\n"), start_row + 1, end_row + 1
  end

  local start_line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1] or ""
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
  local start_char_count = vim.fn.strchars(start_line)
  local end_char_count = vim.fn.strchars(end_line)
  local start_char_index = math.min(math.max(start_char_col - 1, 0), start_char_count)
  local end_char_index = math.min(math.max(end_char_col, 0), end_char_count)
  local start_col = vim.str_byteindex(start_line, start_char_index)
  local end_col = vim.str_byteindex(end_line, end_char_index)

  local ok, text = pcall(vim.api.nvim_buf_get_text, 0, start_row, start_col, end_row, end_col, {})
  if not ok or not text or #text == 0 then
    return ""
  end

  return table.concat(text, "\n"), start_row + 1, end_row + 1
end

-- Get selection from visual marks (use after exiting visual mode)
function M.get_selection_from_marks()
  local start_pos = vim.fn.getcharpos("'<")
  local end_pos = vim.fn.getcharpos("'>")

  -- Check if marks are valid
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return ""
  end

  return get_text_from_positions(start_pos, end_pos, vim.fn.visualmode() or "v")
end

function M.get_selection_payload_from_marks()
  local text, start_line, end_line = M.get_selection_from_marks()
  if not text or text == "" then
    return ""
  end
  return M.format_text_with_location(text, start_line, end_line)
end

function M.get_active_visual_selection_payload()
  local mode = vim.api.nvim_get_mode().mode
  if not mode:match("^[vV\22]") then
    return ""
  end

  local cursor_pos = vim.fn.getcharpos(".")
  local anchor_pos = vim.fn.getcharpos("v")
  if cursor_pos[2] == 0 or anchor_pos[2] == 0 then
    return ""
  end

  local text, start_line, end_line = get_text_from_positions(anchor_pos, cursor_pos, mode)
  if not text or text == "" then
    return ""
  end

  return M.format_text_with_location(text, start_line, end_line)
end

function M.get_context_payload()
  local visual_text = M.get_active_visual_selection_payload()
  if visual_text and visual_text ~= "" then
    return visual_text
  end

  return M.get_current_line_payload()
end

-- Backwards compatibility
function M.get_selection()
  return M.get_current_line()
end

function M.attach_telescope_send_mappings(map, picker, opts)
  opts = opts or {}
  local modes = opts.modes or { "i", "n" }

  local function get_source_text()
    if opts.text ~= nil then
      return opts.text
    end

    return M.get_context_payload()
  end

  local function with_choice(callback)
    local choice = picker.get_choice()
    picker.close()
    if not choice then
      return
    end

    picker.remember_choice(choice, false)
    callback(choice)
  end

  local function send_choice(send_enter)
    with_choice(function(choice)
      local text = get_source_text()
      if not text or text == "" then
        vim.notify("No text to send", vim.log.levels.WARN)
        return
      end

      if send_enter then
        M.send_to_pane_with_enter(choice.target, text)
      else
        M.send_to_pane(choice.target, text)
      end
    end)
  end

  local function send_command()
    with_choice(function(choice)
      vim.ui.input({
        prompt = "Command: ",
      }, function(input)
        if input and input ~= "" then
          M.send_to_pane_with_enter(choice.target, input)
        end
      end)
    end)
  end

  for _, mode in ipairs(modes) do
    map(mode, "<C-s>", function()
      send_choice(false)
    end)

    map(mode, "<C-e>", function()
      send_choice(true)
    end)

    map(mode, "<C-x>", function()
      send_command()
    end)
  end

  return true
end

function M.open_telescope_picker(opts)
  opts = opts or {}
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_config, telescope_config = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  local ok_previewers, previewers = pcall(require, "telescope.previewers")
  local ok_utils, tmux_utils = pcall(require, "tmuxpanes.utils")

  if not (ok_pickers and ok_finders and ok_config and ok_actions and ok_state) then
    return false
  end

  local panes = opts.panes or M.list_panes(opts.scope)
  if #panes == 0 then
    vim.notify("No other panes found", vim.log.levels.WARN)
    return true
  end

  local entries = {}
  for index, pane in ipairs(panes) do
    entries[#entries + 1] = {
      index = index,
      pane = pane,
      display = string.format("%d. %s", index, pane.display),
      ordinal = string.format("%d %s", index, pane.display),
      target = pane.target,
    }
  end

  local previewer
  if ok_previewers and ok_utils then
    previewer = previewers.new_buffer_previewer({
      title = "Pane Output",
      define_preview = function(self, entry)
        local output = tmux_utils.capture_pane(entry.target, M.config.preview_lines)
        local lines = {}

        if output and output ~= "" then
          lines = vim.split(output, "\n", { plain = true })
        else
          lines = { "[no pane output captured]" }
        end

        vim.bo[self.state.bufnr].filetype = "sh"
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    })
  end

  pickers
    .new(opts, {
      prompt_title = opts.prompt or "Tmux Panes",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry.pane,
            display = entry.display,
            ordinal = entry.ordinal,
            target = entry.target,
          }
        end,
      }),
      sorter = telescope_config.values.generic_sorter(opts),
      previewer = previewer,
      attach_mappings = function(prompt_bufnr, map)
        local function get_choice()
          local selection = action_state.get_selected_entry()
          if selection then
            return selection.value
          end
        end

        local function remember_choice(choice, notify)
          M.last_used_pane = choice.pane_id or choice.target
          M.last_used_pane_display = choice.display
          if notify ~= false then
            vim.notify("Selected pane: " .. choice.display, vim.log.levels.INFO)
          end
        end

        actions.select_default:replace(function()
          local choice = get_choice()
          actions.close(prompt_bufnr)
          if choice then
            if opts.on_select then
              opts.on_select(choice)
            else
              remember_choice(choice, opts.notify)
            end
          end
        end)

        M.attach_telescope_send_mappings(map, {
          close = function()
            actions.close(prompt_bufnr)
          end,
          get_choice = get_choice,
          remember_choice = remember_choice,
        }, {
          text = opts.text,
        })

        if opts.attach_mappings then
          return opts.attach_mappings(prompt_bufnr, map, {
            close = function()
              actions.close(prompt_bufnr)
            end,
            get_choice = get_choice,
            remember_choice = remember_choice,
          })
        end

        return true
      end,
    })
    :find()

  return true
end

-- Select pane and send text to it
function M.select_pane(callback, opts)
  opts = opts or {}
  local panes = M.list_panes(opts.scope)
  if #panes == 0 then
    vim.notify("No other panes found", vim.log.levels.WARN)
    return
  end

  local function on_choice(choice, idx)
    if choice then
      M.last_used_pane = choice.pane_id or choice.target
      M.last_used_pane_display = choice.display
      if opts.notify ~= false then
        vim.notify("Selected pane: " .. choice.display, vim.log.levels.INFO)
      end
      if callback then
        callback(choice, idx)
      end
    end
  end

  if M.config.selector == "telescope" or M.config.selector == "auto" then
    if
      M.open_telescope_picker({
        panes = panes,
        prompt = opts.prompt,
        notify = opts.notify,
        on_select = on_choice,
      })
    then
      return
    end
    if M.config.selector == "telescope" then
      vim.notify(
        "Telescope picker requested but telescope.nvim is not available",
        vim.log.levels.WARN
      )
    end
  end

  if M.config.selector == "ui" or M.config.selector == "auto" then
    vim.ui.select(panes, {
      prompt = opts.prompt or "Select tmux pane:",
      format_item = function(item)
        return item.display
      end,
    }, on_choice)
    return
  end

  local lines = { opts.prompt or "Select tmux pane:" }
  for index, pane in ipairs(panes) do
    lines[#lines + 1] = string.format("%d. %s", index, pane.display)
  end

  local choice_index = vim.fn.inputlist(lines)
  if choice_index < 1 or choice_index > #panes then
    return
  end

  on_choice(panes[choice_index], choice_index)
end

-- Select pane and send text to it
function M.select_pane_and_send(opts)
  opts = opts or {}
  local text = opts.text

  if not text or text == "" then
    vim.notify("No text to send", vim.log.levels.WARN)
    return
  end

  M.select_pane(function(pane)
    if opts.send_enter then
      M.send_to_pane_with_enter(pane.target, text)
    else
      M.send_to_pane(pane.target, text)
    end
  end, {
    prompt = "Select tmux pane to send text:",
  })
end

-- Interactive command: send to pane
function M.send_command()
  vim.ui.input({
    prompt = "Command to send: ",
    default = "",
  }, function(input)
    if input and input ~= "" then
      M.select_pane_and_send({ text = input, send_enter = true })
    end
  end)
end

function M.open_send_editor(opts)
  opts = opts or {}
  local initial_text = opts.text or M.get_context_payload()
  if not initial_text or initial_text == "" then
    vim.notify("No text to edit", vim.log.levels.WARN)
    return
  end

  local source_filetype = vim.bo.filetype
  local buf = vim.api.nvim_create_buf(false, true)
  local hint_text
  if M.last_used_pane then
    hint_text = "[tmuxpanes] <C-s> send | <C-e> send+Enter | <C-r> last | <C-t> last+Enter"
  else
    hint_text = "[tmuxpanes] <C-s> send | <C-e> send+Enter | no last pane yet"
  end
  local lines = vim.split(initial_text, "\n", { plain = true })
  local width = math.min(math.max(math.floor(vim.o.columns * 0.7), 60), vim.o.columns - 4)
  local height = math.min(math.max(math.floor(vim.o.lines * 0.5), 8), vim.o.lines - 6)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  local win_opts = {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = row,
    col = col,
  }
  win_opts.title = hint_text
  win_opts.title_pos = "center"
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = source_filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local function close_editor()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function get_payload()
    local payload = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    if payload == "" then
      vim.notify("No text to send", vim.log.levels.WARN)
      return nil
    end
    return payload
  end

  local function send_to_selected(send_enter)
    local payload = get_payload()
    if not payload then
      return
    end

    M.select_pane(function(pane)
      local ok
      if send_enter then
        ok = M.send_to_pane_with_enter(pane.target, payload)
      else
        ok = M.send_to_pane(pane.target, payload)
      end
      if ok then
        close_editor()
      end
    end, {
      prompt = "Select tmux pane to send text:",
    })
  end

  local function send_to_last(send_enter)
    local payload = get_payload()
    if not payload then
      return
    end
    if not M.last_used_pane then
      vim.notify(
        "No last pane used. Select one first with <leader>tt or <leader>ts",
        vim.log.levels.WARN
      )
      return
    end

    if M.send_to_last_pane({ text = payload, send_enter = send_enter }) then
      close_editor()
    end
  end

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    send_to_selected(false)
  end, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-e>", function()
    send_to_selected(true)
  end, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-r>", function()
    send_to_last(false)
  end, map_opts)
  vim.keymap.set({ "n", "i" }, "<C-t>", function()
    send_to_last(true)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function()
    close_editor()
  end, map_opts)

  local last_line = math.max(vim.api.nvim_buf_line_count(buf), 1)
  local last_col = #(vim.api.nvim_buf_get_lines(buf, last_line - 1, last_line, false)[1] or "")
  vim.api.nvim_win_set_cursor(win, { last_line, last_col })
end

-- Quick send to last used pane
function M.send_to_last_pane(opts)
  opts = opts or {}
  local text = opts.text

  if not text or text == "" then
    vim.notify("No text to send", vim.log.levels.WARN)
    return false
  end

  if not M.last_used_pane then
    vim.notify(
      "No last pane used. Select one first with <leader>tt or <leader>ts",
      vim.log.levels.WARN
    )
    return false
  end

  if opts.send_enter then
    return M.send_to_pane_with_enter(M.last_used_pane, text)
  else
    return M.send_to_pane(M.last_used_pane, text)
  end
end

-- Show current last used pane
function M.show_last_pane()
  if M.last_used_pane then
    vim.notify("Last pane: " .. (M.last_used_pane_display or M.last_used_pane), vim.log.levels.INFO)
  else
    vim.notify("No last pane selected yet", vim.log.levels.WARN)
  end
end

-- Create user commands
function M.create_commands()
  if M._commands_created then
    return
  end
  M._commands_created = true

  vim.api.nvim_create_user_command("TmuxPaneList", function()
    M.select_pane(nil, { prompt = "Tmux panes:" })
  end, { desc = "List tmux panes" })

  vim.api.nvim_create_user_command("TmuxPaneListAll", function()
    M.select_pane(nil, { prompt = "Tmux panes (all sessions):", scope = "all" })
  end, { desc = "List tmux panes from all sessions" })

  vim.api.nvim_create_user_command("TmuxPaneListCurrent", function()
    M.select_pane(nil, { prompt = "Tmux panes (current session):", scope = "current" })
  end, { desc = "List tmux panes from current session" })

  vim.api.nvim_create_user_command("TmuxPaneSend", function(opts)
    M.select_pane_and_send({ text = opts.args, send_enter = true })
  end, { nargs = "?", desc = "Send text to tmux pane" })

  vim.api.nvim_create_user_command("TmuxPaneSendLine", function()
    M.select_pane_and_send({ text = M.get_current_line_payload(), send_enter = true })
  end, { desc = "Send current line to tmux pane" })

  vim.api.nvim_create_user_command("TmuxPaneSendVisual", function()
    M.select_pane_and_send({ text = M.get_selection_payload_from_marks(), send_enter = true })
  end, { range = true, desc = "Send visual selection to tmux pane" })

  vim.api.nvim_create_user_command("TmuxPaneEdit", function()
    M.open_send_editor({ text = M.get_context_payload() })
  end, { desc = "Open editable draft for tmux send" })

  vim.api.nvim_create_user_command("TmuxPaneLast", function()
    M.show_last_pane()
  end, { desc = "Show last used tmux pane" })

  vim.api.nvim_create_user_command("TmuxPaneRepeat", function()
    M.send_to_last_pane({ text = M.get_current_line_payload() })
  end, { desc = "Send current line to last used tmux pane" })

  vim.api.nvim_create_user_command("TmuxPaneRepeatEnter", function()
    M.send_to_last_pane({ text = M.get_current_line_payload(), send_enter = true })
  end, { desc = "Send current line to last used tmux pane with Enter" })
end

-- Setup function
function M.setup(opts)
  if not M.check_version() then
    return
  end

  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Create commands
  M.create_commands()

  -- Set up keymaps if prefix is set
  if M.config.prefix then
    local prefix = M.config.prefix

    if M.config.picker_mapping then
      vim.keymap.set("n", M.config.picker_mapping, function()
        M.select_pane(nil, { prompt = "Tmux panes:" })
      end, { desc = "Select tmux pane" })
    end

    vim.keymap.set("n", prefix .. "a", function()
      M.select_pane(nil, { prompt = "Tmux panes (all sessions):", scope = "all" })
    end, { desc = "Select tmux pane from all sessions" })

    vim.keymap.set("n", prefix .. "l", function()
      M.select_pane(nil, { prompt = "Tmux panes (current session):", scope = "current" })
    end, { desc = "Select tmux pane from current session" })

    -- Send current line (normal mode)
    vim.keymap.set("n", prefix .. "s", function()
      M.select_pane_and_send({ text = M.get_current_line_payload() })
    end, { desc = "Send current line to tmux pane" })

    -- Send visual selection (visual mode)
    vim.keymap.set("v", prefix .. "s", function()
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
      vim.schedule(function()
        M.select_pane_and_send({ text = M.get_selection_payload_from_marks() })
      end)
    end, { desc = "Send selection to tmux pane" })

    -- Send with Enter (normal mode)
    vim.keymap.set("n", prefix .. "S", function()
      M.select_pane_and_send({ text = M.get_current_line_payload(), send_enter = true })
    end, { desc = "Send line to tmux pane (with Enter)" })

    -- Send with Enter (visual mode)
    vim.keymap.set("v", prefix .. "S", function()
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
      vim.schedule(function()
        M.select_pane_and_send({ text = M.get_selection_payload_from_marks(), send_enter = true })
      end)
    end, { desc = "Send selection to tmux pane (with Enter)" })

    -- Send command
    vim.keymap.set("n", prefix .. "c", function()
      M.send_command()
    end, { desc = "Send command to tmux pane" })

    vim.keymap.set("n", prefix .. "e", function()
      M.open_send_editor({ text = M.get_current_line_payload() })
    end, { desc = "Edit current line before sending" })

    vim.keymap.set("v", prefix .. "e", function()
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
      vim.schedule(function()
        M.open_send_editor({ text = M.get_selection_payload_from_marks() })
      end)
    end, { desc = "Edit selection before sending" })

    vim.keymap.set("n", prefix .. "r", function()
      M.send_to_last_pane({ text = M.get_current_line_payload() })
    end, { desc = "Repeat send to last tmux pane" })

    vim.keymap.set("v", prefix .. "r", function()
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
      vim.schedule(function()
        M.send_to_last_pane({ text = M.get_selection_payload_from_marks() })
      end)
    end, { desc = "Repeat send selection to last tmux pane" })

    vim.keymap.set("n", prefix .. "R", function()
      M.send_to_last_pane({ text = M.get_current_line_payload(), send_enter = true })
    end, { desc = "Repeat send to last pane (with Enter)" })

    vim.keymap.set("v", prefix .. "R", function()
      local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
      vim.api.nvim_feedkeys(esc, "nx", false)
      vim.schedule(function()
        M.send_to_last_pane({ text = M.get_selection_payload_from_marks(), send_enter = true })
      end)
    end, { desc = "Repeat send selection to last pane (with Enter)" })

    -- Show last pane info
    vim.keymap.set("n", prefix .. "p", function()
      M.show_last_pane()
    end, { desc = "Show last used pane" })
  end
end

return M
