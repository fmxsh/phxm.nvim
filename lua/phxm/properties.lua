local helpers = require("phxm.helpers")
local M = {}

M.current_project = nil
M.root = nil
function M.init(root)
	-- Set up the root table
	M.load_root_properties(root)

	-- Setup the current_project table
	M.load_project_properties(M.root.selected_project)
end
function M.destroy()
	M.current_project = nil
	M.root = nil
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

function M.update_project_name(name)
	if not M.root then
		print("Error: Root properties not loaded.")
		return
	end

	local name = name:gsub("^%s*(.-)%s*$", "%1")
	M.current_project.name = name
end

local function get_project_name_or_dir(target_project_dir)
	if not M.root then
		print("Error: Root properties not loaded.")
		return
	end
	local root = M.root.root_path
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

function M.load_root_properties(root)
	local project_file = root .. "/.selected_project"
	local content = ""

	-- Try to open and read the .selected_project file
	local file = io.open(project_file, "r")
	if file then
		content = file:read("*all"):gsub("\n$", "")
		file:close()
	else
		print("Warning: .selected_project file not found.")
		content = ""
	end
	-- Return a table with the content of .selected_project
	M.root = {
		selected_project = content,
		selected_project_file = root .. "/.selected_project",
		root_path = root,
		keys = require("phxm.project_keys").scan_project_dirs_for_keys(root),
	}
end
function M.load_project_properties(target_project_dir)
	if not M.root then
		print("Error: Root properties not loaded.")
		return
	end
	local root = M.root.root_path
	local current_project = {}
	current_project.files = {}
	current_project.files = project_files_list(target_project_dir)
	current_project.name = get_project_name_or_dir(target_project_dir)
	current_project.project_path = target_project_dir
	current_project.relative_project_path = get_relative_project_path(target_project_dir, root)

	M.current_project = current_project
end
function M.list_included_paths()
	if require("phxm.properties").current_project.project_path then
		local include_file = require("phxm.properties").current_project.project_path .. "/include"
		if vim.fn.filereadable(include_file) == 1 then
			return vim.fn.readfile(include_file)
		end
	end
	return { "Include file not found or not readable." }
end

return M
