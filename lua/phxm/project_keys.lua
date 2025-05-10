local helpers = require("phxm.helpers")
local M = {}

-- Function to recursively scan project directories for .key files and return table of key-name pairs
function M.scan_project_dirs_for_keys(target_dir)
	local root = target_dir
	local result = {}

	-- Helper function to scan for .key and .name files
	local function scan_dir(dir)
		-- Look for .key file
		local key_file = dir .. "/.key"
		if vim.fn.filereadable(key_file) == 1 then
			local key = vim.fn.readfile(key_file)[1]
			local name_file = dir .. "/.name"
			local name
			local path = dir

			-- Look for .name file
			if vim.fn.filereadable(name_file) == 1 then
				name = vim.fn.readfile(name_file)[1]
			else
				-- If .name file does not exist, get the last two directory names
				name = helpers.get_two_dir_names(dir, root)
			end

			-- Add key-name pair to result table
			if key and name then
				table.insert(result, { key = key, name = name, path = path })
			end
		end
	end

	--	-- Recursively scan directories
	--	local function scan_recursive(dir)
	--		scan_dir(dir)
	--		local subdirs = vim.fn.glob(dir .. "/*", true, true)
	--		for _, subdir in ipairs(subdirs) do
	--			if vim.fn.isdirectory(subdir) == 1 then
	--				scan_recursive(subdir)
	--			end
	--		end
	--	end
	local function scan_recursive(dir)
		scan_dir(dir)
		local subdirs = vim.fn.glob(dir .. "/*", true, true)
		for _, subdir in ipairs(subdirs) do
			-- Check if the path is a directory and not a symlink
			local stat = vim.uv.fs_lstat(subdir)
			if stat and stat.type == "directory" then
				scan_recursive(subdir)
			end
		end
	end

	-- Start scanning from base_dir
	scan_recursive(target_dir)

	return result
end
return M
