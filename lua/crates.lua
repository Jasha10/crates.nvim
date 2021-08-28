local M = {}

local core = require("crates.core")
local api = require("crates.api")
local toml = require("crates.toml")
local semver = require("crates.semver")
local util = require("crates.util")
local popup = require("crates.popup")
local config_manager = require("crates.config")

function M.display_versions(crate, versions)
    if not core.visible then
        return
    end

    local avoid_pre = core.cfg.avoid_prerelease and not crate.req_has_suffix
    local newest = util.get_newest(versions, avoid_pre)

    local virt_text
    if newest then
        if semver.matches_requirements(newest.parsed, crate.reqs) then
            -- version matches, no upgrade available
            virt_text = { { string.format(core.cfg.text.version, newest.num), core.cfg.highlight.version } }
        else
            -- version does not match, upgrade available
            local match_yanked = nil
            local match_pre = nil
            local match = nil
            for _,v in ipairs(versions) do
                if semver.matches_requirements(v.parsed, crate.reqs) then
                    if not v.yanked then
                        if avoid_pre then
                            if v.parsed.suffix then
                                match_pre = match_pre or v
                            else
                                match = v
                                break
                            end
                        else
                            match = v
                            break
                        end
                    else
                        match_yanked = match_yanked or v
                    end
                end
            end

            if match then
                -- found a match
                virt_text = {
                    { string.format(core.cfg.text.version, match.num), core.cfg.highlight.version },
                    { string.format(core.cfg.text.update, newest.num), core.cfg.highlight.update },
                }
            elseif match_pre then
                -- found a pre-release match
                virt_text = {
                    { string.format(core.cfg.text.prerelease, match_pre.num), core.cfg.highlight.prerelease },
                    { string.format(core.cfg.text.update, newest.num), core.cfg.highlight.update },
                }
            elseif match_yanked then
                -- found a yanked match
                virt_text = {
                    { string.format(core.cfg.text.yanked, match_yanked.num), core.cfg.highlight.yanked },
                    { string.format(core.cfg.text.update, newest.num), core.cfg.highlight.update },
                }
            else
                -- no match found
                virt_text = {
                    { core.cfg.text.nomatch, core.cfg.highlight.nomatch },
                    { string.format(core.cfg.text.update, newest.num), core.cfg.highlight.update },
                }
            end
        end
    else
        virt_text = { { core.cfg.text.error, core.cfg.highlight.error } }
    end

    vim.api.nvim_buf_clear_namespace(0, M.namespace_id, crate.linenr - 1, crate.linenr)
    vim.api.nvim_buf_set_virtual_text(0, M.namespace_id, crate.linenr - 1, virt_text, {})
end

function M.display_loading(crate)
    local virt_text = { { core.cfg.text.loading, core.cfg.highlight.loading } }
    vim.api.nvim_buf_clear_namespace(0, M.namespace_id, crate.linenr - 1, crate.linenr)
    vim.api.nvim_buf_set_virtual_text(0, M.namespace_id, crate.linenr - 1, virt_text, {})
end

function M.reload_crate(crate)
    local function on_fetched(versions)
        if versions and versions[1] then
            core.vers_cache[crate.name] = versions
        end
        
        -- get current position of crate
        local cur_buf = util.current_buf()
        local c = core.crate_cache[cur_buf][crate.name]

        if c then
            M.display_versions(c, versions)
        end
    end

    if core.cfg.loading_indicator then
        M.display_loading(crate)
    end

    api.fetch_crate_versions(crate.name, on_fetched)
end

function M.clear()
    if M.namespace_id then
        vim.api.nvim_buf_clear_namespace(0, M.namespace_id, 0, -1)
    end
    M.namespace_id = vim.api.nvim_create_namespace("crates.nvim")
end

function M.hide()
    core.visible = false
    M.clear()
end

function M.reload()
    core.visible = true
    core.vers_cache = {}
    M.clear()

    local cur_buf = util.current_buf()
    local crates = toml.parse_crates(0)

    core.crate_cache[cur_buf] = {}

    for _,c in ipairs(crates) do
        core.crate_cache[cur_buf][c.name] = c
        M.reload_crate(c)
    end
end

function M.update()
    core.visible = true
    M.clear()

    local cur_buf = util.current_buf()
    local crates = toml.parse_crates(0)

    core.crate_cache[cur_buf] = {}

    for _,c in ipairs(crates) do
        local versions = core.vers_cache[c.name]

        core.crate_cache[cur_buf][c.name] = c

        if versions then
            M.display_versions(c, versions)
        else
            M.reload_crate(c)
        end
    end
end

function M.toggle()
    if core.visible then
        M.hide()
    else
        M.update()
    end
end

function M.upgrade_crate()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local crate, versions = util.get_line_crate(linenr)

    if not crate or not versions then
        return
    end

    local avoid_pre = core.cfg.avoid_prerelease and not crate.req_has_suffix
    local newest = util.get_newest(versions, avoid_pre)

    if not newest then
        return
    end

    util.set_version(0, crate, newest.num)
end

function M.setup(config)
    if config then
        local default = config_manager.default()
        core.cfg = vim.tbl_deep_extend("keep", config, default)
    else
        core.cfg = config_manager.default()
    end

    vim.cmd("augroup Crates")
    if core.cfg.autoload then
        vim.cmd("autocmd BufRead Cargo.toml lua require('crates').update()")
    end
    if core.cfg.autoupdate then
        vim.cmd("autocmd TextChanged,TextChangedI,TextChangedP Cargo.toml lua require('crates').update()")
    end
    vim.cmd("augroup END")

    vim.cmd([[
        augroup CratesPopup
        autocmd CursorMoved,CursorMovedI Cargo.toml lua require('crates.popup').hide_versions()
        augroup END
    ]])
end

M.show_versions_popup = popup.show_versions
M.hide_versions_popup = popup.hide_versions

return M
