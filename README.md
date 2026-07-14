# planning.nvim

A tiny, dependency-free planning calendar for Neovim.

Open a floating month grid, jump between days with `hjkl`, and keep short
entries on each day with a status (`New` / `In Progress` / `Done`). Entries
can span a single day or a date range. Everything is stored in a local JSON
file and autosaved on every change.

![planning.nvim](docs/preview.png)

## Requirements

- Neovim **0.9+** (uses floating window `title` / `border`).
- No plugins required. `vim.ui.input` prompts are styled automatically if you
  already use `dressing.nvim`, `snacks.nvim.input`, or similar.

## Install

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "duguyue100/planning.nvim",
  cmd = "Planning",
  config = function()
    require("planning").setup()
    -- optional global keymaps
    vim.keymap.set("n", "<leader>po", "<cmd>Planning<cr>", { desc = "Planning" })
    vim.keymap.set("n", "<leader>pn", function() require("planning").next_month() end, { desc = "Planning next month" })
    vim.keymap.set("n", "<leader>pp", function() require("planning").prev_month() end, { desc = "Planning prev month" })
  end,
}
```

> The plugin does **not** bind any global keys by default — `<leader>p*`
> groups are yours to own. Inside the calendar window, all navigation uses
> buffer-local keys (see below).

### Manual

Clone the repo somewhere on your `runtimepath` and start Neovim. The
`:Planning` command is registered automatically via `plugin/planning.lua`.

## Usage

Run `:Planning`. A centered floating window opens on the current month with
today focused.

### Calendar (month grid) — buffer-local keys

| Key       | Action                                   |
| --------- | ---------------------------------------- |
| `h` `j` `k` `l` | Move focus between day cells        |
| `n`       | Next month                               |
| `p`       | Previous month                           |
| `o` / `<CR>` | Open the focused day's detail view       |
| `q` / `<Esc>` | Close the calendar                   |

Each cell shows the day number (top-left) and a preview of up to 3 entries.
When a day has more, the last preview line reads `+k more`. The current day's
number is highlighted with `PlanningToday` (links to `Special`), and the
focused cell has a `PlanningFocus` background (links to `Visual`).

Entries are colored by status:

- **New** — default text color
- **In Progress** — yellow (`WarningMsg`)
- **Done** — green (`String`)

### Day detail — buffer-local keys

| Key       | Action                                   |
| --------- | ---------------------------------------- |
| `a`       | Add a new entry (text + optional date range) |
| `o`       | Edit the entry on the current line       |
| `t`       | Cycle status: New → In Progress → Done   |
| `x`       | Delete the entry on the current line (confirms first) |
| `q` / `<Esc>` | Close the day view, return to grid  |

### Adding entries with date ranges

When you press `a`, you get two prompts:

1. **`New entry:`** — the entry text.
2. **`End date or range (blank = this day):`** — leave blank for a single-day
   entry on the focused day, or specify a range:

| Input         | Result                                  |
| ------------- | --------------------------------------- |
| *(blank)*     | Single-day entry on the focused day     |
| `7/20`        | Range from the focused day to Jul 20    |
| `7/14 - 7/20` | Full range, Jul 14 to Jul 20            |
| `2026-07-14 - 2026-07-20` | Same, explicit ISO dates  |

Dates accept `M/D` (year defaults to the current view year) or `YYYY-MM-DD`.
Ranges can span months (e.g. `7/28 - 8/3`).

### Editing entries

Press `o` on any entry. The text prompt prefills the current text, and the
range prompt prefills the current range (if any). You can:

- **Edit the text** — just change it.
- **Resize the range** — type a new range.
- **Convert range → single-day** — clear the range prompt (leave blank).
- **Convert single-day → range** — type a range where there wasn't one.

### Range entries in the day view

Range entries show their span so you can tell them apart from day-specific
entries:

```
[In Progress] Jul 14 -> Jul 20  Ship planning v1
[New]                          Buy groceries
```

Cycling status (`t`) on a range entry updates the **entire range** — one
entry, one status. Deleting (`x`) removes the whole range (the confirm
prompt shows the full span). Both operations work from **any day** in the
range.

## Configuration

`setup()` accepts an optional table. Only one option today:

```lua
require("planning").setup({
  file = vim.fn.expand("~/notes/planning.json"), -- custom data file
})
```

Default data file: `vim.fn.stdpath("state") .. "/planning.nvim/data.json"`
(typically `~/.local/state/nvim/planning.nvim/data.json`).

### Highlights

| Group           | Default link | Used for                  |
| --------------- | ------------ | ------------------------- |
| `PlanningToday` | `Special`    | Today's day number        |
| `PlanningFocus` | `Visual`     | Focused cell background   |

Override in your colorscheme or config:

```lua
vim.api.nvim_set_hl(0, "PlanningToday", { bold = true, fg = "#ff9e64" })
vim.api.nvim_set_hl(0, "PlanningFocus", { bg = "#2a2a3e" })
```

## Data format

Plain JSON with two top-level keys:

```json
{
  "days": {
    "2026-07-14": [
      { "text": "Buy groceries", "status": "new" }
    ]
  },
  "ranges": [
    { "text": "Ship planning v1", "status": "in_progress", "start": "2026-07-14", "end": "2026-07-20" }
  ]
}
```

- `days` — map of `YYYY-MM-DD` to arrays of single-day entries.
- `ranges` — array of entries that span multiple days, each with `start` and
  `end` (both `YYYY-MM-DD`).

`status` is one of `new`, `in_progress`, `done`. The file is rewritten after
every add / edit / status cycle / delete.

Old data files in the bare `{"YYYY-MM-DD": [...]}` format are migrated
automatically on first load.

## Project layout

```
plugin/planning.lua      :Planning command
lua/planning/init.lua    float window, month grid, nav, day-detail view
lua/planning/store.lua   JSON load/save + entry CRUD
```

## License

MIT
