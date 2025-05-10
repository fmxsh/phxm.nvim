-- Create the jump_state module
local M = {}

-- Internal storage for the state
local jump_state = nil

--- Sets the jump state with path, line number, and description.
-- @param path string: The file path to jump to.
-- @param line_number number|nil: The optional line number to jump to.
-- @param desc string: A description of the jump state.
function M.set(path, line_number, desc)
	if not path or not desc then
		error("Both path and desc parameters are required")
	end
	jump_state = {
		path = path,
		line_number = line_number,
		desc = desc,
	}
end

--- Retrieves and clears the stored jump state.
-- @return table|nil: The jump state containing path, line_number, and desc, or nil if no state is set.
function M.get()
	local state = jump_state
	jump_state = nil -- Clear the state
	return state
end

--- Checks if a jump state is currently set.
-- @return boolean: True if a jump state exists, false otherwise.
function M.has_state()
	return jump_state ~= nil
end

return M
