local helpers = require("phxm.helpers")
local M = {}

-------------------------
local function sanitize_for_hl_group(name)
	return name:gsub("%W", "_") -- Replace non-alphanumeric characters with underscores
end

local function set_path_highlights(path)
	local keypoint = require("keypoint") -- Assuming keypoint module is available

	-- Split the path into directory and file
	local dir, file = path:match("^(.*)/([^/]+)$")
	dir = dir or ""
	file = file or path

	-- Sanitize names for highlight group safety
	local sanitized_dir = sanitize_for_hl_group(dir)
	local sanitized_file = sanitize_for_hl_group(file)

	-- Generate colors based on dir and file
	local dir_color = keypoint.string_to_color(dir)
	dir_color = keypoint.adjust_color(dir_color, 60, 80)
	local file_color = keypoint.string_to_color(file)
	file_color = keypoint.adjust_color(file_color, 60, 90)

	-- Create dynamic highlight groups
	local dir_hl = "DirHlGroup_" .. sanitized_dir
	local file_hl = "FileHlGroup_" .. sanitized_file

	-- Define the highlight groups
	vim.api.nvim_set_hl(0, dir_hl, { fg = dir_color })
	vim.api.nvim_set_hl(0, file_hl, { fg = file_color })

	return dir_hl, file_hl
end

function M.open_selected()
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_get_current_line()

	-- Validate the selection
	if line == "" then
		vim.notify("Invalid selection.", vim.log.levels.WARN)
		return
	end

	-- Construct the absolute file path
	local file_path = line -- Directly use the line as the absolute path
	if vim.fn.isdirectory(file_path) == 1 then
		vim.notify("Cannot open a directory.", vim.log.levels.WARN)
		return
	end

	log("Opening selected file ")
	-- Close the scratch buffer first
	--	vim.cmd("bdelete " .. buf)
	vim.api.nvim_buf_delete(buf, { force = true })

	-- Open the file in a new buffer
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))
end

function M.open_project_switching_history()
	local history_file = require("phxm.properties").root.root_path .. "/.project_switching_history"
	-- Define the history file path

	-- Read the file content
	local file_content = {}
	local file = io.open(history_file, "r")
	if file then
		for line in file:lines() do
			table.insert(file_content, line)
		end
		file:close()
	else
		vim.notify("History file not found: ", vim.log.levels.ERROR)
		return
	end

	-- Create and configure a scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, file_content)

	-- Apply highlight groups to each line
	for i, path in ipairs(file_content) do
		local dir_hl, file_hl = set_path_highlights(path)
		local dir, file = path:match("^(.*)/([^/]+)$")
		dir = dir or ""
		file = file or path

		-- Highlight the directory part
		if dir ~= "" then
			vim.api.nvim_buf_add_highlight(buf, -1, dir_hl, i - 1, 0, #dir)
		end

		-- Highlight the file part
		vim.api.nvim_buf_add_highlight(buf, -1, file_hl, i - 1, #dir, -1)
	end

	-- Make the buffer read-only and hidden
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "hide"
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

	vim.keymap.set("n", "<Esc>", function()
		local buf = vim.api.nvim_get_current_buf()
		vim.cmd("bdelete! " .. buf)
		-- TODO:: do other than bdelete, wipe or vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true })

	-- Bind the `q` key to close the buffer
	vim.keymap.set("n", "q", function()
		local buf = vim.api.nvim_get_current_buf()
		vim.cmd("bdelete! " .. buf)
		-- TODO:: do other than bdelete, wipe or vim.api.nvim_buf_delete(buf, { force = true })
	end, { buffer = buf, noremap = true, silent = true })
end

-------------------------------

-- Function to update the history file
function M.update_history(project_path)
	-- Resolve relative path to absolute path
	local absolute_path = vim.fn.fnamemodify(project_path, ":p")

	-- Define the history file path
	local history_file = require("phxm.properties").root.root_path .. "/.project_switching_history"
	local max_lines = 20
	local lines = {}

	-- Read the existing history file
	local file = io.open(history_file, "r")
	if file then
		local previous_line = nil
		for line in file:lines() do
			-- Ensure paths are absolute and avoid consecutive duplicates
			local resolved_line = vim.fn.fnamemodify(line, ":p")
			if resolved_line ~= previous_line then
				table.insert(lines, resolved_line)
			end
			previous_line = resolved_line
		end
		file:close()
	end

	-- Add the new absolute buffer path at the top
	if #lines == 0 or lines[1] ~= absolute_path then
		table.insert(lines, 1, absolute_path)
	end

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
		vim.notify("Failed to write project history file.")
	end
end

---------------------------------
-- Function to set the previous project
local function set_previous_project(project)
	-- Import the root path from the properties module
	local properties = require("phxm.properties")
	local storage_path = properties.root.root_path .. "/.previous_project"

	-- Write the project name to the file
	local file, err = io.open(storage_path, "w")
	if not file then
		error("Failed to write previous project: " .. (err or "unknown error"))
	end
	file:write(project)
	file:close()
end

local function get_previous_project()
	-- Import the root path from the properties module
	local properties = require("phxm.properties")
	local storage_path = properties.root.root_path .. "/.previous_project"

	-- Try to open the file for reading
	local file, err = io.open(storage_path, "r")
	if not file then
		return nil -- File does not exist
	end

	-- Read the project name from the file
	local project = file:read("*a")
	file:close()

	-- Return nil if the content is empty
	if not project or project == "" then
		return nil
	end
	return project
end

local function project_files_list(project_dir)
	local possible_project_files = {
		include = project_dir .. "/include",
		session = project_dir .. "/.session",
	}

	return possible_project_files
end
local function get_relative_project_path(project_path, root_path)
	local relative_path = vim.fn.substitute(project_path, "^" .. vim.fn.escape(root_path, "/") .. "/", "", "")

	return relative_path
end
local function get_project_name_or_dir(target_project_dir, root)
	-- Check if M.current_project_dir is nil
	local dir = target_project_dir
	if not dir then
		return "Not set"
	end

	-- Proceed if M.current_project_dir is valid
	local name_file = dir .. "/.name"
	local name

	-- Look for .name file
	if vim.fn.filereadable(name_file) == 1 then
		name = vim.fn.readfile(name_file)[1]:gsub("\n$", "") -- Use the custom project name from .name file
	else
		-- If .name file does not exist, get the last two directory names
		name = helpers.get_two_dir_names(dir, root):gsub("\n$", "") -- Use the last two directory names
	end

	return name
end

function M.list_included_paths()
	if require("phxm").current_project.project_path then
		local include_file = require("phxm").current_project.project_path .. "/include"
		if vim.fn.filereadable(include_file) == 1 then
			return vim.fn.readfile(include_file)
		end
	end
	return { "Include file not found or not readable." }
end

function M.destroy() end
-- Function to find the nearest directory containing `.selected_project`
local function find_projects_root(starting_dir)
	local Path = require("plenary.path")
	local current_dir = Path:new(starting_dir):absolute()

	while current_dir do
		-- Define the full path to `.selected_project` in the current directory
		local project_file = Path:new(current_dir .. "/.selected_project")

		-- Check if `.selected_project` exists in this directory
		if project_file:exists() then
			return current_dir -- Return the directory if the file is found
		end

		-- Move up one directory
		local parent_dir = Path:new(current_dir):parent()
		if parent_dir == current_dir then
			break -- Stop if we have reached the root directory
		end
		current_dir = parent_dir
	end

	-- Return nil if no `.selected_project` file was found in any parent directory
	return nil
end
function M.external_plugin_call_switch_to_project(target_project)
	require("phxm.user_actions").switch_to_project(target_project)
	local buffer = require("phxm.buffer")
	local funview = require("funview")
	-- we do this here, because when we switch project, lots of stuff shuts down and we cant access common stuff,
	-- so when switching is done, we can safely fix these
	-- NOTE: There is some inconsistency in placing it here, and having other rebinding stuff in phxm init()
	-- FIX: Put this inside here instead so we retain within this plugin the control of defining the code
	buffer.re_bind_buffer_keys()
	funview.re_bind_function_keys()
end
function M.switch_to_previous_project()
	local previous_project = get_previous_project()
	if previous_project then
		M.switch_to_project(previous_project)
		--NOTE: question is if this should be here or in the switch_to_project function, however we do not bind other stuff there, like jump to function keys specific to buffer keys etc
		local buffer = require("phxm.buffer")
		local project = require("phxm.project")
		local funview = require("funview")
		log("Switching to previous project")
		buffer.re_bind_buffer_keys()
		--project.redo_symlinks()
		funview.re_bind_function_keys()
	end
end
function M.switch_to_project(selected_project)
	local phxm = require("phxm")
	local prop = require("phxm.properties")
	local session = require("phxm.session")
	if prop.current_project then
		-- if new target project is same as current project, do nothing
		-- rather keep the unique previos project
		if prop.current_project.project_path == selected_project then
			return
		end
		set_previous_project(prop.current_project.project_path)
	end

	vim.defer_fn(function()
		vim.api.nvim_exec_autocmds("User", { pattern = "preSwitchToProject" })
	end, 1)
	-- Save current buffer if it's a real buffer and modified
	if vim.bo.modified and vim.bo.buftype == "" and vim.fn.buflisted(vim.fn.bufnr()) == 1 then
		vim.cmd("write")
	end

	-- Before destroying anything, update current selected project path
	--vim.fn.writefile({ selected_project }, prop.root.selected_project_file)
	local selected_project_file = find_projects_root(selected_project) .. "/.selected_project"
	vim.fn.writefile({ selected_project }, selected_project_file)

	-- Do we need to destroy? Only if previous has been loaded
	if prop.root and prop.current_project then
		session.save()

		-- Now we can destroy, as any later initializing will rely on whats written on disk

		phxm.destroy()
		session.destroy()
		prop.destroy()
	end

	-- Any possible switching above has been written to file. The following loading of properties relies on the file on disk
	prop.load_root_properties(phxm.opts.root) -- start from the initial settings of root dir

	-- Setup the current_project table
	prop.load_project_properties(prop.root.selected_project)

	if session.session_file_exists() then
		session.load()
	end

	-- We have loaded session (its buffers etc) now in absence of any autocommands the init below creates
	phxm.init()

	require("phxm.project").redo_symlinks()

	require("phxm.project").update_history(selected_project)
	--print("Switching to project: " .. prop.current_project.relative_project_path)

	-- NOTE: Would thing good put these here, no, switch_to_project is a function that is called at early init when funview isnt loaded, callers of switch_to_project should do call whatever
	--require("phxm.project").re_bind_buffer_keys()
	--require("funview").re_bind_function_keys()

	vim.defer_fn(function()
		vim.api.nvim_exec_autocmds("User", { pattern = "postSwitchToProject" })
	end, 1)
end

function M.get_subsequent_project_keys_for_keypoint_mapping()
	local project_key_name_list =
		require("phxm.project_keys").scan_project_dirs_for_keys(require("phxm.properties").root.root_path)
	local project_keys_config = {}

	-- Iterate through the key-name pairs and create the key-action table
	for _, entry in ipairs(project_key_name_list) do
		project_keys_config[entry.key] = {
			desc = entry.name,
			action = function()
				require("phxm.project").external_plugin_call_switch_to_project(entry.path)
			end,
		}
	end

	return project_keys_config
end

function M.redo_symlinks()
	local prop = require("phxm.properties")
	-- Define the paths based on current project properties
	local project_path = prop.current_project.project_path
	local include_file = project_path .. "/include"
	local symlink_dir = project_path .. "/symlinks"

	-- Check if the include file exists, do nothing if it doesn't
	local include_file_stat = vim.uv.fs_stat(include_file)
	if not include_file_stat then
		print("Include file not found; nothing to do.")
		return
	end

	-- Create the symlink directory if it doesn't exist
	local symlink_dir_stat = vim.uv.fs_stat(symlink_dir)
	if not symlink_dir_stat then
		local ok, err = vim.uv.fs_mkdir(symlink_dir, 493) -- 493 is the octal for 0755 permissions
		if not ok then
			print("Failed to create symlink directory: " .. err)
			return
		end
	end

	-- Remove all existing symlinks in the symlink directory
	for _, file in ipairs(vim.fn.readdir(symlink_dir)) do
		local symlink_path = symlink_dir .. "/" .. file
		local stat = vim.uv.fs_lstat(symlink_path)
		if stat and stat.type == "link" then
			vim.uv.fs_unlink(symlink_path)
		end
	end

	-- Read paths from the include file
	local paths = {}
	for line in io.lines(include_file) do
		-- Trim whitespace and check if the line is not empty
		local trimmed_line = line:match("^%s*(.-)%s*$") -- Remove leading and trailing whitespace
		if trimmed_line ~= "" then
			table.insert(paths, trimmed_line)
		end
	end

	-- Create new symlinks in the symlink directory
	for _, target_path in ipairs(paths) do
		-- Remove trailing slash from target_path if it exists
		-- else we get problems saying path already exists, like:
		-- Failed to create symlink for /home/f/code/credcrypdir/: EEXIST: file already exists: /home/f/code/credcrypdir/ -> /home/f/.vim-projects/code/credcrypdir/
		target_path = target_path:gsub("/$", "")

		local symlink_path = symlink_dir .. "/" .. vim.fn.fnamemodify(target_path, ":t")
		local ok, err = vim.uv.fs_symlink(target_path, symlink_path)
		if not ok then
			print("Failed to create symlink for " .. target_path .. ": " .. err)
		end
	end
end

return M
