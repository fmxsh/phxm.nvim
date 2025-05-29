-- helper.lua
local M = {}
local phxm = require("phxm")
local prop = require("phxm.properties")

local project = require("phxm.project")
---
---
---
---
-- This is old version relying on the global tmux terminal, we use the localized floating terminal now
function M.terminal_command_quick_run2()
	-- Function to check if the NvimTerminal exists in tmux
	local function check_terminal_exists()
		local output = vim.fn.system("tmux list-windows -t WorkSession 2>/dev/null | grep NvimTerminal")
		return vim.v.shell_error == 0 and output ~= ""
	end

	-- Simulate Alt+i to trigger the tmux session creation
	vim.api.nvim_input("<M-i>")

	-- Function to continue execution after ensuring the terminal exists
	local function continue_execution()
		-- Get the project root directory
		local project_path = prop.current_project.project_path

		-- Construct the path to the file
		local file_path = project_path .. "/terminal_command_quick_run"

		-- Check if the file exists and is executable
		if vim.fn.filereadable(file_path) == 0 or vim.fn.executable(file_path) == 0 then
			print("File 'terminal_command_quick_run' either does not exist or is not executable in the project root.")
			return
		end

		-- Attach to the session and select the NvimTerminal window
		vim.fn.system("tmux attach-session -t WorkSession ; tmux select-window -t NvimTerminal")

		-- Cancel any previous thing that may have been started.
		vim.fn.system("tmux send-keys -t WorkSession:NvimTerminal C-c")
		-- Define the terminal command
		local command = "tmux send-keys -t WorkSession:NvimTerminal '" .. file_path .. "' C-m"

		-- Execute the terminal command
		vim.fn.system(command)

		print("Command sent successfully to NvimTerminal.")
	end

	-- Poll for readiness of the NvimTerminal window
	local retries = 10
	local interval = 500 -- milliseconds

	local function poll_for_terminal()
		if check_terminal_exists() then
			continue_execution()
		else
			if retries > 0 then
				retries = retries - 1
				vim.defer_fn(poll_for_terminal, interval)
			else
				print("Error: 'NvimTerminal' in tmux did not become ready in time.")
			end
		end
	end

	-- Start polling
	poll_for_terminal()
end

--Original version
-- function M.terminal_command_quick_run()
-- 	-- Simulate Alt+i
--
-- 	-- Get the project root directory
-- 	local project_path = prop.current_project.project_path
--
-- 	-- Construct the path to the file
-- 	local file_path = project_path .. "/terminal_command_quick_run"
--
-- 	-- Check if the file exists and is executable
-- 	if vim.fn.filereadable(file_path) == 0 or vim.fn.executable(file_path) == 0 then
-- 		print("File 'terminal_command_quick_run' either does not exist or is not executable in the project root.")
-- 		return
-- 	end
--
-- 	vim.api.nvim_input("<M-i>")
-- 	-- Define the terminal command
-- 	local command = "tmux send-keys -t WorkSession:NvimTerminal '" .. file_path .. "' C-m"
--
-- 	-- Execute the terminal command
-- 	vim.fn.system(command)
-- end

-- Function to create a new terminal in a floating window

-----------------------START QUICK TERMINAL-----------------------
-- obsolete local stored_term_buf, stored_term_win, stored_title_win, term_initialized
-- Global table to track the currently selected terminal for each project
local currently_selected_terminal = {}
local terminal_count = 0 -- Track the number of terminals created
local terminals = {} -- List of all terminals
local terminal_creation_count = 0

-- Function to darken a color by a percentage
local function darken_color(hex_color, percentage)
	local r = tonumber(hex_color:sub(2, 3), 16)
	local g = tonumber(hex_color:sub(4, 5), 16)
	local b = tonumber(hex_color:sub(6, 7), 16)

	local factor = (100 - percentage) / 100
	r = math.floor(r * factor)
	g = math.floor(g * factor)
	b = math.floor(b * factor)

	return string.format("#%02x%02x%02x", r, g, b)
end

-- Function to generate a unique highlight group for each terminal with darker colors
local function create_terminal_highlight()
	terminal_count = terminal_count + 1
	local highlight_name = "TerminalHighlight" .. terminal_count

	-- Generate a random light color
	local base_color = string.format("#%06x", math.random(0x888888, 0xFFFFFF)) -- Lighter base color range
	local darkened_color = darken_color(base_color, 85)

	-- Set the highlight for the terminal
	vim.api.nvim_set_hl(0, highlight_name, { bg = darkened_color }) -- Darkened background
	return highlight_name
end

-- Function to create a floating title window
local function create_title_window(title, col, row, width, highlight_group)
	-- Create a buffer for the title
	local title_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { " " .. title .. " " }) -- Add title text

	-- Create the floating window for the title
	local opts = {
		relative = "editor",
		width = #title + 2, -- Title width with padding
		height = 1,
		col = col + math.floor((width - (#title + 4)) / 2), -- Center the title
		row = row - 1, -- Place above the terminal
		style = "minimal",
		border = "none",
	}
	local title_win = vim.api.nvim_open_win(title_buf, false, opts)

	-- Set the highlight for the title window
	vim.api.nvim_set_option_value(
		"winhl",
		"NormalFloat:" .. highlight_group .. ",FloatBorder:" .. highlight_group,
		{ win = title_win }
	)

	-- Set buffer options
	vim.bo[title_buf].bufhidden = "wipe" -- Wipe the buffer when closed
	vim.bo[title_buf].modifiable = false -- Make the buffer unmodifiable
	return title_win
end
-- Function to create a new terminal in a floating window
function M.create_new_terminal(project_path)
	local project_name = prop.current_project.name
	if not project_name then
		print("No current project detected!")
		return
	end

	-- Initialize terminal list for the project if not already present
	terminals[project_name] = terminals[project_name] or {}

	-- Check and hide the currently visible terminal for the project
	local current_index = currently_selected_terminal[project_name]
	if current_index then
		local current_terminal = terminals[project_name][current_index]
		if current_terminal then
			if vim.api.nvim_win_is_valid(current_terminal.win) then
				vim.api.nvim_win_hide(current_terminal.win)
			end
			if current_terminal.title_win and vim.api.nvim_win_is_valid(current_terminal.title_win) then
				vim.api.nvim_win_hide(current_terminal.title_win)
			end
		end
	end

	-- Create a new terminal buffer
	local new_term_buf = vim.api.nvim_create_buf(false, true) -- Create a new unlisted buffer

	-- Set up the floating window dimensions
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
	}

	-- Create a new floating window for the terminal
	local new_term_win = vim.api.nvim_open_win(new_term_buf, true, opts)

	-- Assign a unique background color to the terminal
	local highlight_group = create_terminal_highlight()
	vim.api.nvim_set_option_value(
		"winhl",
		"NormalFloat:" .. highlight_group .. ",FloatBorder:" .. highlight_group,
		{ win = new_term_win }
	)

	-- Create a title window above the terminal
	-- NOTE: terminal_creation_count is leftover thing, but still used to generate unique color groups for unique background of each terminal
	terminal_creation_count = terminal_creation_count + 1

	-- Create a title window above the terminal
	local terminal_number = #terminals[project_name] + 1

	local title = "[" .. project_name .. "] Project Terminal " .. terminal_number
	local new_title_win = create_title_window(title, col, row, width, highlight_group)

	-- Open fish shell in the terminal buffer
	vim.fn.termopen("fish", { cwd = project_path or vim.loop.cwd() }) -- Use fallback to current directory

	-- Set buffer options
	vim.bo[new_term_buf].buflisted = false -- Unlist buffer
	vim.bo[new_term_buf].filetype = "toggleterm" -- Neutral filetype for terminal

	-- Disable Treesitter for terminal
	vim.cmd(string.format("autocmd TermOpen <buffer=%d> lua require'nvim-treesitter'.detach()", new_term_buf))

	-- Start terminal in insert mode
	vim.cmd("startinsert")

	-- Store the terminal data in the project-specific list
	table.insert(terminals[project_name], {
		buf = new_term_buf,
		win = new_term_win,
		title_win = new_title_win,
		highlight_group = highlight_group,
		title = title,
	})

	-- Update the currently selected terminal for this project
	currently_selected_terminal[project_name] = #terminals[project_name]
end

-- Function to toggle the project directory terminal

function M.toggle_project_dir_terminal()
	local project_name = prop.current_project.name
	if not project_name then
		print("No current project detected!")
		return
	end

	local project_path = require("phxm.properties").current_project.project_path
	terminals[project_name] = terminals[project_name] or {}
	currently_selected_terminal[project_name] = currently_selected_terminal[project_name] or 0

	local project_terminals = terminals[project_name]
	local selected_index = currently_selected_terminal[project_name]
	local selected_terminal = project_terminals[selected_index]

	-- If the terminal window is open and valid, hide it
	if selected_terminal and vim.api.nvim_win_is_valid(selected_terminal.win) then
		vim.api.nvim_win_hide(selected_terminal.win)
		if selected_terminal.title_win and vim.api.nvim_win_is_valid(selected_terminal.title_win) then
			vim.api.nvim_win_hide(selected_terminal.title_win)
		end
		-- Do not reset `currently_selected_terminal[project_name]` to preserve the last active terminal
		return
	end

	-- If no valid terminal exists, create a new one
	if not selected_terminal then
		M.create_new_terminal(project_path)
	else
		-- Reopen the floating window for the existing terminal
		local width = math.floor(vim.o.columns * 0.8)
		local height = math.floor(vim.o.lines * 0.8)
		local col = math.floor((vim.o.columns - width) / 2)
		local row = math.floor((vim.o.lines - height) / 2)
		local highlight_group = selected_terminal.highlight_group

		local opts = {
			relative = "editor",
			width = width,
			height = height,
			col = col,
			row = row,
			style = "minimal",
			border = "rounded",
		}
		selected_terminal.win = vim.api.nvim_open_win(selected_terminal.buf, true, opts)

		-- Reapply the background color if reopening
		vim.api.nvim_set_option_value(
			"winhl",
			"NormalFloat:" .. highlight_group .. ",FloatBorder:" .. highlight_group,
			{ win = selected_terminal.win }
		)

		-- Create or reapply the title window above the terminal
		local title = selected_terminal.title
		selected_terminal.title_win = create_title_window(title, col, row, width, highlight_group)

		vim.cmd("startinsert") -- Ensure terminal starts in insert mode
	end
end

local function switch_to_terminal(project_name, index)
	if not project_name then
		print("No current project detected!")
		return
	end

	local project_terminals = terminals[project_name]
	if not project_terminals or #project_terminals == 0 then
		print("No terminals available for project: " .. project_name)
		return
	end

	if index < 1 or index > #project_terminals then
		print("No terminal at this position for project: " .. project_name)
		return
	end

	-- Close any currently visible terminal and title window
	local currently_selected_index = currently_selected_terminal[project_name]
	if currently_selected_index and project_terminals[currently_selected_index] then
		local currently_selected = project_terminals[currently_selected_index]
		if vim.api.nvim_win_is_valid(currently_selected.win) then
			vim.api.nvim_win_hide(currently_selected.win)
		end
		if currently_selected.title_win and vim.api.nvim_win_is_valid(currently_selected.title_win) then
			vim.api.nvim_win_hide(currently_selected.title_win)
		end
	end

	-- Switch to the new terminal
	local term = project_terminals[index]

	-- Calculate window dimensions and position
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Reopen the terminal window if necessary
	if not vim.api.nvim_win_is_valid(term.win) then
		local opts = {
			relative = "editor",
			width = width,
			height = height,
			col = col,
			row = row,
			style = "minimal",
			border = "rounded",
		}
		term.win = vim.api.nvim_open_win(term.buf, true, opts)
		vim.api.nvim_set_option_value(
			"winhl",
			"NormalFloat:" .. term.highlight_group .. ",FloatBorder:" .. term.highlight_group,
			{ win = term.win }
		)
	end

	-- Reopen the title window if necessary
	if not vim.api.nvim_win_is_valid(term.title_win) then
		term.title_win = create_title_window(term.title, col, row, width, term.highlight_group)
	end

	vim.cmd("startinsert") -- Ensure terminal starts in insert mode

	-- Update the currently selected terminal index for the project
	currently_selected_terminal[project_name] = index
end

function M.next_terminal()
	local project_name = prop.current_project.name
	if not project_name then
		print("No current project detected!")
		return
	end

	-- Get the terminal list for the current project
	local project_terminals = terminals[project_name]
	if not project_terminals or #project_terminals == 0 then
		print("No terminals created yet for project: " .. project_name)
		return
	end

	-- Get the current terminal index
	local current_index = currently_selected_terminal[project_name] or 1

	-- Increment index and wrap around if necessary
	local next_index = current_index + 1
	if next_index > #project_terminals then
		next_index = 1 -- Wrap around to the first terminal
	end

	-- Switch to the next terminal
	switch_to_terminal(project_name, next_index)

	-- Update the currently selected terminal
	currently_selected_terminal[project_name] = next_index
end

-- Function to go to the previous terminal for the current project
function M.previous_terminal()
	local project_name = prop.current_project.name
	if not project_name then
		print("No current project detected!")
		return
	end

	-- Get the terminal list for the current project
	local project_terminals = terminals[project_name]
	if not project_terminals or #project_terminals == 0 then
		print("No terminals created yet for project: " .. project_name)
		return
	end

	-- Get the current terminal index
	local current_index = currently_selected_terminal[project_name] or 1

	-- Decrement index and wrap around if necessary
	local prev_index = current_index - 1
	if prev_index < 1 then
		prev_index = #project_terminals -- Wrap around to the last terminal
	end

	-- Switch to the previous terminal
	switch_to_terminal(project_name, prev_index)

	-- Update the currently selected terminal
	currently_selected_terminal[project_name] = prev_index
end
function M.terminal_command_quick_run()
	local project_name = prop.current_project.name
	local project_path = prop.current_project.project_path

	if not project_name or not project_path then
		print("No current project detected or project path is missing!")
		return
	end

	-- Ensure terminals table exists for the project
	terminals[project_name] = terminals[project_name] or {}

	-- Check if the first terminal exists
	local first_terminal = terminals[project_name][1]
	local command = project_path .. "/terminal_command_quick_run"
	if first_terminal then
		-- If the first terminal exists, switch to it
		switch_to_terminal(project_name, 1)
	else
		-- Create a new terminal if it doesn't exist
		M.create_new_terminal(project_path)
	end
	-- Send Ctrl-C to stop any running process to cancel previous run if still active
	vim.fn.chansend(vim.b.terminal_job_id, "\x03\n") -- Ctrl-C is ASCII 0x03
	-- Ensure the terminal is in insert mode and send the command
	vim.cmd("startinsert")
	vim.fn.chansend(vim.b.terminal_job_id, command .. "\n")
end

-----------------------END QUICK TERMINAL-----------------------
------------- NON TITLE VERSION ----------------------
---local stored_term_buf, stored_term_win, term_initialized
-- local terminal_count = 0 -- Track the number of terminals created
--
-- -- Function to generate a unique highlight group for each terminal
-- local function create_terminal_highlight()
-- 	terminal_count = terminal_count + 1
-- 	local highlight_name = "TerminalHighlight" .. terminal_count
-- 	local color = string.format("#%06x", math.random(0x444444, 0xFFFFFF)) -- Random light background color
-- 	vim.api.nvim_set_hl(0, highlight_name, { bg = color, fg = "#c0caf5" }) -- Set the highlight
-- 	return highlight_name
-- end
--
-- -- Function to create a new terminal in a floating window
-- function M.create_new_terminal(project_path)
-- 	-- Create a new terminal buffer
-- 	stored_term_buf = vim.api.nvim_create_buf(false, true) -- Create a new unlisted buffer
-- 	term_initialized = false -- Reset initialization flag
--
-- 	-- Set up the floating window dimensions
-- 	local width = math.floor(vim.o.columns * 0.8)
-- 	local height = math.floor(vim.o.lines * 0.8)
-- 	local opts = {
-- 		relative = "editor",
-- 		width = width,
-- 		height = height,
-- 		col = math.floor((vim.o.columns - width) / 2),
-- 		row = math.floor((vim.o.lines - height) / 2),
-- 		style = "minimal",
-- 		border = "rounded",
-- 	}
--
-- 	-- Create a new floating window
-- 	stored_term_win = vim.api.nvim_open_win(stored_term_buf, true, opts)
--
-- 	-- Assign a unique background color to the terminal
-- 	local highlight_group = create_terminal_highlight()
-- 	vim.api.nvim_win_set_option(
-- 		stored_term_win,
-- 		"winhl",
-- 		"NormalFloat:" .. highlight_group .. ",FloatBorder:" .. highlight_group
-- 	)
--
-- 	-- Open fish shell in the terminal buffer
-- 	vim.fn.termopen("fish", { cwd = project_path or vim.loop.cwd() }) -- Use fallback to current directory
-- 	term_initialized = true
--
-- 	-- Set buffer options
-- 	vim.bo[stored_term_buf].buflisted = false -- Unlist buffer
-- 	vim.bo[stored_term_buf].filetype = "toggleterm" -- Neutral filetype for terminal
--
-- 	-- Disable Treesitter for terminal
-- 	vim.cmd(string.format("autocmd TermOpen <buffer=%d> lua require'nvim-treesitter'.detach()", stored_term_buf))
--
-- 	-- Start terminal in insert mode
-- 	vim.cmd("startinsert")
-- end
--
-- -- Function to toggle the project directory terminal
-- function M.toggle_project_dir_terminal()
-- 	local project_path = require("phxm.properties").current_project.project_path
--
-- 	-- If the terminal window is open and valid, hide it
-- 	if stored_term_win and vim.api.nvim_win_is_valid(stored_term_win) then
-- 		vim.api.nvim_win_hide(stored_term_win)
-- 		stored_term_win = nil
-- 		return
-- 	end
--
-- 	-- If no valid terminal buffer exists, create a new one
-- 	if not (stored_term_buf and vim.api.nvim_buf_is_valid(stored_term_buf)) then
-- 		M.create_new_terminal(project_path)
-- 	else
-- 		-- Reopen the floating window for the existing terminal buffer
-- 		local width = math.floor(vim.o.columns * 0.8)
-- 		local height = math.floor(vim.o.lines * 0.8)
-- 		local opts = {
-- 			relative = "editor",
-- 			width = width,
-- 			height = height,
-- 			col = math.floor((vim.o.columns - width) / 2),
-- 			row = math.floor((vim.o.lines - height) / 2),
-- 			style = "minimal",
-- 			border = "rounded",
-- 		}
-- 		stored_term_win = vim.api.nvim_open_win(stored_term_buf, true, opts)
--
-- 		-- Reapply the background color if reopening
-- 		local highlight_group = "TerminalHighlight" .. terminal_count
-- 		vim.api.nvim_win_set_option(
-- 			stored_term_win,
-- 			"winhl",
-- 			"NormalFloat:" .. highlight_group .. ",FloatBorder:" .. highlight_group
-- 		)
--
-- 		vim.cmd("startinsert") -- Ensure terminal starts in insert mode
-- 	end
-- end
--
--
------------------------

--local stored_term_win = nil

--local stored_term_buf_name = nil
--tmux send-keys -t WorkSession:NvimTerminal 'ls' C-m
-- Open terminal in a floating window and run the preprogrammed cmd
-- function M.terminal_command_quick_run()
-- 	local term_cmd = "ls"
-- 	local previous_win = vim.api.nvim_get_current_win()
-- 	local previous_mode = vim.api.nvim_get_mode().mode
--
-- 	-- Check if the terminal buffer already exists
-- 	local term_buf = nil
-- 	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
-- 		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == stored_term_buf_name then
-- 			term_buf = buf
-- 			break
-- 		end
-- 	end
--
-- 	-- Reuse the terminal if it exists and the window is valid
-- 	if stored_term_win and vim.api.nvim_win_is_valid(stored_term_win) then
-- 		vim.api.nvim_set_current_win(stored_term_win)
-- 	elseif term_buf then
-- 		-- Create a floating window for the terminal
-- 		local width = math.floor(vim.o.columns * 0.8)
-- 		local height = math.floor(vim.o.lines * 0.8)
-- 		local opts = {
-- 			relative = "editor",
-- 			width = width,
-- 			height = height,
-- 			col = math.floor((vim.o.columns - width) / 2),
-- 			row = math.floor((vim.o.lines - height) / 2),
-- 			style = "minimal",
-- 		}
-- 		stored_term_win = vim.api.nvim_open_win(term_buf, true, opts)
-- 	else
-- 		-- Create a new terminal buffer and floating window
-- 		local width = math.floor(vim.o.columns * 0.8)
-- 		local height = math.floor(vim.o.lines * 0.8)
-- 		local opts = {
-- 			relative = "editor",
-- 			width = width,
-- 			height = height,
-- 			col = math.floor((vim.o.columns - width) / 2),
-- 			row = math.floor((vim.o.lines - height) / 2),
-- 			style = "minimal",
-- 		}
-- 		term_buf = vim.api.nvim_create_buf(false, true)
-- 		stored_term_win = vim.api.nvim_open_win(term_buf, true, opts)
-- 		vim.fn.termopen("/bin/bash")
-- 		stored_term_buf_name = vim.api.nvim_buf_get_name(0)
-- 	end
--
-- 	-- Ensure terminal is in insert mode
-- 	vim.cmd("startinsert")
--
-- 	-- Send the command to the terminal
-- 	if term_buf then
-- 		local job_id = vim.b[term_buf].terminal_job_id
-- 		if job_id then
-- 			vim.api.nvim_chan_send(job_id, "tt-attach-to-NvimTerminal" .. "\n")
-- 			vim.api.nvim_chan_send(job_id, term_cmd .. "\n")
-- 		else
-- 			print("Failed to find terminal job ID for buffer " .. stored_term_buf_name)
-- 		end
-- 	else
-- 		print("Terminal buffer not found or not valid!")
-- 	end
--
-- 	-- Switch back to the previous window
-- 	vim.api.nvim_set_current_win(previous_win)
--
-- 	-- Restore the previous mode (e.g., normal mode)
-- 	if previous_mode:sub(1, 1) ~= "i" then
-- 		vim.cmd("stopinsert")
-- 	end
-- end
--------------------------------------

function M.open_yank_buffer()
	local root_path = require("phxm.properties").root.root_path
	local yank_buffer_file = root_path .. "/.global_yank_buffer"

	-- Check if the file exists
	if vim.fn.filereadable(yank_buffer_file) == 0 then
		vim.notify("Yank buffer file does not exist.", vim.log.levels.WARN)
		return
	end

	-- Check if a buffer named "Yank Buffer" already exists
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local buf_name = vim.api.nvim_buf_get_name(buf)
		if buf_name == "Yank Buffer" and vim.api.nvim_buf_is_loaded(buf) then
			-- Switch to the existing "Yank Buffer"
			vim.api.nvim_set_current_buf(buf)
			vim.notify("Reusing existing Yank Buffer.", vim.log.levels.INFO)
			return
		end
	end

	-- Read the content of the yank buffer file
	local lines = vim.fn.readfile(yank_buffer_file)

	-- Open a new scratch buffer
	vim.cmd("enew")
	local buf = vim.api.nvim_get_current_buf()
	-- Set a unique name for the buffer
	pcall(vim.api.nvim_buf_set_name, buf, "Yank Buffer")
	-- Set buffer options using vim.bo
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	--	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	--	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
	--	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	-- Open the buffer in a floating window
	vim.api.nvim_set_current_win(vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = vim.o.columns - 4,
		height = vim.o.lines - 4,
		row = math.floor((vim.o.lines - vim.o.lines / 2) / 2),
		col = math.floor((vim.o.columns - vim.o.columns / 2) / 2),
		border = "rounded",
	}))

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Highlight between ---YB START--- and ---YB END---
	local highlights = {}
	local start_idx, end_idx = nil, nil
	for i, line in ipairs(lines) do
		if line:find("---YB START---") or line:find("---DB START---") then
			start_idx = i
		elseif line:find("---YB END---") or line:find("---DB END---") then
			end_idx = i
			if start_idx and end_idx then
				table.insert(highlights, { start_idx, end_idx })
				start_idx, end_idx = nil, nil
			end
		end
	end

	-- Function to highlight and move the viewport
	local function highlight_and_center(start_line, end_line)
		vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
		for i = start_line, end_line - 1 do
			vim.api.nvim_buf_add_highlight(buf, -1, "Visual", i - 1, 0, -1)
		end
		vim.fn.cursor(start_line, 1) -- Move cursor to the start of the block
		vim.cmd("normal! zz") -- Center the viewport on the cursor
	end

	-- Initially highlight the first block
	local current_highlight = 1
	if #highlights > 0 then
		highlight_and_center(highlights[current_highlight][1], highlights[current_highlight][2])
	end

	-- Default to the last block on startup
	local current_highlight = #highlights
	if #highlights > 0 then
		highlight_and_center(highlights[current_highlight][1], highlights[current_highlight][2])
	end

	-- Define movement commands
	local function move_to_next_block()
		if current_highlight < #highlights then
			current_highlight = current_highlight + 1
			highlight_and_center(highlights[current_highlight][1], highlights[current_highlight][2])
		else
			vim.notify("No more blocks below.", vim.log.levels.INFO)
		end
	end

	local function move_to_prev_block()
		if current_highlight > 1 then
			current_highlight = current_highlight - 1
			highlight_and_center(highlights[current_highlight][1], highlights[current_highlight][2])
		else
			vim.notify("No more blocks above.", vim.log.levels.INFO)
		end
	end

	-- Yank current block using the default 'y' key
	local function yank_current_block()
		if #highlights == 0 then
			vim.notify("No blocks to yank.", vim.log.levels.WARN)
			return
		end

		local start_line, end_line = highlights[current_highlight][1], highlights[current_highlight][2]

		-- Adjust start_line to skip the marker itself
		local yank_start = start_line + 1
		local yank_end = end_line - 1

		-- Ensure there's content between the markers
		if yank_start > yank_end then
			vim.notify("No content to yank between markers.", vim.log.levels.WARN)
			return
		end

		-- Move cursor to the start of the block
		vim.api.nvim_win_set_cursor(0, { yank_start, 0 })
		-- Visually select lines between markers, skipping the marker lines
		vim.cmd("normal! V")
		vim.api.nvim_win_set_cursor(0, { yank_end, 0 })
		-- Yank the visually selected lines
		vim.cmd("normal! y")

		-- Get the yanked content from the default register
		local yanked_content = vim.fn.getreg('"')

		-- Trim leading and trailing whitespace
		local trimmed_content = yanked_content:gsub("^%s+", ""):gsub("%s+$", "")

		-- Set the trimmed content back to the default register
		vim.fn.setreg('"', trimmed_content)

		vim.notify("Content between markers yanked and trimmed.")
	end
	-- Map keys
	vim.keymap.set("n", "j", move_to_next_block, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "k", move_to_prev_block, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "y", yank_current_block, { buffer = buf, noremap = true, silent = true })

	vim.api.nvim_set_hl(0, "YBMarker", { fg = "#111111", bg = "#000000" })

	vim.keymap.set("n", "<Esc>", function()
		local buf = vim.api.nvim_get_current_buf()
		vim.cmd("bdelete! " .. buf)
	end, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "q", function()
		local buf = vim.api.nvim_get_current_buf()
		vim.cmd("bdelete! " .. buf)
	end, { buffer = buf, noremap = true, silent = true })

	-- Highlight markers in the buffer
	-- Define the highlight group

	-- Loop through the buffer and highlight markers
	-- Wont work as changing hl selectin up down will reset hl
	-- for line_num = 0, vim.api.nvim_buf_line_count(buf) - 1 do
	-- 	local line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]
	-- 	if line then
	-- 		-- Highlight START markers
	-- 		local start_col = line:find("---YB START---")
	-- 		if start_col then
	-- 			vim.api.nvim_buf_add_highlight(buf, -1, "YBMarker", line_num, start_col - 1, start_col + 12)
	-- 		end

	-- 		-- Highlight END markers
	-- 		local end_col = line:find("---YB END---")
	-- 		if end_col then
	-- 			vim.api.nvim_buf_add_highlight(buf, -1, "YBMarker", line_num, end_col - 1, end_col + 10)
	-- 		end
	-- 	end
	-- end
end

-- Function to append yanked content to the buffer file
function M.append_to_yank_file()
	local yank_buffer_file = require("phxm.properties").root.root_path .. "/.global_yank_buffer"
	-- Get the yanked content from the unnamed register
	local yanked_content = vim.fn.getreg('"')

	-- Trim leading and trailing whitespace
	local trimmed_content = yanked_content:gsub("^%s+", ""):gsub("%s+$", "")

	if trimmed_content == "" then
		-- Skip if there's nothing to append
		return
	end

	-- Format the content with markers
	local content_with_markers = {
		"---YB START---",
		trimmed_content,
		"---YB END---",
	}

	-- Append to the yank buffer file
	local file = io.open(yank_buffer_file, "a")
	if file then
		for _, line in ipairs(content_with_markers) do
			file:write(line .. "\n")
		end
		file:close()
	else
		vim.notify("Failed to write to yank buffer file.", vim.log.levels.ERROR)
	end
end
--------------------------------------

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
	local sanitized_file = sanitize_for_hl_group(dir .. "_file")

	-- Generate colors based on dir and file

	local dir_color = keypoint.string_to_color(dir)
	local dir_color_original = dir_color
	dir_color = keypoint.adjust_color(dir_color, 60, 80)
	local file_color = keypoint.string_to_color(file)
	file_color = keypoint.adjust_color(dir_color_original, 40, 90)

	-- Create dynamic highlight groups
	local dir_hl = "DirHlGroup_" .. sanitized_dir
	local file_hl = "FileHlGroup_" .. sanitized_file

	-- Define the highlight groups
	vim.api.nvim_set_hl(0, dir_hl, { fg = dir_color, bg = "#300303" })
	vim.api.nvim_set_hl(0, file_hl, { fg = file_color, bg = "#260202" })

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

	-- Close the scratch buffer first
	--vim.cmd("bdelete " .. buf)
	vim.api.nvim_buf_delete(buf, { force = true })

	-- Open the file in a new buffer
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))
end

function M.generate_dir_tree(base_dir)
	-- Run the `find` command to get all absolute paths
	local handle = io.popen("find " .. vim.fn.shellescape(base_dir) .. " -print")
	if not handle then
		vim.notify("Failed to run the find command.", vim.log.levels.ERROR)
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	-- Split the result into lines
	local absolute_paths = vim.split(result, "\n", { trimempty = true })
	return absolute_paths
end

function M.open_dir_tree()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		vim.notify("No file is open in the current buffer.", vim.log.levels.WARN)
		return
	end

	-- Prompt for the number of steps up
	local user_input = vim.fn.input("Enter a number (0 for current dir, 1 for parent, etc.): ", "0")
	local steps_up = tonumber(user_input)

	if not steps_up or steps_up < 0 then
		vim.notify("Invalid input. Please enter a non-negative number.", vim.log.levels.ERROR)
		return
	end

	-- Determine the base directory
	local base_dir = vim.fn.fnamemodify(current_file, string.rep(":h", steps_up + 1))
	if base_dir == "" then
		vim.notify("Could not determine the directory.", vim.log.levels.ERROR)
		return
	end

	-- Generate absolute paths for the directory tree
	local absolute_paths = M.generate_dir_tree(base_dir)
	if not absolute_paths or #absolute_paths == 0 then
		vim.notify("No files found in the specified directory.", vim.log.levels.INFO)
		return
	end

	-- Create and configure a scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, absolute_paths)

	-- Apply highlight groups to each line
	for i, path in ipairs(absolute_paths) do
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
	end, { buffer = buf, noremap = true, silent = true })
	-- Bind the `q` key to close the buffer
	vim.keymap.set("n", "q", function()
		local buf = vim.api.nvim_get_current_buf()
		vim.cmd("bdelete! " .. buf)
	end, { buffer = buf, noremap = true, silent = true })
end

-----------------------------

--
----
-----
---

function M.find_all_functions_in_files2(paths)
	local ts = vim.treesitter
	local ts_query = vim.treesitter.query
	local uv = vim.loop

	local function read_file(file_path)
		local fd = uv.fs_open(file_path, "r", 438)
		if not fd then
			return nil
		end
		local stat = uv.fs_fstat(fd)
		if not stat then
			return nil
		end
		local data = uv.fs_read(fd, stat.size, 0)
		uv.fs_close(fd)
		return data
	end

	local function scan_directory(dir, files)
		files = files or {}

		-- Open directory
		local scandir = uv.fs_scandir(dir)
		if not scandir then
			return files -- Return collected files if scandir fails
		end

		while true do
			local entry_name, entry_type = uv.fs_scandir_next(scandir)

			-- Handle the case where `entry_name` is nil
			if not entry_name then
				break
			end

			-- If `entry_type` is nil, we need to query the file type manually
			if not entry_type then
				local stat = uv.fs_stat(dir .. "/" .. entry_name)
				if stat then
					entry_type = stat.type
				end
			end

			local path = dir .. "/" .. entry_name

			if entry_type == "file" then
				-- Collect files
				table.insert(files, path)
			elseif entry_type == "directory" then
				-- Recursively scan subdirectories
				scan_directory(path, files)
			end
		end

		return files
	end

	local function find_function_in_buffer(buffer)
		-- NOTE: Be careful to reattach the parser for the buffer to be scanned
		-- what we send here is a buffer of with the content, and it was not attached to any parser
		-- it was created on the fly as temporary buffer
		-- thus in case of javascript, bash, do so,
		-- but lua is already attached to the parser
		-- if lua fails in the future, check to attach the parser explicitly here
		--
		-- FIX: Our treesitter capture codes are duplicated and exist in other place (may differ in bash versoin)
		-- FIX: Bash verson has captures not relevant
		local parser = vim.treesitter.get_parser(buffer, "lua")
		if not parser then
			vim.notify("No parser available for the buffer", vim.log.levels.ERROR)
			return
		end

		local tree = parser:parse()[1]
		local root = tree:root()

		local filetype = vim.bo.filetype

		local query_types = {
			lua = function()
				-- Action for Lua
				return vim.treesitter.query.parse(
					"lua",
					--					[[
					--  (function_declaration
					--    name: (identifier) @func_name
					--    )
					--  (function_declaration
					--    name: (dot_index_expression
					--      field: (identifier) @func_name)
					--    )
					--]]
					[[
  (function_declaration
    name: (identifier) @func_name
    )
  (function_declaration
    name: (dot_index_expression
      table: (identifier) @table_name
      field: (identifier) @func_name)
    )
      (field
      name: (identifier) @table_field_name
      value: (function_definition))
]]
				)
			end,
			php = function()
				return vim.treesitter.query.parse(
					"php",
					[[
        ; Match standalone function declarations
        (function_definition
            name: (name) @function_name)

        ; Match method declarations inside a class
        (method_declaration
            name: (name) @method_name)

        ; Match class declarations
        (class_declaration
            name: (name) @class_name)
]]
				)
			end,
			bash = function()
				return vim.treesitter.query.parse(
					"bash",
					[[
    ; Match function definitions in Bash
    (function_definition
        name: (word) @function_name)

    ]]
				)
			end,
			javascript = function()
				return vim.treesitter.query.parse(
					"javascript",
					[[
    ; Match regular function declarations
    (function_declaration
        name: (identifier) @function_name)

    ; Match function expressions assigned to variables
    (variable_declarator
        name: (identifier) @variable_name
        value: [(function_expression) (arrow_function)])

    ; Match class method definitions
    (method_definition
        name: (property_identifier) @method_name)

    ; Match object literal methods
    (pair
        key: (property_identifier) @object_key
        value: [(function_expression) (arrow_function)])
]]
				)
			end,
			default = function()
				-- Default action
				print("Find all functions: Unknown filetype!")
				return nil
			end,
		}
		local query = query_types[filetype]() or query_types.default()

		local results = {}
		if filetype == "lua" then
			-- Iterate over matches
			for _, match, _ in query:iter_matches(root, buffer, root:start(), root:end_(), nil) do
				for id, node in pairs(match) do
					if query.captures[id] == "func_name" then
						local range = node:range()
						table.insert(results, { range = range, content = vim.treesitter.get_node_text(node, buffer) })
					end
				end
			end
		elseif filetype == "php" then
		elseif filetype == "bash" then
			------------------------------------------
			------------------------------------------
			-- Set filetype explicitly for the buffer
			vim.bo[buffer].filetype = "bash"
			vim.treesitter.start(buffer, "bash") -- Attach Tree-sitter explicitly

			-- Re-parse after starting
			local parser = vim.treesitter.get_parser(buffer, "bash")
			if not parser then
				vim.notify("Failed to attach Tree-sitter parser for Bash", vim.log.levels.ERROR)
				return {}
			end
			local tree = parser:parse()[1]
			if not tree then
				vim.notify("Failed to parse buffer", vim.log.levels.ERROR)
				return {}
			end

			local root = tree:root()

			for _, match, _ in query:iter_matches(root, buffer) do
				local func_name = ""
				local start_row = nil

				for id, node in pairs(match) do
					local capture_name = query.captures[id]
					if capture_name == "function_name" then
						func_name = vim.treesitter.get_node_text(node, buffer)
						start_row = node:range()
					end
				end
				if func_name ~= "" and start_row then
					--table.insert(results, { name = func_name, line = start_row + 1 })
					table.insert(results, { range = start_row, content = func_name })
				end
			end
			------------------------------------------
			------------------------------------------
		elseif filetype == "javascript" then
			-- Set filetype explicitly for the buffer
			vim.bo[buffer].filetype = "javascript"
			vim.treesitter.start(buffer, "javascript") -- Attach Tree-sitter explicitly

			-- Re-parse after starting
			local parser = vim.treesitter.get_parser(buffer, "javascript")
			if not parser then
				vim.notify("Failed to attach Tree-sitter parser for Javascript", vim.log.levels.ERROR)
				return {}
			end
			local tree = parser:parse()[1]
			if not tree then
				vim.notify("Failed to parse buffer", vim.log.levels.ERROR)
				return {}
			end

			local root = tree:root()

			--for _, match, _ in query:iter_matches(root, buffer, root:start(), root:end_(), nil) do
			for _, match, _ in query:iter_matches(root, buffer) do
				local func_name = ""
				local start_row = nil
				for id, node in pairs(match) do
					local capture_name = query.captures[id]
					if capture_name == "function_name" then
						-- Regular function declaration
						func_name = vim.treesitter.get_node_text(node, buffer)
						start_row = node:range()
					elseif capture_name == "variable_name" then
						-- Function assigned to a variable
						func_name = vim.treesitter.get_node_text(node, buffer)
						start_row = node:range()
					elseif capture_name == "method_name" then
						-- Class method
						func_name = vim.treesitter.get_node_text(node, buffer)
						start_row = node:range()
					elseif capture_name == "object_key" then
						-- Object literal method
						func_name = vim.treesitter.get_node_text(node, buffer)
						start_row = node:range()
					end
				end

				if func_name ~= "" and start_row then
					table.insert(results, { content = func_name, range = start_row }) -- Store function name and line
				end
			end
		else
			-- Default action
			print("Find all functions: Unknown filetype!")
			return nil
		end
		return results
	end

	local results = {}

	-- Process each path
	for _, search_dir in ipairs(paths) do
		local files = scan_directory(search_dir)
		for _, file in ipairs(files) do
			local content = read_file(file)
			if content then
				local buffer = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(content, "\n"))
				local matches = find_function_in_buffer(buffer)
				if matches and #matches > 0 then
					results[file] = matches
				end
				vim.api.nvim_buf_delete(buffer, { force = true })
			end
		end
	end
	return results
end

local function entry_maker_for_functions(entry)
	local entry_display = require("telescope.pickers.entry_display")
	local keypoint = require("keypoint") -- Assuming you have this module for color generation

	-- Utility to sanitize strings for highlight group names
	local function sanitize_for_hl_group(name)
		return name:gsub("%W", "_") -- Replace non-alphanumeric characters with underscores
	end

	-- Generate path, line number, and function name
	local path = entry.filename
	local line = tostring(entry.lnum)
	local func_name = entry.text

	local function truncate_path(path, max_length)
		if #path > max_length then
			return "..." .. path:sub(-max_length + 3) -- Add "..." and keep the last max_length - 3 characters
		end
		return path
	end
	path = truncate_path(path, 40)

	-- Separate directory and file name

	-- Sanitize directory and file names for highlight group safety
	local sanitized_path = sanitize_for_hl_group(path)
	local sanitized_func = sanitize_for_hl_group(func_name)

	-- Generate colors dynamically
	local path_color = keypoint.string_to_color(path)
	-----------------------------------------------------60 before
	local func_color = keypoint.adjust_color(path_color, 20, 90)
	path_color = keypoint.adjust_color(path_color, 60, 80)
	local path_hl = "DirHlGroup_" .. sanitized_path
	-- Ensure unique, 2 files may have same func name...
	local func_hl = "DirHlGroup_" .. sanitized_path .. sanitized_func

	-- Define highlight groups with generated colors
	vim.api.nvim_set_hl(0, path_hl, { fg = path_color })
	vim.api.nvim_set_hl(0, func_hl, { fg = func_color })

	return {
		value = entry,
		ordinal = path .. " " .. line .. " " .. func_name, -- Sort and filter by all fields
		display = function()
			-- Create the displayer for Telescope
			local displayer = entry_display.create({
				separator = " ",
				items = {
					{ width = 40, hl = path_hl }, -- Directory column
					{ width = 10 }, -- Line number column
					{ remaining = true }, -- Function name column
				},
			})

			return displayer({
				{ path, path_hl },
				{ line },
				{ func_name, func_hl },
			})
		end,
		filename = entry.filename,
		lnum = entry.lnum,
		text = entry.text,
	}
end

local function get_current_word()
	return vim.fn.expand("<cword>")
end

function M.telescope_filter_function_definition_under_cursor()
	-- Example usage
	local word = get_current_word()
	M.telescope_filter_function_definitions(word)
end
-- Example usage function
function M.telescope_filter_function_definitions(pre_entered_word)
	pre_entered_word = pre_entered_word or ""

	-------------- GET ALL INCLUDED DIRECTORIES -------------
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'include' file
	local include_file_path = project_dir .. "/include"

	-- Check if the 'include' file exists
	if vim.fn.filereadable(include_file_path) == 0 then
		vim.notify("No include file found", vim.log.levels.WARN)
		return
	end

	-- Read the contents of the 'include' file
	local include_file_content = vim.fn.readfile(include_file_path)

	-- Check if the file is empty
	if #include_file_content == 0 then
		vim.notify("No file paths found in include file", vim.log.levels.INFO)
		return
	end
	local results = M.find_all_functions_in_files2(include_file_content)
	-----------------
	-- The all_results table now contains a flat list of all matches

	--local results = M.find_all_functions_in_files("/home/f/.local/share/nvim/lazy/phxm.nvim")

	-- Prepare entries for Telescope
	local telescope_results = {}
	for file, matches in pairs(results) do
		for _, match in ipairs(matches) do
			local line = match.range + 1
			local entry = {
				display = file .. " [" .. line .. "]: " .. match.content,
				filename = file,
				lnum = line,
				text = match.content,
			}
			table.insert(telescope_results, entry)
		end
	end
	local user_input = ""
	-- Use Telescope to show results
	require("telescope.pickers")
		.new({}, {
			prompt_title = "Function Calls",
			finder = require("telescope.finders").new_table({
				results = telescope_results,
				entry_maker = entry_maker_for_functions,
				--				entry_maker = function(entry)
				--					return {
				--						value = entry,
				--						display = entry.display,
				--						ordinal = entry.display,
				--						filename = entry.filename,
				--						lnum = entry.lnum,
				--					}
				--				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			previewer = require("telescope.previewers").new_buffer_previewer({
				define_preview = function(self, entry, status)
					local filename = entry.filename
					if vim.fn.filereadable(filename) == 1 then
						vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "lua")
						vim.fn.jobstart({ "cat", filename }, {
							stdout_buffered = true,
							on_stdout = function(_, data)
								vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, data)
								vim.api.nvim_buf_set_option(self.state.bufnr, "modifiable", false)
								vim.api.nvim_buf_add_highlight(
									self.state.bufnr,
									-1,
									"TelescopeSelection",
									entry.lnum - 1,
									0,
									-1
								)
								vim.api.nvim_win_set_cursor(self.state.winid, { entry.lnum, 0 })
							end,
						})
					else
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "File not found" })
					end
				end,
			}),
			on_input_filter_cb = function(input)
				user_input = input
				return input -- You must return the input for Telescope to function correctly
			end,

			attach_mappings = function(_, map)
				map("i", "<CR>", function(prompt_bufnr)
					local entry = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
					require("telescope.actions").close(prompt_bufnr)
					require("phxm.buffer").update_history(
						entry.value.filename,
						entry.value.lnum,
						"function> " .. user_input .. " = " .. entry.value.text .. "()"
					)

					-- Open file and go to line
					vim.cmd("edit " .. entry.value.filename)
					vim.api.nvim_win_set_cursor(0, { entry.value.lnum, 0 })
				end)
				return true
			end,
			default_text = pre_entered_word,
		})
		:find()
end
---------------------------------

local function entry_maker(entry)
	local entry_display = require("telescope.pickers.entry_display")
	local keypoint = require("keypoint")

	-- Utility to sanitize strings for highlight group names
	local function sanitize_for_hl_group(name)
		return name:gsub("%W", "_") -- Replace non-alphanumeric characters with underscores
	end

	local path = entry
	local dir, file = path:match("^(.*)/([^/]+)$")
	dir = dir or ""
	file = file or path

	-- Sanitize dir and file names for highlight group safety
	local sanitized_dir = sanitize_for_hl_group(dir)
	local sanitized_file = sanitize_for_hl_group(file)

	-- Create dynamic highlight groups for dir and file
	local dir_color = keypoint.string_to_color(dir)
	dir_color = keypoint.adjust_color(dir_color, 60, 80)
	local file_color = keypoint.string_to_color(file)
	file_color = keypoint.adjust_color(file_color, 60, 90)
	local dir_hl = "DirHlGroup_" .. sanitized_dir
	local file_hl = "FileHlGroup_" .. sanitized_file

	-- Define highlight groups with dynamically generated colors
	vim.api.nvim_set_hl(0, dir_hl, { fg = dir_color })
	vim.api.nvim_set_hl(0, file_hl, { fg = file_color })

	return {
		value = entry,
		ordinal = entry,
		display = function()
			-- Get the Telescope results window width dynamically
			local win_id = vim.api.nvim_get_current_win()
			local win_width = vim.api.nvim_win_get_width(win_id)

			-- Adjust directory and file widths based on the window width
			local dir_width = math.floor(win_width - 25) -- 50% for directory, adjust as needed
			local file_width = win_width - dir_width - 4 -- Remaining width for file name with padding

			-- Truncate dir if it exceeds dir_width, adding "..." at the start
			if #dir > dir_width then
				dir = "..." .. dir:sub(-dir_width + 3) -- Retain the end part of the dir string
			end

			local displayer = entry_display.create({
				separator = " ",
				items = {
					{ width = dir_width, align = "right" }, -- Right align directory column
					{ width = file_width },
				},
			})

			return displayer({
				{ dir, dir_hl },
				{ file, file_hl },
			})
		end,
	}
end

-- Function to open a buffer and display project information
function M.display_project_info()
	local project_base_path = prop.root.root_path
	local project_dir = prop.current_project.project_path
	local key_file = project_dir .. "/.key"

	assigned_key = "Does not exist"
	-- Initialize content variables for each file

	-- Check if the files exist and read their contents
	if vim.fn.filereadable(key_file) == 1 then
		assigned_key = table.concat(vim.fn.readfile(key_file), "\n")
	end
	-- Prepare project information
	local lines = {
		"Root Information:",
		"---------------------",
		"Project Base Directory    : " .. prop.root.root_path,
		"Current Project Directory : " .. (prop.root.selected_project or "Not set"),
		"",
		"Project Information:",
		"---------------------",
		"Key Assigned              : " .. assigned_key,
		"Project Name              : " .. (prop.current_project.name or "Unknown"),
		"Session File              : "
			.. (
				(prop.current_project.project_path and (prop.current_project.project_path .. "/.session.vim"))
				or "Not set"
			),
		"Current Working Directory : " .. vim.fn.getcwd(),
		"",
		"Include File Content:",
		"---------------------",
	}

	-- Read the content of the "include" file and append to the lines table
	local include_lines = require("phxm.properties").list_included_paths() or { "No include file found." }
	vim.list_extend(lines, include_lines)

	-- Concatenate the lines into a single string
	local info_string = table.concat(lines, "\n")

	-- Output the information below the status line
	vim.api.nvim_echo({ { info_string, "Normal" } }, true, {})
end

-- Reads the content of the include file for the current project
function M.read_include_file()
	if prop.current_project and phxm.current_project.files and phxm.current_project.files.include then
		local include_path = prop.current_project.files.include
		if vim.fn.filereadable(include_path) == 1 then
			return vim.fn.readfile(include_path)
		end
	end
	return nil
end

function M.list_included_dirs()
	-- Ensure `prop.current_project.project_path` is set

	if not prop.current_project.project_path then
		vim.notify("Error: `prop.current_project.project_path` is not set.", vim.log.levels.ERROR)
		return
	end

	-- Define the path to the 'include' and '.named_buffers' files
	local include_file_path = prop.current_project.project_path .. "/include"
	local named_buffers_file_path = prop.current_project.project_path .. "/.named_buffers"

	-- Check if the 'include' file exists
	if vim.fn.filereadable(include_file_path) == 0 then
		vim.notify("No include file found", vim.log.levels.WARN)
		return
	end

	-- Read the contents of the 'include' file
	local include_file_content = vim.fn.readfile(include_file_path)

	if #include_file_content == 0 then
		vim.notify("No directories found in include file", vim.log.levels.INFO)
		return
	end

	-- Read the .named_buffers file if it exists
	local named_buffers = {}
	if vim.fn.filereadable(named_buffers_file_path) == 1 then
		local file_content = vim.fn.readfile(named_buffers_file_path)
		named_buffers = vim.json.decode(table.concat(file_content, "\n")) or {}
	end

	-- Prepare the content to be displayed in the list
	local lines = { "Included Directories:", "--------------------" }

	-- Iterate over each path in the include file
	for _, file_path in ipairs(include_file_content) do
		local buffer_name = nil

		-- Check if the current path matches any entry in .named_buffers
		for _, entry in ipairs(named_buffers) do
			if entry.path == file_path then
				buffer_name = entry.name -- Get the corresponding name
				break
			end
		end

		-- If no name is found, set buffer_name to "(No Name)"
		buffer_name = buffer_name or "(No Name)"

		-- Add the name and path to the output list, separated by a colon
		table.insert(lines, buffer_name .. " : " .. file_path)
	end

	table.insert(lines, "--------------------")

	-- Display the list using `nvim_echo` to show it in the command area
	vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})

	-- Wait for user input (press enter to continue)
end

local function get_all_files_in_dirs(dirs)
	local paths = {}
	for _, dir in ipairs(dirs) do
		-- Use vim.loop to iterate over directory contents
		local handle = vim.loop.fs_scandir(dir)
		while handle do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end
			local full_path = dir .. "/" .. name
			if type == "file" then
				table.insert(paths, full_path)
			elseif type == "directory" then
				-- Recursively process subdirectories
				vim.list_extend(paths, get_all_files_in_dirs({ full_path }))
			end
		end
	end
	return paths
end

local function launch_telescope_with_files(file_list)
	local user_input
	require("telescope.builtin").find_files({

		prompt_title = "Find in Included Directories (cached list)",
		finder = require("telescope.finders").new_table({
			results = file_list, -- Use your file list here
			entry_maker = entry_maker,
		}),
		sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
		entry_maker = entry_maker,
		-------------------
		on_input_filter_cb = function(input)
			user_input = input
			return input -- You must return the input for Telescope to function correctly
		end,
		attach_mappings = function(_, map)
			map("i", "<CR>", function(prompt_bufnr)
				-- Get user input and selection
				local actions = require("telescope.actions")
				-- Wont work to get current line
				--user_input = require("telescope.actions.state").get_current_line()
				--selected_result = require("telescope.actions.state").get_selected_entry()
				-- Get the selected entry
				local action_state = require("telescope.actions.state")
				local selected_entry = action_state.get_selected_entry()
				-- Close Telescope
				actions.close(prompt_bufnr)
				-- Open the selected file in Neovim
				if selected_entry and selected_entry.value then
					vim.cmd("edit " .. vim.fn.fnameescape(selected_entry.value))
					require("phxm.buffer").record_buffer_change()

					local cursor_position = vim.api.nvim_win_get_cursor(0)
					local line_number = cursor_position[1]
					require("phxm.buffer").update_history(selected_entry.value, line_number, "file> " .. user_input)
				end
			end)
			return true
		end,

		------------------

		layout_config = {
			--width = 0.8, -- Set the width of the result window (e.g., 60% of the current window)
			--preview_width = 0.3,
		},
	})
end
--Original
--
--
--local function launch_telescope_with_files(file_list)
--	require("telescope.builtin").find_files({
--		prompt_title = "Find in Included Directories (cached list)",
--		finder = require("telescope.finders").new_table({
--			results = file_list, -- Use your file list here
--			entry_maker = entry_maker,
--		}),
--		sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
--		entry_maker = entry_maker,
--		layout_config = {
--			--width = 0.8, -- Set the width of the result window (e.g., 60% of the current window)
--			--preview_width = 0.3,
--		},
--	})
--end
--
---- Serach-dirs can be list of dirs or paths to files
--local function launch_telescope(search_dirs)
--	require("telescope.builtin").find_files({
--		search_dirs = search_dirs,
--		prompt_title = "Find in Included Directories",
--		sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
--		entry_maker = entry_maker,
--		layout_config = {
--			--width = 0.8, -- Set the width of the result window (e.g., 60% of the current window)
--			--preview_width = 0.3,
--		},
--	})
--end
-- Serach-dirs can be list of dirs or paths to files
local function launch_telescope(search_dirs, remember)
	remember = remember or false
	local project_dir = prop.current_project.project_path
	local remembered_search = ""
	if remember then
		local file = io.open(project_dir .. "/.search_in_project_include_remembered_search", "r")

		if file then
			remembered_search = file:read("*all")
			file:close()
		end
	end
	local user_input
	require("telescope.builtin").find_files({
		search_dirs = search_dirs,
		prompt_title = "Find in Included Directories",
		sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
		entry_maker = entry_maker,

		-------------------
		on_input_filter_cb = function(input)
			user_input = input
			return input -- You must return the input for Telescope to function correctly
		end,
		attach_mappings = function(_, map)
			map("i", "<CR>", function(prompt_bufnr)
				-- Get user input and selection
				local actions = require("telescope.actions")
				-- Wont work to get current line
				--user_input = require("telescope.actions.state").get_current_line()
				--selected_result = require("telescope.actions.state").get_selected_entry()
				-- Get the selected entry
				local action_state = require("telescope.actions.state")
				local selected_entry = action_state.get_selected_entry()
				-- Close Telescope
				actions.close(prompt_bufnr)
				-- Open the selected file in Neovim
				if selected_entry and selected_entry.value then
					vim.cmd("edit " .. vim.fn.fnameescape(selected_entry.value))
					require("phxm.buffer").record_buffer_change()

					local cursor_position = vim.api.nvim_win_get_cursor(0)
					local line_number = cursor_position[1]
					if selected_entry and selected_entry.value then
						vim.cmd("edit " .. vim.fn.fnameescape(selected_entry.value))
						local cursor_position = vim.api.nvim_win_get_cursor(0)
						local line_number = cursor_position[1]
						require("phxm.buffer").update_history(selected_entry.value, line_number, "file> " .. user_input)
						if user_input then
							local file = io.open(project_dir .. "/.search_in_project_include_remembered_search", "w")
							if file then
								file:write(user_input)
								file:close()
							end
						end
					end
				end
			end)
			return true
		end,

		default_text = remembered_search,
		------------------

		layout_config = {
			--width = 0.8, -- Set the width of the result window (e.g., 60% of the current window)
			--preview_width = 0.3,
		},
	})
end
function M.search_in_project_include_remember_last_search()
	-- Example usage
	M.search_in_project_include(true)
end

--sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
function M.search_in_project_include(remember)
	remember = remember or false

	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'include' file
	local include_file_path = project_dir .. "/include"

	-- Check if the 'include' file exists
	if vim.fn.filereadable(include_file_path) == 0 then
		vim.notify("No include file found", vim.log.levels.WARN)
		return
	end

	-- Read the contents of the 'include' file
	local include_file_content = vim.fn.readfile(include_file_path)

	-- Check if the file is empty
	if #include_file_content == 0 then
		vim.notify("No file paths found in include file", vim.log.levels.INFO)
		return
	end

	-------------------- DECIDE IF TO USE CACHE OR NOT ---------------------
	-- Check if the project has a .use_telescope_cache file
	-- If it does, use the cache to speed up the search
	local project_path = require("phxm.properties").current_project.project_path
	local use_cache_flag_file = project_path .. "/.use_telescope_cache"
	local cache_file = project_path .. "/.telescope_find_file_cache"
	local search_dirs = {}

	-- Check if we are using the cache
	local cache_flag = io.open(use_cache_flag_file, "r")
	if cache_flag then
		io.close(cache_flag) -- Close the file handle

		-- Check if the cache file exists
		local cache_handle = io.open(cache_file, "r")
		if cache_handle then
			log("Using cache")
			local function get_filename(path)
				return path:match("^.+/(.+)$")
			end
			-- Load cache contents
			for line in cache_handle:lines() do
				table.insert(search_dirs, line)
				--log("line: " .. get_filename(line))
			end
			io.close(cache_handle)
			launch_telescope_with_files(search_dirs)
		else
			log("build cache")
			-- Notify the user immediately
			vim.notify("Building Telescope file cache...", vim.log.levels.INFO)

			-- Use vim.defer_fn to delay the heavy operation
			vim.defer_fn(function()
				-- Generate new cache and save it
				search_dirs = get_all_files_in_dirs(include_file_content)
				vim.notify("Done Building Telescope file cache...", vim.log.levels.INFO)

				-- Save the new cache
				local save_cache = io.open(cache_file, "w")
				if save_cache then
					for _, path in ipairs(search_dirs) do
						save_cache:write(path .. "\n")
					end
					save_cache:close()
				end
				--	launch_telescope(search_dirs)
				launch_telescope_with_files(search_dirs, remember)
			end, 1) -- 1ms delay (just enough for UI to process the notification)
		end
	else
		log("No cache file no Using cache")

		-- Default behavior if caching is not enabled
		for _, file_path in ipairs(include_file_content) do
			table.insert(search_dirs, file_path)
		end
		launch_telescope(search_dirs, remember)
	end
	----------------------------------

	-- Prepare the table of file paths for Telescope's search_dirs

	-- Call Telescope with fzf fuzzy matching
	--	require("telescope.builtin").find_files({
	--		search_dirs = search_dirs, -- Use the table of file paths as search directories
	--		prompt_title = "Find in Included Directories", -- Custom prompt title
	--		sorter = require("telescope").extensions.fzf.native_fzf_sorter(), -- Use fzf fuzzy sorting
	--	})

	--	--This is the version used that works
	--	require("telescope.builtin").find_files({
	--		search_dirs = search_dirs,
	--		prompt_title = "Find in Included Directories",
	--		sorter = require("telescope").extensions.fzf.native_fzf_sorter(),
	--		entry_maker = entry_maker,
	--		layout_config = {
	--			--width = 0.8, -- Set the width of the result window (e.g., 60% of the current window)
	--			--preview_width = 0.3,
	--		},
	--	})
end

function M.todo_open_list()
	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'todo' file
	local todo_file_path = project_dir .. "/TODO.md"

	-- Check if the 'todo' file exists
	if vim.fn.filereadable(todo_file_path) == 0 then
		-- If it doesn't exist, create the file
		vim.fn.writefile({}, todo_file_path)
		vim.notify("Created new todo file at: " .. todo_file_path, vim.log.levels.INFO)
	end

	-- Open the 'todo' file in a new buffer
	vim.cmd("edit " .. vim.fn.fnameescape(todo_file_path))

	-- Function to toggle checkbox, reorder tasks, and manage completion dates
	local function toggle_checkbox()
		local current_line_num = vim.fn.line(".")
		local line = vim.api.nvim_get_current_line()

		-- Toggle between `[ ]` and `[x]`
		if line:find("%[ %]") then
			-- Mark as completed and add date
			local date = os.date("%Y-%m-%d")
			line = line:gsub("%[ %]", "[x]", 1) .. " [completed::" .. date .. "]"
		elseif line:find("%[x%]") then
			-- Mark as incomplete and remove the completion date
			line = line:gsub("%[x%]", "[ ]", 1):gsub("%s%[completed::%d%d%d%d%-%d%d%-%d%d%]", "")
		else
			vim.notify("No checkbox found on this line", vim.log.levels.WARN)
			return
		end

		-- Update the line with the toggled checkbox and (if applicable) completion date
		vim.api.nvim_set_current_line(line)

		-- Remove the current line from its position
		vim.api.nvim_buf_set_lines(0, current_line_num - 1, current_line_num, false, {})

		-- Move the line to the top if unchecked, or bottom if checked
		if line:find("%[ %]") then
			-- Unchecked: insert at the top
			vim.api.nvim_buf_set_lines(0, 0, 0, false, { line })
		else
			-- Checked: insert at the bottom
			local last_line = vim.api.nvim_buf_line_count(0)
			vim.api.nvim_buf_set_lines(0, last_line, last_line, false, { line })
		end
	end

	-- Function to toggle `-` within `[ ]` or `[x]` and manage cancellation dates
	local function toggle_dash_within_brackets()
		local current_line_num = vim.fn.line(".")
		local line = vim.api.nvim_get_current_line()

		-- Toggle between `[ ]` and `[x]`
		if line:find("%[ %]") then
			-- Mark as completed and add date
			local date = os.date("%Y-%m-%d")
			line = line:gsub("%[ %]", "[-]", 1) .. " [canceled::" .. date .. "]"
		elseif line:find("%[x%]") then
			-- Mark as incomplete and remove the completion date
			line = line:gsub("%[x%]", "[ ]", 1):gsub("%s%[completed::%d%d%d%d%-%d%d%-%d%d%]", "")
		else
			vim.notify("No checkbox found on this line", vim.log.levels.WARN)
			return
		end

		-- Update the line with the toggled checkbox and (if applicable) completion date
		vim.api.nvim_set_current_line(line)

		-- Remove the current line from its position
		vim.api.nvim_buf_set_lines(0, current_line_num - 1, current_line_num, false, {})

		-- Move the line to the top if unchecked, or bottom if checked
		if line:find("%[ %]") then
			-- Unchecked: insert at the top
			vim.api.nvim_buf_set_lines(0, 0, 0, false, { line })
		else
			-- Checked: insert at the bottom
			local last_line = vim.api.nvim_buf_line_count(0)
			vim.api.nvim_buf_set_lines(0, last_line, last_line, false, { line })
		end
	end

	local function close_buffer()
		-- Save the buffer before closing
		vim.cmd("write")

		-- Wipe the buffer to remove it completely from the buffer list
		vim.cmd("bwipeout")
	end

	-- Get the buffer number of the "TODO.md" file
	local bufnr = vim.api.nvim_get_current_buf()

	-- Set up key mappings
	vim.api.nvim_buf_set_keymap(bufnr, "n", "  ", "", {
		callback = toggle_checkbox,
		noremap = true,
		silent = true,
		desc = "Toggle TODO checkbox",
	})

	vim.api.nvim_buf_set_keymap(bufnr, "n", " x", "", {
		callback = toggle_dash_within_brackets,
		noremap = true,
		silent = true,
		desc = "Toggle dash within brackets",
	})

	vim.api.nvim_buf_set_keymap(bufnr, "n", " q", "", {
		callback = close_buffer,
		noremap = true,
		silent = true,
		desc = "Close buffer",
	})
end

function M.open_readme()
	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'README.md' file
	local readme_file_path = project_dir .. "/README.md"

	-- Check if the 'README.md' file exists
	local file_exists = vim.fn.filereadable(readme_file_path) == 1

	-- If it does not exist, create the file with default content
	if not file_exists then
		-- Open the file in write mode and create default content
		local file = io.open(readme_file_path, "w")
		if file then
			-- Write the default content
			file:write("# " .. prop.current_project.name .. "\n\n\n")
			file:close()
			vim.notify("Created new README.md with default title", vim.log.levels.INFO)
		else
			vim.notify("Failed to create README.md", vim.log.levels.ERROR)
			return
		end
	end

	-- Open the 'README.md' file in a new buffer
	vim.cmd("edit " .. readme_file_path)
end

local function refresh_todo_buffer_if_open()
	local filepath = prop.current_project.project_path .. "/TODO.md"
	-- Find buffer by file path
	local buf = vim.fn.bufnr(filepath, true)
	if buf ~= -1 then
		-- Check if the buffer is visible in any window
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == buf then
				-- Reload the buffer
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("edit")
				end)
				break
			end
		end
	end
end

function M.todo_add()
	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'todo' file
	local todo_file_path = project_dir .. "/TODO.md"

	-- Check if the 'todo' file exists
	if vim.fn.filereadable(todo_file_path) == 0 then
		vim.notify("No todo file found", vim.log.levels.WARN)
		return
	end

	-- Ask the user for the todo item text
	local todo_text = vim.fn.input(prop.current_project.name .. ": Enter todo item: ")

	-- Get the current date in 'yyyy-mm-dd' format
	local current_date = os.date("%Y-%m-%d")

	-- Open the file in read mode to get existing content
	local file = io.open(todo_file_path, "r")
	local content = file:read("*all")
	file:close()

	-- Prepend the new todo item to the content with the created date
	local new_content = "- [ ] " .. todo_text .. " [created::" .. current_date .. "]\n" .. content

	-- Write the updated content back to the file
	file = io.open(todo_file_path, "w")
	if file then
		file:write(new_content)
		file:close()
		refresh_todo_buffer_if_open()
		vim.notify("Added a new todo item at the start of the file", vim.log.levels.INFO)
	else
		vim.notify("Failed to open todo file", vim.log.levels.ERROR)
	end
end

function M.close_all_buffers()
	vim.cmd("%bd") -- Close all buffers
end

function M.grep_in_project_include_under_cursor(pre_entered_word)
	local word = get_current_word()
	M.grep_in_project_include(word)
end
function M.grep_in_project_include(pre_entered_word)
	pre_entered_word = pre_entered_word or ""

	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path to the 'include' file
	local include_file_path = project_dir .. "/include"
	print("include_file_path: " .. include_file_path)

	-- Check if the 'include' file exists
	if vim.fn.filereadable(include_file_path) == 0 then
		vim.notify("No include file found", vim.log.levels.WARN)
		return
	end

	-- Read the contents of the 'include' file
	local include_file_content = vim.fn.readfile(include_file_path)

	-- Check if the file is empty
	if #include_file_content == 0 then
		vim.notify("No file paths found in include file", vim.log.levels.INFO)
		return
	end

	-- Prepare the table of file paths for Telescope's search_dirs
	local search_dirs = {}
	for _, file_path in ipairs(include_file_content) do
		table.insert(search_dirs, file_path)
	end

	local user_input = nil

	-- Call Telescope to grep within the included directories
	require("telescope.builtin").live_grep({
		search_dirs = search_dirs, -- Use the table of file paths as search directories
		prompt_title = "Grep in Included Directories", -- Custom prompt title

		on_input_filter_cb = function(input)
			user_input = input
			return input -- You must return the input for Telescope to function correctly
		end,
		attach_mappings = function(_, map)
			map("i", "<CR>", function(prompt_bufnr)
				-- Get user input and selection
				local actions = require("telescope.actions")
				-- Wont work to get current line
				--user_input = require("telescope.actions.state").get_current_line()
				--selected_result = require("telescope.actions.state").get_selected_entry()
				-- Get the selected entry
				local action_state = require("telescope.actions.state")
				local selected_entry = action_state.get_selected_entry()
				-- Close Telescope
				actions.close(prompt_bufnr)
				-- Open the selected file in Neovim
				if selected_entry and selected_entry.filename then
					require("phxm.buffer").update_history(
						selected_entry.filename,
						selected_entry.lnum,
						"grep> " .. user_input
					)
					vim.cmd("edit " .. vim.fn.fnameescape(selected_entry.filename))

					-- Optionally move the cursor to the matched line
					if selected_entry.lnum then
						vim.api.nvim_win_set_cursor(0, { selected_entry.lnum, 0 })
					end
				end
				-- write user input to file
				-- save to memory regardless remember-flag
			end)
			return true
		end,

		default_text = pre_entered_word, -- Pre-fill the input with preset text
		sorter = require("telescope").extensions.fzf.native_fzf_sorter(), -- Use fzf fuzzy sorting
	})

	-- Call Telescope to grep within the included directories
	--	Original
	--	require("telescope.builtin").live_grep({
	--		search_dirs = search_dirs, -- Use the table of file paths as search directories
	--		prompt_title = "Grep in Included Directories", -- Custom prompt title
	--		on_input_filter_cb = function(input)
	--			user_input = input
	--			return input -- You must return the input for Telescope to function correctly
	--		end,
	--		sorter = require("telescope").extensions.fzf.native_fzf_sorter(), -- Use fzf fuzzy sorting
	--	})
end

function M.switch_to_project(selected_project)
	project.switch_to_project(selected_project)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Recursively collect directories, pruning any dir named "symlinks"
-- ──────────────────────────────────────────────────────────────────────────────
local function collect_dirs(root)
	local uv = vim.loop
	local dirs = {}

	local function scan(dir)
		local fd = uv.fs_scandir(dir)
		if not fd then
			return
		end

		while true do
			local name, typ = uv.fs_scandir_next(fd)
			if not name then
				break
			end

			if typ == "directory" then
				if name ~= "symlinks" then -- ✂ 1. never descend into /symlinks
					local full = dir .. "/" .. name
					table.insert(dirs, full) --    2. never list /symlinks itself
					scan(full) --    recurse
				end
			end
		end
	end

	scan(root)
	return dirs
end

function M.switch_project_via_telescope()
	local project_base_path = prop.root.root_path or "/home/f/.vim-projects"

	local project_dirs = collect_dirs(project_base_path)

	if #project_dirs == 0 then
		vim.notify("No project folders found in: " .. project_base_path, vim.log.levels.INFO)
		return
	end

	--	-- Use Telescope to display the project directories
	--	require("telescope.builtin").find_files({
	--		prompt_title = "Switch Project",
	--		finder = require("telescope.finders").new_table({
	--			results = project_dirs,
	--		}),
	--		sorter = require("telescope.config").values.generic_sorter({}),
	--		attach_mappings = function(prompt_bufnr, map)
	--			-- Define what happens when the user selects a project
	--			local actions = require("telescope.actions")
	--			local action_state = require("telescope.actions.state")
	--
	--			map("i", "<CR>", function()
	--				local selection = action_state.get_selected_entry()
	--				actions.close(prompt_bufnr)
	--
	--				-- Switch to the selected project
	--				if selection then
	--					M.switch_to_project(selection[1])
	--				end
	--			end)
	--
	--			return true
	--		end,
	--	})

	-- Use Telescope to display the project directories
	require("telescope.builtin").find_files({
		prompt_title = "Switch Project",
		finder = require("telescope.finders").new_table({
			results = project_dirs,
			entry_maker = entry_maker,
		}),
		sorter = require("telescope.config").values.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			-- Define what happens when the user selects a project
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")

			map("i", "<CR>", function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)

				-- Switch to the selected project
				if selection then
					-- NOTE: Or original
					M.switch_to_project(selection.value)
					-- Now done in switch_to_project
					--require("phxm.buffer").re_bind_buffer_keys()
				end
			end)

			return true
		end,
	})
end
-- Function to prompt user for a key and scan project directories

-- Function to recursively scan directories for .key files and check if the key exists
local function check_key_in_dir(dir, key)
	-- Debug: show which directory we are scanning

	-- Check for the existence of .key file in the current directory
	local root_key_file = dir .. "/.key"
	if vim.fn.filereadable(root_key_file) == 1 then
		local file_content = vim.fn.readfile(root_key_file)
		for _, line in ipairs(file_content) do
			if line == key then
				return true, root_key_file -- Key found in the root .key file
			end
		end
	end

	--	-- Get a list of subdirectories to scan
	--	local subdirs = vim.fn.glob(dir .. "/*", false, 1)
	--	for _, subdir in ipairs(subdirs) do
	--		if vim.fn.isdirectory(subdir) == 1 then
	--			local is_key_taken, matching_file = check_key_in_dir(subdir, key)
	--			if is_key_taken then
	--				return true, matching_file -- Key found in a subdirectory
	--			end
	--		end
	--	end
	-- Get a list of subdirectories to scan
	local subdirs = vim.fn.glob(dir .. "/*", false, true)
	for _, subdir in ipairs(subdirs) do
		-- Check if the path is a directory and not a symlink
		local stat = vim.uv.fs_lstat(subdir)
		if stat and stat.type == "directory" then
			local is_key_taken, matching_file = check_key_in_dir(subdir, key)
			if is_key_taken then
				return true, matching_file -- Key found in a subdirectory
			end
		end
	end

	return false, nil -- No key found in this directory or its subdirectories
end

-- Function to prompt user for a key and manage key assignment
function M.assign_key_to_current_project()
	local key = vim.fn.input("Enter a key character: ")
	if key == "" then
		print("No key entered. Aborting.")
		return
	end

	-- Debug: display the key entered
	print("User entered key: " .. key)

	-- Ensure `M.config.project_base` is set before proceeding
	if not prop.current_project.project_path then
		print("Error: project path not set.")
		return
	end

	-- Debug: display the base directory being scanned

	-- Check if the key is already taken
	local is_key_taken, matching_file = check_key_in_dir(prop.root.root_path, key)

	if is_key_taken then
		print("Key '" .. key .. "' is already taken in file: " .. matching_file)
	else
		-- Key is not taken, proceed to create a new .key file in the current project directory
		local key_file_path = prop.current_project.project_path .. "/.key"
		vim.fn.writefile({ key }, key_file_path)

		-- Debug: confirm that the key file has been written
		print("Key '" .. key .. "' created successfully in: " .. key_file_path)
	end
end
-- Function to prompt user for a project name and store it in .name file
function M.name_current_project()
	-- Ensure `prop.current_project.project_path` is set
	if not prop.current_project.project_path then
		print("Error: `prop.current_project.project_path` is not set.")
		return
	end

	-- Prompt the user for the project name
	local project_name = vim.fn.input("Enter the project name: ")

	if project_name == "" then
		print("No name entered. Aborting.")
		return
	end

	project_name = project_name:gsub("^%s*(.-)%s*$", "%1")

	-- Define the .name file path
	local name_file_path = prop.current_project.project_path .. "/.name"

	-- Write the project name to the .name file
	vim.fn.writefile({ project_name }, name_file_path)

	-- Update our realtime usage also
	require("phxm.properties").update_project_name(project_name)

	-- Confirm that the project name has been saved
	print("Project name '" .. project_name .. "' saved to: " .. name_file_path)
end

function M.name_current_buffer()
	-- Ensure `prop.current_project.project_path` is set
	if not prop.current_project.project_path then
		print("Error: `prop.current_project.project_path` is not set.")
		return
	end

	-- Get the current buffer's path
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path == "" then
		print("Error: No buffer path found.")
		return
	end

	-- Prompt the user for the buffer name
	local buffer_name = vim.fn.input("Enter a name for the current buffer: ")

	if buffer_name == "" then
		print("No name entered. Aborting.")
		return
	end

	-- Define the .named_buffers file path
	local named_buffers_file_path = prop.current_project.project_path .. "/.named_buffers"

	-- Read the current contents of the .named_buffers file if it exists
	local named_buffers = {}
	if vim.fn.filereadable(named_buffers_file_path) == 1 then
		local file_content = vim.fn.readfile(named_buffers_file_path)
		named_buffers = vim.json.decode(table.concat(file_content, "\n")) or {}
	end

	-- Update or insert the path:name pair
	named_buffers[buf_path] = buffer_name

	-- Write the updated table back to the file as JSON
	local json_data = vim.json.encode(named_buffers)
	vim.fn.writefile({ json_data }, named_buffers_file_path)

	-- Confirm that the buffer name has been saved
	print("Buffer name '" .. buffer_name .. "' saved with path: " .. buf_path)
	-- NOTE: Is it necessary to rebind buffer keys here?
	require("phxm.buffer").re_bind_buffer_keys()
end
function M.delete_buffer()
	--vim.api.nvim_buf_delete(0, { force = true })
	-- Use current buffer if no buffer ID is provided
	local buffer_id = vim.api.nvim_get_current_buf()

	-- Check if the buffer exists before attempting to delete
	if vim.api.nvim_buf_is_valid(buffer_id) then
		--vim.api.nvim_buf_delete(buffer_id, { force = true })
		-- This one works, the others seem to leave them unlisted but are found when we laters scan in rebinding
		vim.cmd("bwipeout! " .. buffer_id)

		--vim.api.nvim_buf_delete(buffer_id, { force = true, unload = true })
		require("phxm.buffer").re_bind_buffer_keys()
	else
	end
end

return M
