-- planning/store.lua: JSON-backed entry storage.
-- ponytail: one file, autosave on every mutation.
-- Model: { days = { ["YYYY-MM-DD"] = { {text,status}, ... } },
--          ranges = { {text,status,start,end}, ... } }

local M = {}

local default_path = vim.fn.stdpath("state") .. "/planning.nvim/data.json"
local path = default_path
local data = nil

local function key(y, m, d)
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function ensure_dir()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
end

-- migrate old format (bare { ["YYYY-MM-DD"] = {...} }) to { days=..., ranges={} }
local function migrate(raw)
  if raw and raw.days then return raw end
  local migrated = { days = {}, ranges = {} }
  if type(raw) == "table" then
    for k, v in pairs(raw) do
      if type(k) == "string" and k:match("^%d%d%d%d%-%d%d%-%d%d$") then
        migrated.days[k] = v
      end
    end
  end
  return migrated
end

function M.set_path(p)
  path = p or default_path
  data = nil
end

function M.path()
  return path
end

function M.load()
  if data then return data end
  data = { days = {}, ranges = {} }
  local f = io.open(path, "r")
  if f then
    local body = f:read("*a")
    f:close()
    if body and body ~= "" then
      local ok, decoded = pcall(vim.fn.json_decode, body)
      if ok and type(decoded) == "table" then data = migrate(decoded) end
    end
  end
  return data
end

function M.reload()
  data = nil
  return M.load()
end

function M.save()
  ensure_dir()
  vim.fn.writefile({ vim.fn.json_encode(data) }, path)
end

-- returns merged list of day-specific + range entries for a date
-- each entry is enriched: { text, status, _type="day"|"range", _idx=N }
function M.entries(y, m, d)
  M.load()
  local datekey = key(y, m, d)
  local result = {}
  -- range entries first (always pinned to top)
  for i, r in ipairs(data.ranges) do
    if r.start <= datekey and datekey <= r["end"] then
      result[#result + 1] = { text = r.text, status = r.status, _type = "range", _idx = i, start = r.start, ["end"] = r["end"] }
    end
  end
  -- day entries after
  local days = data.days[datekey] or {}
  for i, e in ipairs(days) do
    result[#result + 1] = { text = e.text, status = e.status, _type = "day", _idx = i }
  end
  return result
end

-- ---------- day-entry CRUD ----------

function M.add(y, m, d, text)
  M.load()
  local k = key(y, m, d)
  data.days[k] = data.days[k] or {}
  table.insert(data.days[k], { text = text, status = "new" })
  M.save()
end

function M.update(y, m, d, idx, text)
  M.load()
  local list = data.days[key(y, m, d)]
  if list and list[idx] then
    list[idx].text = text
    M.save()
  end
end

function M.cycle(y, m, d, idx)
  M.load()
  local list = data.days[key(y, m, d)]
  if list and list[idx] then
    list[idx].status = (list[idx].status == "new" and "in_progress")
      or (list[idx].status == "in_progress" and "done")
      or "new"
    M.save()
  end
end

function M.delete(y, m, d, idx)
  M.load()
  local k = key(y, m, d)
  local list = data.days[k]
  if list then
    table.remove(list, idx)
    if #list == 0 then data.days[k] = nil end
    M.save()
  end
end

function M.move(y, m, d, idx, dir)
  M.load()
  local list = data.days[key(y, m, d)]
  if not list then return end
  local target = idx + dir
  if target < 1 or target > #list then return end
  list[idx], list[target] = list[target], list[idx]
  M.save()
end

-- ---------- range-entry CRUD ----------

function M.add_range(text, status, start_str, end_str)
  M.load()
  table.insert(data.ranges, { text = text, status = status or "new", start = start_str, ["end"] = end_str })
  M.save()
end

function M.update_range(idx, text, start_str, end_str)
  M.load()
  local r = data.ranges[idx]
  if r then
    r.text = text
    if start_str then r.start = start_str end
    if end_str then r["end"] = end_str end
    M.save()
  end
end

function M.cycle_range(idx)
  M.load()
  local r = data.ranges[idx]
  if r then
    r.status = (r.status == "new" and "in_progress")
      or (r.status == "in_progress" and "done")
      or "new"
    M.save()
  end
end

function M.delete_range(idx)
  M.load()
  table.remove(data.ranges, idx)
  M.save()
end

function M.move_range(idx, dir)
  M.load()
  local target = idx + dir
  if target < 1 or target > #data.ranges then return end
  data.ranges[idx], data.ranges[target] = data.ranges[target], data.ranges[idx]
  M.save()
end

function M.reset()
  M.load()
  data.days = {}
  data.ranges = {}
  M.save()
end

-- convert a day-entry to a range-entry (used when editing a day entry to add a range)
function M.day_to_range(y, m, d, day_idx, start_str, end_str)
  M.load()
  local k = key(y, m, d)
  local list = data.days[k]
  if not list or not list[day_idx] then return end
  local e = list[day_idx]
  table.insert(data.ranges, { text = e.text, status = e.status, start = start_str, ["end"] = end_str })
  table.remove(list, day_idx)
  if #list == 0 then data.days[k] = nil end
  M.save()
end

-- convert a range-entry to a day-entry on (y,m,d) (used when editing a range to remove range)
function M.range_to_day(idx, y, m, d)
  M.load()
  local r = data.ranges[idx]
  if not r then return end
  local k = key(y, m, d)
  data.days[k] = data.days[k] or {}
  table.insert(data.days[k], { text = r.text, status = r.status })
  table.remove(data.ranges, idx)
  M.save()
end

return M
