-- NOTE: We disabled symlinks, it wont follow, wherever we use vim.fn.glob, like finding .key files, or recursive hell
--
local prop = require("phxm.properties")
local project = require("phxm.project")

local M = {}

local autogroup_name = "phxmAutocmdGroup"

local default_opts = {
	root = vim.fn.expand("~/.vim-projects"), -- Default base path for projects
}
M.opts = {}

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", default_opts, opts or {})

	--prop.init(M.opts.root)
	-- print num of arg
	log(" num of arg: " .. vim.fn.argc())
	--M.init()
	if vim.fn.argc() == 0 then
		local selected_project_file = vim.fn.expand(M.opts.root .. "/.selected_project")
		if vim.fn.filereadable(selected_project_file) == 1 then
			local file_content = vim.fn.readfile(selected_project_file)
			if file_content and #file_content > 0 then
				local project_path = file_content[1]:gsub("\n$", "")
				-- Switch to the project if the file has valid content
				require("phxm.project").switch_to_project(project_path)
				M.opts.is_loaded = true

				-- We do this, because whatever other plugin may not have run yet to set their event handlers...
				vim.defer_fn(function()
					vim.api.nvim_exec_autocmds("User", { pattern = "phxmPostLoaded" })
				end, 1)

			--				vim.api.nvim_exec_autocmds("User", { pattern = "postStart" })
			else
				-- Handle empty file
				M.opts.is_loaded = false
				require("phxm.project").switch_to_project(M.opts.root)
				M.opts.is_loaded = true
				vim.defer_fn(function()
					vim.api.nvim_exec_autocmds("User", { pattern = "phxmPostLoaded" })
				end, 1)
				log("phxm loaded root as project: .selected_project file is empty")
			end
		else
			-- Handle missing file
			M.opts.is_loaded = false
			log("phxm not loaded: .selected_project file is missing")
		end
	else
		log("phxm not loaded: loaded with arg")
	end
end

--called when we switch_to_project
function M.init()
	-- Clear the group if it exists, then recreate it
	local group = vim.api.nvim_create_augroup(autogroup_name, { clear = true })

	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		callback = function() end,
	})

	-- Set up the autocommands for `BufEnter` and `VimLeavePre`
	-- NOTE: No need to save session on each buf enter
	--vim.api.nvim_create_autocmd({ "BufEnter", "VimLeavePre" }, {
	vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
		group = group,
		callback = function()
			require("phxm.session").save()
		end,
	})
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("GlobalYankBuffer", { clear = true }),
		callback = function()
			-- Check if the yank operation was triggered by the 'y' operator
			if vim.v.event.operator == "y" then
				require("phxm.user_actions").append_to_yank_file()
			end
		end,
		-- NOTE: Could add separate ones for other operators like 'd', 'c', etc.
	})

	local function close_empty_or_directory_buffers()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			-- Check if the buffer is valid and either unnamed or points to a directory
			--			if vim.api.nvim_buf_is_valid(buf) then
			--				local buf_name = vim.api.nvim_buf_get_name(buf)
			--				if buf_name == "" or vim.fn.isdirectory(buf_name) == 1 then
			--					vim.cmd("silent! bwipeout! " .. buf)
			--				end
			--			end
			if vim.api.nvim_buf_is_valid(buf) then
				local buf_name = vim.api.nvim_buf_get_name(buf)
				--if buf_name == "" or vim.fn.isdirectory(buf_name) == 1 then
				if vim.fn.isdirectory(buf_name) == 1 then
					vim.cmd("silent! bwipeout! " .. buf)
				end
			end
		end
	end

	-- Run the function on BufEnter to automatically close matching buffers
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function()
			close_empty_or_directory_buffers()
			local buffer = require("phxm.buffer")
			buffer.re_bind_buffer_keys()
			require("funview").re_bind_function_keys()
			buffer.record_buffer_change()

			-- Do this because LSP servers need us to be in the file root of target file (bash lsp at least)
			-- Get the full path of the current buffer
			local bufname = vim.fn.expand("%:p")

			-- Check if the buffer is associated with a valid file
			if bufname ~= "" and vim.fn.filereadable(bufname) == 1 then
				-- Change directory to the directory of the file
				vim.cmd("cd " .. vim.fn.expand("%:p:h"))
			end

			---- Also, make sure update history of when we change buff
			--			local buffer_name = vim.fn.bufname()
			--			if buffer_name and buffer_name ~= "" then
			--				if require("phxm.jump_state").has_state() then
			--					local state = require("phxm.jump_state").get()
			--					if state then
			--						buffer.update_history(state.path, state.line_number, state.desc)
			--					end
			--				else
			--					local cursor_position = vim.api.nvim_win_get_cursor(0)
			--					local line_number = cursor_position[1]
			--					buffer.update_history(buffer_name, line_number, "Auto")
			--				end
			--			end
		end,
	})

	-- Clear buffer history for a window when it is closed
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local phxm = require("phxm")
			if not phxm.current_project then
				return
			end
			local window_id = tonumber(args.match)
			local project_path = require("phxm").current_project.project_path
			local buffer = require("phxm.buffer")

			-- Ensure window_id is valid before attempting to clear its entry
			if window_id and buffer.previous_buffers[project_path] then
				buffer.previous_buffers[project_path][window_id] = nil
			end
		end,
	})

	-- For init.lua
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*", -- Applies to all files. Use specific patterns (e.g., "*.txt") for specific file types.
		callback = function()
			require("funview").re_bind_function_keys()
		end,
	})
end

function M.destroy()
	-- We may get conflicts in initialize when loading/unloading other stuff like buffers if stuff like BufEnter etc exits
	-- Thus have this
	vim.api.nvim_del_augroup_by_name(autogroup_name)
end

return M
