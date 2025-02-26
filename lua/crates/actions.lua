local M = {}

local edit = require("crates.edit")
local util = require("crates.util")
local state = require("crates.state")
local toml = require("crates.toml")
local types = require("crates.types")
local Diagnostic = types.Diagnostic
local Range = types.Range

function M.upgrade_crate(alt)
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local info = util.get_buf_info(buf)
   if next(crates) and info then
      edit.upgrade_crates(buf, crates, info, alt)
   end
end

function M.upgrade_crates(alt)
   local buf = util.current_buf()
   local lines = Range.new(
   vim.api.nvim_buf_get_mark(0, "<")[1] - 1,
   vim.api.nvim_buf_get_mark(0, ">")[1])

   local crates = util.get_line_crates(buf, lines)
   local info = util.get_buf_info(buf)
   if next(crates) and info then
      edit.upgrade_crates(buf, crates, info, alt)
   end
end

function M.upgrade_all_crates(alt)
   local buf = util.current_buf()
   local cache = state.buf_cache[buf]
   if cache.crates and cache.info then
      edit.upgrade_crates(buf, cache.crates, cache.info, alt)
   end
end

function M.update_crate(alt)
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local info = util.get_buf_info(buf)
   if next(crates) and info then
      edit.update_crates(buf, crates, info, alt)
   end
end

function M.update_crates(alt)
   local buf = util.current_buf()
   local lines = Range.new(
   vim.api.nvim_buf_get_mark(0, "<")[1] - 1,
   vim.api.nvim_buf_get_mark(0, ">")[1])

   local crates = util.get_line_crates(buf, lines)
   local info = util.get_buf_info(buf)
   if next(crates) and info then
      edit.update_crates(buf, crates, info, alt)
   end
end

function M.update_all_crates(alt)
   local buf = util.current_buf()
   local cache = state.buf_cache[buf]
   if cache.crates and cache.info then
      edit.update_crates(buf, cache.crates, cache.info, alt)
   end
end

function M.expand_plain_crate_to_inline_table()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local _, crate = next(util.get_line_crates(buf, Range.pos(line)))
   if crate then
      edit.expand_plain_crate_to_inline_table(buf, crate)
   end
end

function M.extract_crate_into_table()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local _, crate = next(util.get_line_crates(buf, Range.pos(line)))
   if crate then
      edit.extract_crate_into_table(buf, crate)
   end
end

function M.open_homepage()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local _, crate = next(crates)
   if crate then
      local crate_info = state.api_cache[crate:package()]
      if crate_info and crate_info.homepage then
         util.open_url(crate_info.homepage)
      else
         util.notify(vim.log.levels.INFO, "The crate '%s' has no homepage specified", crate:package())
      end
   end
end

function M.open_repository()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local _, crate = next(crates)
   if crate then
      local crate_info = state.api_cache[crate:package()]
      if crate_info and crate_info.repository then
         util.open_url(crate_info.repository)
      else
         util.notify(vim.log.levels.INFO, "The crate '%s' has no repository specified", crate:package())
      end
   end
end

function M.open_documentation()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local _, crate = next(crates)
   if crate then
      local crate_info = state.api_cache[crate:package()]
      local url = crate_info and crate_info.documentation
      url = url or util.docs_rs_url(crate:package())
      util.open_url(url)
   end
end

function M.open_crates_io()
   local buf = util.current_buf()
   local line = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local _, crate = next(crates)
   if crate then
      util.open_url(util.crates_io_url(crate:package()))
   end
end

local function rename_crate_package_action(buf, crate, name)
   return function()
      edit.rename_crate_package(buf, crate, name)
   end
end

local function remove_diagnostic_range_action(buf, d)
   return function()
      vim.api.nvim_buf_set_text(buf, d.lnum, d.col, d.end_lnum, d.end_col, {})
   end
end

local function remove_lines_action(buf, lines)
   return function()
      vim.api.nvim_buf_set_lines(buf, lines.s, lines.e, false, {})
   end
end

local function remove_feature_action(buf, crate, feat)
   return function()
      edit.disable_feature(buf, crate, feat)
   end
end

function M.get_actions()
   local actions = {}

   local buf = util.current_buf()
   local line, col = util.cursor_pos()
   local crates = util.get_line_crates(buf, Range.pos(line))
   local key, crate = next(crates)
   if crate then
      local info = util.get_crate_info(buf, key)
      if info then
         if info.vers_update then
            actions["update_crate"] = M.update_crate
         end
         if info.vers_upgrade then
            actions["upgrade_crate"] = M.upgrade_crate
         end
      end


      if crate.syntax == "plain" then
         actions["expand_crate_to_inline_table"] = M.expand_plain_crate_to_inline_table
      end
      if crate.syntax ~= "table" then
         actions["extract_crate_into_table"] = M.extract_crate_into_table
      end
   end

   local diagnostics = util.get_buf_diagnostics(buf) or {}
   for _, d in ipairs(diagnostics) do
      if not d:contains(line, col) then
         goto continue
      end

      if d.kind == "section_dup" then
         actions["remove_duplicate_section"] = remove_diagnostic_range_action(buf, d)
      elseif d.kind == "section_dup_orig" then
         actions["remove_original_section"] = remove_lines_action(buf, d.data["lines"])
      elseif d.kind == "section_invalid" then
         actions["remove_invalid_dependency_section"] = remove_diagnostic_range_action(buf, d)

      elseif d.kind == "crate_dup" then
         actions["remove_duplicate_crate"] = remove_diagnostic_range_action(buf, d)
      elseif d.kind == "crate_dup_orig" then
         actions["remove_original_crate"] = remove_diagnostic_range_action(buf, d)
      elseif d.kind == "crate_name_case" then
         actions["rename_crate"] = rename_crate_package_action(buf, d.data["crate"], d.data["crate_name"])

      elseif crate and d.kind == "feat_dup" then
         actions["remove_duplicate_feature"] = remove_feature_action(buf, crate, d.data["feat"])
      elseif crate and d.kind == "feat_dup_orig" then
         actions["remove_original_feature"] = remove_feature_action(buf, crate, d.data["feat"])
      elseif crate and d.kind == "feat_invalid" then
         actions["remove_invalid_feature"] = remove_feature_action(buf, crate, d.data["feat"])
      end

      ::continue::
   end

   if crate then
      actions["open_documentation"] = M.open_documentation
      actions["open_crates.io"] = M.open_crates_io
   end

   actions["update_all_crates"] = M.update_all_crates
   actions["upgrade_all_crates"] = M.upgrade_all_crates

   return actions
end

return M
