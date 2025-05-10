local M = {}

function M.get_current_buffer_name()
	local bufname = vim.api.nvim_buf_get_name(0) -- Get the current buffer name
	if bufname == "" then
		return "[No Name]" -- Return "[No Name]" if the buffer has no name
	else
		return bufname -- Return the actual buffer name
	end
end

function M.get_two_dir_names(path, root)
	-- Remove the root part from the path
	local relative_path = vim.fn.substitute(path, "^" .. vim.fn.escape(root, "/") .. "/", "", "")
	local dirs = vim.split(relative_path, "/")

	-- Retrieve the last two directories if available, else fallback
	if #dirs >= 2 then
		return dirs[#dirs - 1] .. "/" .. dirs[#dirs]
	elseif #dirs == 1 then
		return dirs[1]
	else
		return "[Root Directory]" -- Default case if no directories found
	end
end

return M
