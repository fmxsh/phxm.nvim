local prop = require("phxm.properties")
--
-- helper.lua
local M = {}
function M.session_file_exists()
	local session_file = prop.current_project.files.session
	return vim.fn.filereadable(session_file) == 1
end
-- Function to save a session in the current project directory
function M.save()
	--issue event to save the session
	vim.api.nvim_exec_autocmds("User", { pattern = "phxmPreSessionSave" })
	vim.opt.sessionoptions = { "buffers", "curdir", "folds", "help", "globals", "winpos", "winsize" }
	vim.cmd("mksession! " .. vim.fn.fnameescape(prop.current_project.files.session))

	vim.api.nvim_exec_autocmds("User", { pattern = "phxmPostSessionSave" })
	--	vim.api.nvim_exec_autocmds("User", { pattern = "PreMksession" })
	--	vim.api.nvim_exec_autocmds("User", { pattern = "PostMksession" })
end

-- Function to load/source the session from the current project directory
function M.load()
	vim.cmd("silent! source " .. vim.fn.fnameescape(prop.current_project.files.session))
end
-- Function to wipe out all buffers except for one blank [No Name] buffer
-- Wipe out all buffers, leave a blank nofile, wipe and unlisted one

local function wipe_all_but_one_no_name_ORIGINAL()
	-- Create a new [No Name] buffer if none exists
	vim.cmd("enew")

	-- Get the buffer number of the new [No Name] buffer
	local keep_bufnr = vim.api.nvim_get_current_buf()

	-- Softly delete all buffers with `bdelete`, except the newly created [No Name] buffer
	-- Or we will get errors from "shedulers" trying to access buffer 1
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= keep_bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
			vim.cmd("bdelete! " .. bufnr)
		end
	end
	-- Set the [No Name] buffer to behave as a scratch buffer
	vim.bo[keep_bufnr].buftype = "nofile"
	vim.bo[keep_bufnr].bufhidden = "wipe"
	-- Diaable the below if you want the scratch buffer to be visible
	vim.bo[keep_bufnr].buflisted = false

	-- Iterate over all buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		-- Wipe out all buffers except the newly created [No Name] buffer
		if bufnr ~= keep_bufnr and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
			vim.cmd("bwipeout " .. bufnr)
		end
	end
	-- Confirm all other buffers are closed
	-- Do this because nvim in above delete cycle opens a buffer set to a directory,
	-- so delete that oene and leave only our scratch buffer
	-- If a directory buffer reappears, wipe it out
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= keep_bufnr then
			vim.cmd("bwipeout " .. bufnr)
		end
	end
end
local function wipe_all_but_one_no_name()
	-- Create a new [No Name] buffer and get its buffer number
	vim.cmd("enew")
	local keep_bufnr = vim.api.nvim_get_current_buf()

	-- Set the new buffer to behave as a scratch buffer
	vim.bo[keep_bufnr].buftype = "nofile"
	vim.bo[keep_bufnr].bufhidden = "wipe"
	vim.bo[keep_bufnr].buflisted = false

	-- Delete all other buffers except terminal buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local buftype = vim.bo[bufnr].buftype
		if bufnr ~= keep_bufnr and buftype ~= "terminal" then
			vim.cmd("bwipeout! " .. bufnr)
		end
	end
end

local function wipe_all_but_one_no_name2()
	-- Create a new [No Name] buffer if none exists
	vim.cmd("enew")

	-- Get the buffer number of the new [No Name] buffer
	local keep_bufnr = vim.api.nvim_get_current_buf()
	--	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
	--		log(
	--			"Pre Check: Buffer "
	--				.. bufnr
	--				.. " - Name: "
	--				.. vim.fn.bufname(bufnr)
	--				.. " - Listed: "
	--				.. vim.inspect(vim.bo[bufnr].buflisted)
	--				.. " - Hidden: "
	--				.. vim.inspect(vim.bo[bufnr].bufhidden)
	--				.. " - Type: "
	--				.. vim.inspect(vim.bo[bufnr].buftype)
	--		)
	--	end
	-- Softly delete all buffers with `bdelete`, except the newly created [No Name] buffer
	-- Or we will get errors from "shedulers" trying to access buffer 1
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= keep_bufnr and vim.api.nvim_buf_is_loaded(bufnr) and not vim.bo[bufnr].buftype == "terminal" then
			vim.cmd("bdelete! " .. bufnr)
		end
	end
	-- Set the [No Name] buffer to behave as a scratch buffer
	vim.bo[keep_bufnr].buftype = "nofile"
	vim.bo[keep_bufnr].bufhidden = "wipe"
	-- Diaable the below if you want the scratch buffer to be visible
	vim.bo[keep_bufnr].buflisted = false

	-- Iterate over all buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		-- Wipe out all buffers except the newly created [No Name] buffer
		if
			bufnr ~= keep_bufnr
			and vim.api.nvim_buf_is_loaded(bufnr)
			and vim.bo[bufnr].buflisted
			and not vim.bo[bufnr].buftype == "terminal"
		then
			vim.cmd("bwipeout " .. bufnr)
		end
	end
	-- Confirm all other buffers are closed
	-- Do this because nvim in above delete cycle opens a buffer set to a directory,
	-- so delete that oene and leave only our scratch buffer
	-- If a directory buffer reappears, wipe it out
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr ~= keep_bufnr and not vim.bo[bufnr].buftype == "terminal" then
			vim.cmd("bwipeout " .. bufnr)
		end
	end
	--	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
	--		log(
	--			"Post Check: Buffer "
	--				.. bufnr
	--				.. " - Name: "
	--				.. vim.fn.bufname(bufnr)
	--				.. " - Listed: "
	--				.. vim.inspect(vim.bo[bufnr].buflisted)
	--				.. " - Hidden: "
	--				.. vim.inspect(vim.bo[bufnr].bufhidden)
	--				.. " - Type: "
	--				.. vim.inspect(vim.bo[bufnr].buftype)
	--		)
	--	end
end

function M.destroy()
	-- Get the current project directory
	local project_dir = prop.current_project.project_path

	-- Define the path for the session file
	local session_file = prop.current_project.files.session

	local function close_all_floating_windows()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local config = vim.api.nvim_win_get_config(win)
			if config.relative ~= "" then -- This is a floating window
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	-- Run before restoring session
	-- Or we may get: E5108: Error executing lua: vim/_editor.lua:0: nvim_exec2(): Vim(only):E5601: Cannot close window, only floating window would remain
	-- because of :only further down
	close_all_floating_windows()

	-- Content for the session file
	local session_content = {
		--":bufdo! bwipeout",
		"let SessionLoad = 1",
		"let so_save = &g:so | let siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1",
		'let v:this_session=expand("<sfile>:p")',
		"silent only | silent tabonly",
		"cd " .. project_dir,
		"if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == '' | let wipebuf = bufnr('%') | endif",
		"let shortmess_save = &shortmess",
		"if &shortmess =~ 'A' | set shortmess=aoOA | else | set shortmess=aoO | endif",
		"argglobal",
		"%argdel",
		"$argadd " .. project_dir,
		"wincmd t",
		"let save_winminheight = &winminheight",
		"let save_winminwidth = &winminwidth",
		"set winminheight=0",
		"set winheight=1",
		"set winminwidth=0",
		"set winwidth=1",
		"argglobal",
		"enew",
		"setlocal fdm=manual",
		"setlocal fde=0",
		"setlocal fmr={{{,}}}",
		"setlocal fdi=#",
		"setlocal fdl=0",
		"setlocal fml=1",
		"setlocal fdn=20",
		"setlocal fen",
		"tabnext 1",
		"if exists('wipebuf') && len(win_findbuf(wipebuf)) == 0 && getbufvar(wipebuf, '&buftype') isnot# 'terminal' | silent exe 'bwipe ' . wipebuf | endif",
		"unlet! wipebuf",
		"set winheight=1 winwidth=20",
		"let &shortmess = shortmess_save",
		"let &winminheight = save_winminheight",
		"let &winminwidth = save_winminwidth",
		'let sx = expand("<sfile>:p:r") . "x.vim"',
		"if filereadable(sx) | exe 'source ' . fnameescape(sx) | endif",
		"let &g:so = so_save | let &g:siso = siso_save",
		"set hlsearch",
		"nohlsearch",
		"doautoall SessionLoadPost",
		"unlet SessionLoad",
		'" vim: set ft=vim :',
	}
	for _, cmd in ipairs(session_content) do
		vim.cmd(cmd)
	end
	wipe_all_but_one_no_name()
	-- Write the session content to the .session.vim file
	--	vim.fn.writefile(session_content, session_file)

	-- Notify the user
	--	vim.notify("Session file created at: " .. session_file)
end

return M
