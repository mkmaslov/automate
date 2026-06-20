-- Download lazy.nvim, if not present
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", 
				          "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" }, { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

--------------------------------------------------------------------------------

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Settings
vim.opt.number = true
vim.opt.ruler = true
vim.opt.showcmd = true
vim.opt.autoindent = true
vim.opt.wrap = true
vim.opt.hlsearch = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.colorcolumn = "80"
vim.opt.clipboard:append("unnamedplus")
vim.opt.expandtab = true

--------------------------------------------------------------------------------

-- Setup lazy.nvim
require("lazy").setup({
  -- PLUGINS
  spec = {
    -- File tree
    { "nvim-tree/nvim-tree.lua", version = "*", lazy = false,
      -- File tree icons
      dependencies = {"nvim-tree/nvim-web-devicons"},
      config = function()
        require("nvim-tree").setup {}
      end,
    },
    -- Hints on keybindings
    {"folke/which-key.nvim", event = "VeryLazy", opts = {}},
    -- Colormap
    {"EdenEast/nightfox.nvim", lazy = false},
    -- Ruler
    {"lukas-reineke/virt-column.nvim", opts = {virtcolumn = "80,100"}},
    -- Status bar
    {"nvim-lualine/lualine.nvim", opts = { options = { theme = "auto" }}},
    -- Syntax highlighting
    {"nvim-treesitter/nvim-treesitter", build = ":TSUpdate",
      opts = {
      ensure_installed = {"bash", "c", "cpp", "julia", "lua", "luadoc",
        "markdown", "markdown_inline", "python", "query", "vim", "vimdoc",
      },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
},
  },
  -- Disable hererocks
  rocks = { enabled = false },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "habamax"} },
  -- automatically check for plugin updates
  checker = { enabled = true },
})

-- Set colorscheme
vim.cmd.colorscheme("carbonfox")

--------------------------------------------------------------------------------

-- KEYBINDINGS

-- nvim-tree
local api = require("nvim-tree.api")
vim.keymap.set("n", "<leader>e", api.tree.toggle,
  { desc = "Toggle explorer", silent = true })
vim.keymap.set("n", "<leader>o", api.tree.focus,
  { desc = "Focus explorer",  silent = true })
vim.keymap.set("n", "<leader>r", api.tree.find_file,
  { desc = "Reveal file in explorer", silent = true })
-- which-key
vim.keymap.set("i", "<C-g>", function()
  require("which-key").show({ mode = "i" })
  end, { desc = "which-key (insert)" })
-- which-key
-- local wk = require("which-key")
-- wk.add({ { "<leader>", group = "leader" } }, { mode = "v" })
-- wk.add({ { "<C-g>", group = "insert" } }, { mode = "i" })

--------------------------------------------------------------------------------