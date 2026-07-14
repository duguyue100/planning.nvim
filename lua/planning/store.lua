-- planning/store.lua: JSON-backed entry storage.
-- ponytail: one file, one table, autosave on every mutation.

local M = {}

local default_path = vim.fn.stdpath("state") .. "/planning.nvim/data.json"
local path = default_path
local data = nil -- map "YYYY-MM-DD" -> { { text = str, status = str }, ... }

local function key(y, m, d)
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function ensure_dir()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
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
  data = {}
  local f = io.open(path, "r")
  if f then
    local body = f:read("*a")
    f:close()
    if body and body ~= "" then
      local ok, decoded = pcall(vim.fn.json_decode, body)
      if ok and type(decoded) == "table" then data = decoded end
    end
  end
  return data
end

function M.save()
  ensure_dir()
  vim.fn.writefile({ vim.fn.json_encode(data) }, path)
end

function M.entries(y, m, d)
  M.load()
  return data[key(y, m, d)] or {}
end

function M.add(y, m, d, text)
  M.load()
  local k = key(y, m, d)
  data[k] = data[k] or {}
  table.insert(data[k], { text = text, status = "new" })
  M.save()
end

function M.update(y, m, d, idx, text)
  M.load()
  local list = data[key(y, m, d)]
  if list and list[idx] then
    list[idx].text = text
    M.save()
  end
end

function M.cycle(y, m, d, idx)
  M.load()
  local list = data[key(y, m, d)]
  if list and list[idx] then
    list[idx].status = (list[idx].status == "new" and "in_progress")
      or (list[idx].status == "in_progress" and "done")
      or "new"
    M.save()
  end
end

function M.delete(y, m, d, idx)
  M.load()
  local list = data[key(y, m, d)]
  if list then
    table.remove(list, idx)
    if #list == 0 then data[key(y, m, d)] = nil end
    M.save()
  end
end

return M
