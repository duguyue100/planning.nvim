-- plugin/planning.lua: registers user commands.
vim.api.nvim_create_user_command("Planning", function()
  require("planning").open()
end, { desc = "Open the planning calendar" })

vim.api.nvim_create_user_command("PlanningReset", function()
  require("planning").reset()
end, { desc = "Delete all planning entries" })
