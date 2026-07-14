-- plugin/planning.lua: registers the :Planning user command.
vim.api.nvim_create_user_command("Planning", function()
  require("planning").open()
end, { desc = "Open the planning calendar" })
