local wezterm = require("wezterm")

return {
	hyperlink_rules = {
		-- Linkify things that look like URLs and the host has a TLD name.
		-- Compiled-in default. Used if you don't specify any hyperlink_rules.
		{
			regex = '\\b\\w+://[\\w.-]+\\.[a-z]{2,15}\\S*\\b',
			format = '$0',
		},
		{
			regex = '((http([s]){0,1}://){0,1}(localhost|127.0.0.1){1}(([:]){0,1}[\0-9]{4}){0,1}/{0,1}){1}',
			format = '$0',
		},

		{
			regex = [[\bfile://\S*\b]],
			format = '$0',
		},

		-- Linkify things that look like URLs with numeric addresses as hosts.
		-- E.g. http://127.0.0.1:8000 for a local development server,
		-- or http://192.168.1.1 for the web interface of many routers.
		{
			regex = [[\b\w+://(?:[\d]{1,3}\.){3}[\d]{1,3}\S*\b]],
			format = '$0',
		},

		-- Make task numbers clickable
		-- The first matched regex group is captured in $1.
		{
			regex = [[\b[tT](\d+)\b]],
			format = 'https://example.com/tasks/?t=$1',
		},

		-- Make username/project paths clickable. This implies paths like the following are for GitHub.
		-- ( "nvim-treesitter/nvim-treesitter" | wbthomason/packer.nvim | wez/wezterm | "wez/wezterm.git" )
		-- As long as a full URL hyperlink regex exists above this it should not match a full URL to
		-- GitHub or GitLab / BitBucket (i.e. https://gitlab.com/user/project.git is still a whole clickable URL)
		{
			regex = [[["]?([\w\d]{1}[-\w\d]+)(/){1}([-\w\d\.]+)["]?]],
			format = 'https://www.github.com/$1/$3',
		},
	},
	color_scheme = "Catppuccin Macchiato",
	font = wezterm.font 'CaskaydiaCove NF',
	keys = {
		{ key = '=', mods = 'CTRL', action = wezterm.action.IncreaseFontSize },
	},
	mouse_bindings = {
		{
			event = {
				Up = {
					streak = 1,
					button = "Right"
				}
			},
			mods = "NONE",
			action = wezterm.action { PasteFrom = "PrimarySelection" }
		},
	},
}
