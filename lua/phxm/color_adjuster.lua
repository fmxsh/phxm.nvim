local M = {}
local config_path = vim.fn.expand("~/.config/")

-- Helper function to read a value from a file or return a default
local function read_value(file_path, default)
	local file = io.open(file_path, "r")
	if file then
		local value = tonumber(file:read("*a"))
		file:close()
		return value or default
	end
	return default
end

-- Helper function to write a value to a file
local function write_value(file_path, value)
	local file = io.open(file_path, "w")
	if file then
		file:write(tostring(value))
		file:close()
	end
end

-- Increment or decrement brightness
function M.increase_brightness()
	local file_path = config_path .. "phxm_syntax_color_brightness"
	local brightness = read_value(file_path, 50)
	brightness = math.min(brightness + 1, 100) -- Ensure brightness does not exceed 100
	write_value(file_path, brightness)
	print("Current brightness: " .. brightness)
	return brightness
end

function M.decrease_brightness()
	local file_path = config_path .. "phxm_syntax_color_brightness"
	local brightness = read_value(file_path, 50)
	brightness = math.max(brightness - 1, 0) -- Ensure brightness does not go below 0
	write_value(file_path, brightness)
	print("Current brightness: " .. brightness)
	return brightness
end

-- Increment or decrement saturation
function M.increase_saturation()
	local file_path = config_path .. "phxm_syntax_color_saturation"
	local saturation = read_value(file_path, 50)
	saturation = math.min(saturation + 1, 100) -- Ensure saturation does not exceed 100
	write_value(file_path, saturation)
	print("Current saturation: " .. saturation)
	return saturation
end

function M.decrease_saturation()
	local file_path = config_path .. "phxm_syntax_color_saturation"
	local saturation = read_value(file_path, 50)
	saturation = math.max(saturation - 1, 0) -- Ensure saturation does not go below 0
	write_value(file_path, saturation)
	print("Current saturation: " .. saturation)
	return saturation
end
-- Get current brightness
function M.get_current_brightness()
	local file_path = config_path .. "phxm_syntax_color_brightness"
	local brightness = read_value(file_path, 50)
	return brightness
end

-- Get current saturation
function M.get_current_saturation()
	local file_path = config_path .. "phxm_syntax_color_saturation"
	local saturation = read_value(file_path, 50)
	return saturation
end
return M
