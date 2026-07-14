-- planning/init.lua: calendar float + day-detail view.
-- ponytail: zero deps. nvim_open_win + vim.ui.input + extmarks.

local store = require("planning.store")

local M = {}

-- Layout (computed from terminal size at open time; see compute_layout)
local CELL_W = 14
local CELL_H = 4 -- 1 day-number line + (CELL_H-1) preview lines
local GAP = 1 -- space between cells (cols and rows)
local PREVIEW = 3 -- max entries shown in a cell before "+k more"
local WIN_RATIO = 0.8 -- target fraction of editor area

-- ponytail: clamp cell sizes so the grid stays readable on narrow terminals
-- and doesn't over-stretch on huge ones.
local CELL_W_MIN, CELL_W_MAX = 10, 30
local CELL_H_MIN, CELL_H_MAX = 4, 8

local function compute_layout()
  local target_w = math.floor(vim.o.columns * WIN_RATIO)
  local target_h = math.floor(vim.o.lines * WIN_RATIO)
  CELL_W = math.max(CELL_W_MIN, math.min(CELL_W_MAX, math.floor((target_w - 6 * GAP) / 7)))
  CELL_H = math.max(CELL_H_MIN, math.min(CELL_H_MAX, math.floor((target_h - 2 - 5 * GAP) / 6)))
  PREVIEW = CELL_H - 1
end

local function grid_size()
  return 7 * CELL_W + 6 * GAP, 2 + 6 * CELL_H + 5 * GAP
end

local function day_size()
  local w = math.min(math.floor(vim.o.columns * WIN_RATIO), 80)
  local h = math.min(math.floor(vim.o.lines * WIN_RATIO), 20)
  return math.max(w, 40), math.max(h, 8)
end

-- Status -> highlight group (nil = default text)
local STATUS_HL = {
  new = nil,
  in_progress = "WarningMsg",
  done = "String",
}
local STATUS_LABEL = { new = "New", in_progress = "In Progress", done = "Done" }

local ns = vim.api.nvim_create_namespace("planning")

local function define_hl()
  vim.api.nvim_set_hl(0, "PlanningToday", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "PlanningFocus", { link = "Visual", default = true })
end

-- Grid UI state
local grid = {
  win = nil,
  buf = nil,
  year = nil,
  month = nil,
  cur = { week = 1, day = 1 }, -- 1-indexed: week 1..6, day 1..7 (Mon..Sun)
}

-- Day-detail UI state
local day = {
  win = nil,
  buf = nil,
  y = nil,
  m = nil,
  d = nil,
}

-- ---------- date helpers ----------

local function month_title(y, m)
  return os.date("%B %Y", os.time({ year = y, month = m, day = 15 }))
end

-- 0-based offset of the 1st from Monday (Mon=0 .. Sun=6)
local function first_offset(y, m)
  local w = tonumber(os.date("%w", os.time({ year = y, month = m, day = 1 }))) -- Sun=0..Sat=6
  return (w == 0) and 6 or (w - 1)
end

local function days_in_month(y, m)
  return tonumber(os.date("%d", os.time({ year = y, month = m + 1, day = 0 })))
end

-- 0-based buffer column of day d (1..7)
local function col_of(d)
  return (d - 1) * (CELL_W + GAP)
end

-- 0-based buffer row of week w's top (1..6)
local function row_of(w)
  return 1 + (w - 1) * (CELL_H + GAP) -- +1 for header line
end

-- ---------- month grid render ----------

local function build_lines()
  local width = 7 * CELL_W + 6 * GAP
  local total_rows = 2 + 6 * CELL_H + 5 * GAP -- +2: header + gap row
  local blank = string.rep(" ", width)
  local lines = {}
  for i = 1, total_rows do lines[i] = blank end

  -- header: Mo Tu We Th Fr Sa Su
  local names = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
  local hdr = {}
  for d = 1, 7 do
    hdr[#hdr + 1] = names[d]
    hdr[#hdr + 1] = string.rep(" ", CELL_W - #names[d] + (d < 7 and GAP or 0))
  end
  lines[1] = table.concat(hdr)

  local offset = first_offset(grid.year, grid.month)
  local ndays = days_in_month(grid.year, grid.month)

  local function put(r, c, s)
    local line = lines[r]
    lines[r] = line:sub(1, c) .. s .. line:sub(c + #s + 1)
  end

  for w = 1, 6 do
    for d = 1, 7 do
      local idx = (w - 1) * 7 + (d - 1)
      local daynum = idx - offset + 1
      if daynum >= 1 and daynum <= ndays then
        local r0 = row_of(w) + 1 -- 1-based buffer row
        local c0 = col_of(d)
        put(r0, c0, tostring(daynum))
        local entries = store.entries(grid.year, grid.month, daynum)
        local show, overflow
        if #entries <= PREVIEW then
          show = entries
          overflow = nil
        else
          show = { entries[1], entries[2] }
          overflow = #entries - 2
        end
        for i, e in ipairs(show) do
          local txt = e.text
          if #txt > CELL_W - 1 then txt = txt:sub(1, CELL_W - 2) .. ">" end
          put(r0 + i, c0, txt)
        end
        if overflow then
          put(r0 + PREVIEW, c0, "+" .. overflow .. " more")
        end
      end
    end
  end
  return lines
end

local function apply_extmarks()
  vim.api.nvim_buf_clear_namespace(grid.buf, ns, 0, -1)
  local offset = first_offset(grid.year, grid.month)
  local ndays = days_in_month(grid.year, grid.month)
  local now = os.date("*t")
  for w = 1, 6 do
    for d = 1, 7 do
      local idx = (w - 1) * 7 + (d - 1)
      local daynum = idx - offset + 1
      if daynum >= 1 and daynum <= ndays then
        local r0 = row_of(w) -- 0-based
        local c0 = col_of(d)
        local numstr = tostring(daynum)
        local is_today = (grid.year == now.year and grid.month == now.month and daynum == now.day)
        vim.api.nvim_buf_set_extmark(grid.buf, ns, r0, c0, {
          end_col = c0 + #numstr,
          hl_group = is_today and "PlanningToday" or "Number",
          priority = 100,
        })
        local entries = store.entries(grid.year, grid.month, daynum)
        local show, overflow
        if #entries <= PREVIEW then
          show = entries
          overflow = nil
        else
          show = { entries[1], entries[2] }
          overflow = #entries - 2
        end
        for i, e in ipairs(show) do
          local txt = e.text
          if #txt > CELL_W - 1 then txt = txt:sub(1, CELL_W - 2) .. ">" end
          local hl = STATUS_HL[e.status]
          if hl then
            vim.api.nvim_buf_set_extmark(grid.buf, ns, r0 + i, c0, {
              end_col = c0 + #txt,
              hl_group = hl,
              priority = 100,
            })
          end
        end
        if overflow then
          local txt = "+" .. overflow .. " more"
          vim.api.nvim_buf_set_extmark(grid.buf, ns, r0 + PREVIEW, c0, {
            end_col = c0 + #txt,
            hl_group = "Comment",
          })
        end
      end
    end
  end
  -- focused cell: subtle background across all cell rows
  local w, d = grid.cur.week, grid.cur.day
  local r0 = row_of(w)
  local c0 = col_of(d)
  for i = 0, CELL_H - 1 do
    vim.api.nvim_buf_set_extmark(grid.buf, ns, r0 + i, c0, {
      end_col = c0 + CELL_W,
      hl_group = "PlanningFocus",
      priority = 90,
    })
  end
end

local function render()
  if not (grid.buf and vim.api.nvim_buf_is_valid(grid.buf)) then return end
  local lines = build_lines()
  vim.bo[grid.buf].modifiable = true
  vim.api.nvim_buf_set_lines(grid.buf, 0, -1, false, lines)
  vim.bo[grid.buf].modifiable = false
  apply_extmarks()
  if grid.win and vim.api.nvim_win_is_valid(grid.win) then
    pcall(vim.api.nvim_win_set_cursor, grid.win, { row_of(grid.cur.week) + 1, col_of(grid.cur.day) })
  end
end

-- ---------- grid navigation ----------

local function move(dw, dd)
  local idx = (grid.cur.week - 1) * 7 + grid.cur.day + dw * 7 + dd
  if idx < 1 then idx = 1 elseif idx > 42 then idx = 42 end
  grid.cur.week = math.floor((idx - 1) / 7) + 1
  grid.cur.day = ((idx - 1) % 7) + 1
  render()
end

local function shift_month(delta)
  local y, m = grid.year, grid.month + delta
  if m < 1 then m = 12; y = y - 1 elseif m > 12 then m = 1; y = y + 1 end
  grid.year = y
  grid.month = m
  grid.cur = { week = 1, day = 1 }
  -- land on day 1 of the new month if it's a real cell
  local offset = first_offset(y, m)
  local idx = offset + 1 -- cell index (0-based) for day 1
  grid.cur.day = ((idx) % 7) + 1
  grid.cur.week = math.floor(idx / 7) + 1
  if grid.win and vim.api.nvim_win_is_valid(grid.win) then
    vim.api.nvim_win_set_config(grid.win, { title = month_title(y, m), title_pos = "center" })
  end
  render()
end

local function close_grid()
  if grid.win and vim.api.nvim_win_is_valid(grid.win) then
    vim.api.nvim_win_close(grid.win, true)
  end
  grid.win = nil
  grid.buf = nil
end

-- ---------- day-detail view ----------

local function day_render()
  if not (day.buf and vim.api.nvim_buf_is_valid(day.buf)) then return end
  local entries = store.entries(day.y, day.m, day.d)
  local lines = {}
  for i, e in ipairs(entries) do
    lines[i] = string.format("[%s] %s", STATUS_LABEL[e.status], e.text)
  end
  if #lines == 0 then lines[1] = "  (no entries — press a to add)" end
  vim.bo[day.buf].modifiable = true
  vim.api.nvim_buf_set_lines(day.buf, 0, -1, false, lines)
  vim.bo[day.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(day.buf, ns, 0, -1)
  for i, e in ipairs(entries) do
    local hl = STATUS_HL[e.status]
    if hl then
      vim.api.nvim_buf_set_extmark(day.buf, ns, i - 1, 0, { end_col = #lines[i], hl_group = hl })
    end
  end
end

local function day_focus()
  if day.win and vim.api.nvim_win_is_valid(day.win) then
    pcall(vim.api.nvim_set_current_win, day.win)
  end
end

local function day_close()
  if day.win and vim.api.nvim_win_is_valid(day.win) then
    vim.api.nvim_win_close(day.win, true)
  end
  day.win = nil
  day.buf = nil
  render() -- refresh grid previews
  if grid.win and vim.api.nvim_win_is_valid(grid.win) then
    pcall(vim.api.nvim_set_current_win, grid.win)
  end
end

local function day_cursor_idx()
  if not (day.win and vim.api.nvim_win_is_valid(day.win)) then return nil end
  return vim.api.nvim_win_get_cursor(day.win)[1]
end

local function day_add()
  vim.ui.input({ prompt = "New entry: " }, function(text)
    if text and text ~= "" then
      store.add(day.y, day.m, day.d, text)
      day_render()
    end
    day_focus()
  end)
end

local function day_edit()
  local idx = day_cursor_idx()
  if not idx then return end
  local e = store.entries(day.y, day.m, day.d)[idx]
  if not e then return end
  vim.ui.input({ prompt = "Edit: ", default = e.text }, function(text)
    if text then
      store.update(day.y, day.m, day.d, idx, text)
      day_render()
    end
    day_focus()
  end)
end

local function day_cycle()
  local idx = day_cursor_idx()
  if not idx then return end
  store.cycle(day.y, day.m, day.d, idx)
  day_render()
end

local function day_delete()
  local idx = day_cursor_idx()
  if not idx then return end
  local e = store.entries(day.y, day.m, day.d)[idx]
  if not e then return end
  vim.ui.select({ "Yes", "No" }, { prompt = "Delete: " .. e.text .. "?" }, function(choice)
    if choice == "Yes" then
      store.delete(day.y, day.m, day.d, idx)
      day_render()
    end
    day_focus()
  end)
end

local function open_day()
  local offset = first_offset(grid.year, grid.month)
  local ndays = days_in_month(grid.year, grid.month)
  local idx = (grid.cur.week - 1) * 7 + grid.cur.day - 1 -- 0-based cell index
  local daynum = idx - offset + 1
  if daynum < 1 or daynum > ndays then return end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "planning-day"
  vim.bo[buf].modifiable = false

  local width, height = day_size()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = string.format("%04d-%02d-%02d", grid.year, grid.month, daynum),
    title_pos = "center",
    style = "minimal",
  })
  day.win = win
  day.buf = buf
  day.y = grid.year
  day.m = grid.month
  day.d = daynum

  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "a", day_add, opts)
  vim.keymap.set("n", "o", day_edit, opts)
  vim.keymap.set("n", "t", day_cycle, opts)
  vim.keymap.set("n", "x", day_delete, opts)
  vim.keymap.set("n", "q", day_close, opts)
  vim.keymap.set("n", "<Esc>", day_close, opts)

  day_render()
end

-- ---------- public API ----------

function M.open()
  if grid.win and vim.api.nvim_win_is_valid(grid.win) then
    vim.api.nvim_set_current_win(grid.win)
    return
  end
  define_hl()
  compute_layout()
  local now = os.date("*t")
  grid.year = now.year
  grid.month = now.month
  store.load()
  -- focus today
  local offset = first_offset(grid.year, grid.month)
  local idx = offset + now.day - 1 -- 0-based cell index of today
  grid.cur.day = (idx % 7) + 1
  grid.cur.week = math.floor(idx / 7) + 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "planning"
  vim.bo[buf].modifiable = false

  local width, height = grid_size()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = month_title(grid.year, grid.month),
    title_pos = "center",
    style = "minimal",
  })
  grid.win = win
  grid.buf = buf

  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "h", function() move(0, -1) end, opts)
  vim.keymap.set("n", "l", function() move(0, 1) end, opts)
  vim.keymap.set("n", "j", function() move(1, 0) end, opts)
  vim.keymap.set("n", "k", function() move(-1, 0) end, opts)
  vim.keymap.set("n", "n", function() shift_month(1) end, opts)
  vim.keymap.set("n", "p", function() shift_month(-1) end, opts)
  vim.keymap.set("n", "<CR>", open_day, opts)
  vim.keymap.set("n", "o", open_day, opts)
  vim.keymap.set("n", "q", close_grid, opts)
  vim.keymap.set("n", "<Esc>", close_grid, opts)

  render()
end

M.next_month = function() shift_month(1) end
M.prev_month = function() shift_month(-1) end

function M.setup(opts)
  opts = opts or {}
  if opts.file then store.set_path(opts.file) end
end

return M
