-- 1. Loaded (or "In Memory")
--
--     The buffer’s contents are loaded into memory, which means you can view, edit, and navigate it without needing to re-read from disk.
--     A buffer is usually in the loaded state when you actively open and work on it.
--     You can check if a buffer is loaded using :echo bufloaded({bufnr}), which returns 1 if loaded and 0 if not.
--
-- 2. Unloaded
--
--     An unloaded buffer is not currently in memory, meaning its content has been removed from memory to free resources.
--     The buffer remains in the buffer list (if it was listed) and retains some metadata (like line number and marks).
--     To reload an unloaded buffer, you need to reopen it, which reads the file from disk again.
--
-- 3. Listed
--
--     A listed buffer appears in the buffer list (e.g., you can see it in :ls), making it accessible by its buffer number or name.
--     By default, buffers you actively open or work on are listed.
--     You can unlist a buffer using :bdelete, which keeps its content in memory but removes it from the list of accessible buffers.
--     Listed buffers are useful for navigating between files within the editor.
--
-- 4. Unlisted
--
--     An unlisted buffer does not show up in the buffer list (:ls), so it’s not directly accessible by standard navigation commands.
--     You can unlist a buffer with :bdelete, which keeps its state in memory without listing it.
--     Unlisted buffers can still be accessed by their buffer number if you know it.
--
-- 5. Hidden
--
--     A hidden buffer is a buffer that remains in memory even after switching away from it.
--     In Neovim/Vim, you can have hidden buffers if you set set hidden, which allows buffers to remain open and in memory without requiring you to save them.
--     Hidden buffers retain their state and unsaved changes, which is helpful when working with multiple files.
--
-- 6. Modified
--
--     A modified buffer has unsaved changes, meaning it differs from the on-disk file.
--     This is a temporary state indicating that changes need to be saved.
--     If you try to close a modified buffer, Neovim/Vim will prompt you to save, discard, or cancel.

local context = "ctx_dynamicbuffers"
local M = {}
-- NOTE: we use win pos and dim as id, using window_id wont work when we destroy and recreate session in project switching. We get new window ids

-- NOTE: This code is duplicated and exist 3 times mostly same, buffer module, curretn_file_dir_tree, and in project module
------------------------
local function sanitize_for_hl_group(name)
	-- Replace unsafe characters for highlight group names
	return name:gsub("[^%w_]", "_")
end

local function set_path_highlights(full_path)
	local keypoint = require("keypoint") -- Assuming keypoint module is available

	-- Extract [linunumber:description] and filepath
	local meta, path = full_path:match("^%[(.-)%]%s+(.*)$")
	if not meta or not path then
		vim.notify("Invalid path format: " .. full_path, vim.log.levels.ERROR)
		return nil
	end

	-- Split the path into directory and file
	local dir, file = path:match("^(.*)/([^/]+)$")
	dir = dir or ""
	file = file or path

	-- Sanitize names for highlight group safety
	local sanitized_dir = sanitize_for_hl_group(dir)
	local sanitized_file = sanitize_for_hl_group(file)

	-- Generate colors for metadata, directory, and file
	local meta_color = "#FFD700" -- Golden color for metadata
	local dir_color = keypoint.string_to_color(dir)
	dir_color = keypoint.adjust_color(dir_color, 60, 80)
	local file_color = keypoint.string_to_color(file)
	file_color = keypoint.adjust_color(file_color, 60, 90)

	-- Create dynamic highlight groups
	local meta_hl = "MetaHlGroup"
	local dir_hl = "DirHlGroup_" .. sanitized_dir
	local file_hl = "FileHlGroup_" .. sanitized_file

	-- Define the highlight groups
	vim.api.nvim_set_hl(0, meta_hl, { fg = meta_color, bold = true, bg = "#030303" })
	vim.api.nvim_set_hl(0, dir_hl, { fg = dir_color, bg = "#111111" })
	vim.api.nvim_set_hl(0, file_hl, { fg = file_color, bold = true, bg = "#222222" })

	return meta_hl, dir_hl, file_hl, meta, dir, file
end

function M.open_selected()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_get_current_line()

	-- Validate the selection
	if line == "" then
		vim.notify("Invalid selection.", vim.log.levels.WARN)
		return
	end

	-- Parse the line in the format [linenumber:some text] path
	local linenumber, file_path = line:match("^%[(.-):.-%]%s+(.*)$")
	if not file_path or file_path == "" then
		vim.notify("Failed to parse file path from the selected line.", vim.log.levels.WARN)
		return
	end

	-- Convert linenumber to a number
	linenumber = tonumber(linenumber)

	-- Validate the file path
	if vim.fn.isdirectory(file_path) == 1 then
		vim.notify("Cannot open a directory: " .. file_path, vim.log.levels.WARN)
		return
	end

	log("Opening selected file: " .. file_path)

	-- Close the scratch buffer first
	vim.api.nvim_buf_delete(buf, { force = true })

	-- Open the file in a new buffer
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))

	-- If linenumber is valid and greater than 0, move to that line
	if linenumber and linenumber > 0 then
		vim.api.nvim_win_set_cursor(0, { linenumber, 0 })
	end
end

function M.open_buffer_switching_history()
	-- Define the history file path
	local history_file = require("phxm.properties").current_project.project_path .. "/.buffer_switching_history"

	-- Read the file content
	local file_content = {}
	local file = io.open(history_file, "r")
	if file then
		for line in file:lines() do
			table.insert(file_content, line)
		end
		file:close()
	else
		vim.notify("History file not found: " .. history_file, vim.log.levels.ERROR)
		return
	end

	-- Create and configure a scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, file_content)

	-- Apply highlight groups to each line
	for i, full_path in ipairs(file_content) do
		-- Generate and retrieve highlight groups
		local meta_hl, dir_hl, file_hl, meta, dir, file = set_path_highlights(full_path)
		if not meta_hl or not dir_hl or not file_hl then
			vim.notify("Failed to generate highlights for: " .. full_path, vim.log.levels.WARN)
			goto continue
		end

		-- Highlight the metadata part                                     2
		vim.api.nvim_buf_add_highlight(buf, -1, meta_hl, i - 1, 0, #meta + 3)

		-- Highlight the directory part
		if dir ~= "" then
			vim.api.nvim_buf_add_highlight(buf, -1, dir_hl, i - 1, #meta + 3, #meta + 3 + #dir + 1)
		end

		-- Highlight the file part
		vim.api.nvim_buf_add_highlight(buf, -1, file_hl, i - 1, #meta + 3 + #dir + 1, -1)

		::continue::
	end

	-- Make the buffer read-only and hidden
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"

	-- Open the buffer in a split
	vim.api.nvim_set_current_win(vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = vim.o.columns - 4,
		height = vim.o.lines - 4,
		row = math.floor((vim.o.lines - 20) / 2),
		col = math.floor((vim.o.columns - 80) / 2),
		border = "rounded",
	}))

	-- Bind the Enter key to open the selected file
	vim.keymap.set("n", "<CR>", M.open_selected, { buffer = buf, noremap = true, silent = true })

	-- Bind the `q` and `<Esc>` keys to close the buffer
	vim.keymap.set("n", "q", function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true })
end
-------------------------------

-- Function to update the history file
function M.update_history(buffer_name, line_number, desc)
	desc = desc or "-"
	line_number = line_number or "-"
	-- In case desc has special chars
	desc = desc:gsub(":", ""):gsub("%[", ""):gsub("%]", "")
	local absolute_path
	local function is_absolute(path)
		return path:sub(1, 1) == "/"
	end

	--
	-- Resolve relative path to absolute path
	if not is_absolute(buffer_name) then
		absolute_path = vim.fn.fnamemodify(buffer_name, ":p")
	else
		absolute_path = buffer_name
	end

	absolute_path = "[" .. line_number .. ":" .. desc .. "] " .. absolute_path
	local history_file = require("phxm.properties").current_project.project_path .. "/.buffer_switching_history"
	local max_lines = 20
	local lines = {}

	-- Read the existing history file
	local file = io.open(history_file, "r")
	if file then
		for line in file:lines() do
			-- Avoid duplicates and ensure paths are absolute
			if line ~= absolute_path then
				table.insert(lines, line)
			end
		end
		file:close()
	end

	-- Add the new absolute buffer path at the top
	table.insert(lines, 1, absolute_path)

	-- Truncate the list to the maximum allowed lines
	while #lines > max_lines do
		table.remove(lines)
	end

	-- Write the updated history back to the file
	file = io.open(history_file, "w")
	if file then
		for _, line in ipairs(lines) do
			file:write(line .. "\n")
		end
		file:close()
	else
		vim.notify("Failed to write buffer history file: ")
	end
end

-- Function to set the previous buffer
local function set_current_buffer(buffer)
	-- Import the current project path from the properties module
	local properties = require("phxm.properties")
	local current_path = properties.current_project.project_path .. "/.current_buffer"
	local previous_path = properties.current_project.project_path .. "/.previous_buffer"

	-- Check if the buffer corresponds to an existing file
	local function file_exists(file_path)
		local file = io.open(file_path, "r")
		if file then
			file:close()
			return true
		else
			return false
		end
	end
	-- Only save realy files in switch memory
	if not file_exists(buffer) then
		--	error("Buffer is not an existing file on disk: " .. buffer)
		return
	end

	-- Check if a current buffer exists
	local current_file = io.open(current_path, "r")
	if current_file then
		-- Read the current buffer and move it to .previous_buffer
		local current_buffer = current_file:read("*a")
		current_file:close()

		-- If the current buffer matches the new buffer, do nothing
		-- Reason: when starting editor it is entering the last buffer which is same as the one stored in .current_buffer
		if current_buffer and current_buffer == buffer then
			return
		end

		-- Write the current buffer to .previous_buffer
		if current_buffer and current_buffer ~= "" then
			local previous_file, err = io.open(previous_path, "w")
			if not previous_file then
				error("Failed to write previous buffer: " .. (err or "unknown error"))
			end
			previous_file:write(current_buffer)
			previous_file:close()
		end
	end

	-- Write the new buffer to .current_buffer
	local new_file, err = io.open(current_path, "w")
	if not new_file then
		error("Failed to write current buffer: " .. (err or "unknown error"))
	end
	new_file:write(buffer)
	new_file:close()
end

-- Function to get the previous buffer
local function get_previous_buffer()
	-- Import the current project path from the properties module
	local properties = require("phxm.properties")
	local storage_path = properties.current_project.project_path .. "/.previous_buffer"

	-- Try to open the file for reading
	local file, err = io.open(storage_path, "r")
	if not file then
		return nil -- File does not exist
	end

	-- Read the buffer name from the file
	local buffer = file:read("*a")
	file:close()

	-- Return nil if the content is empty
	if not buffer or buffer == "" then
		return nil
	end

	return buffer
end

-- Record buffer change, storing the previous buffer and updating to the new buffer for each project
function M.record_buffer_change()
	local phxm = require("phxm")
	local props = require("phxm.properties")
	if not props.current_project then
		return
	end

	local current_buf = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

	set_current_buffer(current_buf)
end

M.switch_to_buffer_by_path = function(target_path)
	-- Normalize target path (to handle relative vs absolute differences)
	local normalized_target = vim.fn.fnamemodify(target_path, ":p")

	-- Iterate through all listed buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local buf_name = vim.api.nvim_buf_get_name(bufnr)

		-- Normalize buffer path to avoid mismatches
		local normalized_buf_name = vim.fn.fnamemodify(buf_name, ":p")

		-- Check if the buffer matches the given path
		if normalized_buf_name == normalized_target then
			M.switch_to_buffer(bufnr)
			return -- Exit early once found
		end
	end
end

-- Switch to a specific buffer, and update the buffer history accordingly
function M.switch_to_buffer(bufnr)
	vim.api.nvim_set_current_buf(bufnr)
	vim.defer_fn(function()
		-- Issue event phxmPostSwitchedBuffer
		vim.api.nvim_exec_autocmds("User", { pattern = "phxmPostSwitchedBuffer" })
	end, 1)
end

-- See relevant auto cmds in init.lua
--

-- Switch to the previous buffer within the current project
function M.switch_to_previous_buffer()
	local phxm = require("phxm")
	local props = require("phxm.properties")
	local previous_buffer = get_previous_buffer()
	if not previous_buffer then
		print("No previous buffer to switch to.")
		return
	end
	-- Check if the buffer exists
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == previous_buffer then
			M.switch_to_buffer(buf)
			--			vim.api.nvim_set_current_buf(buf) -- Switch to the existing buffer
			return
		end
	end

	-- If buffer doesn't exist but the path is a valid file, open it
	if vim.fn.filereadable(previous_buffer) == 1 then
		vim.cmd("edit " .. vim.fn.fnameescape(previous_buffer))
	else
		print("Buffer not found, and file is not readable:", previous_buffer)
	end
end
function M.re_bind_buffer_keys()
	local dynkey = require("dynkey")
	local project = require("phxm.project")
	local prop = require("phxm.properties")
	local prefix_keys = "="
	local project_name = prop.current_project.name
	-- Make sure it is local to the current project directory
	local key_group_id = context .. ":[project:" .. project_name .. "]:" .. prefix_keys

	dynkey.unbind_latest_bindings(context)

	dynkey.add_group(key_group_id, prefix_keys)

	-- Get a list of all listed buffers, regardless of whether they are loaded or unloaded
	local buffers = vim.fn.getbufinfo({ buflisted = 1 })

	-- Define the path to the .named_buffers file (JSON format)
	local named_buffers_file_path = prop.current_project.project_path .. "/.named_buffers"

	-- Load the named buffers from the JSON file
	local named_buffers = {}
	if vim.fn.filereadable(named_buffers_file_path) == 1 then
		local json_content = vim.fn.readfile(named_buffers_file_path)
		if json_content and #json_content > 0 then
			-- Parse the JSON file
			local ok, parsed_data = pcall(vim.fn.json_decode, table.concat(json_content, "\n"))

			if ok and parsed_data then
				named_buffers = parsed_data
			else
				log("Error parsing .named_buffers JSON file")
			end
		end
	end

	-- Iterate through each buffer
	for _, buf_info in ipairs(buffers) do
		-- Target all buffers except 'nofile'
		--TODO: Check name instead
		if buf_info.buftype ~= "nofile" then
			-- Ensure buffer has a valid name (file path)
			local buf_name = buf_info.name
			if buf_name and buf_name ~= "" then
				-- Skip the TODO.md buffer as we have quick commands for that
				if buf_name:find(prop.current_project.project_path .. "/TODO.md", 1, true) then
					goto continue
				end
				-- Check if the buffer name matches any of the named buffers from the JSON
				local original_name = buf_name
				-- will be same as original if none is found
				local custom_name = named_buffers[buf_name] or buf_name

				-- Bind a key to switch to this buffer
				local key_func = function()
					M.switch_to_buffer(buf_info.bufnr) -- Switch to this buffer
				end

				-- Add a key to the group (use the custom name or the buffer's path as the key description)
				-- NOTE: Important to use the original name (which is full path) as identifier, not the custom name, or we get duplicates when changing key and updating this buffer listing
				dynkey.make_key(key_group_id, original_name, key_func, "n", custom_name)

				::continue::
			else
				-- Log invalid or empty buffer name
				--log("Buffer #" .. buf_info.bufnr .. " has no valid name, skipping")
			end
		else
			-- Log skipped buffers of type 'nofile'
			--log("Buffer #" .. buf_info.bufnr .. " is of type 'nofile', skipping")
		end
	end

	-- Finalize and bind the keys for the buffer
	dynkey.finalize(key_group_id)
	dynkey.bind_keys(context, key_group_id)
end
return M
