# Neovim Configuration

A modern Neovim configuration using lazy.nvim plugin manager with modular structure and custom color highlighting plugin.

## Overview

This is a performance-focused Neovim configuration that emphasizes:
- Modular architecture for maintainability
- Modern development tools (LSP, TreeSitter, completion)
- Custom Colorify plugin for enhanced color highlighting
- Optimized startup time and runtime performance

## Folder Structure

```
~/.config/nvim/
├── init.lua                    # Entry point
├── lazy-lock.json             # Plugin versions
├── lua/
│   ├── core/                  # Core configuration
│   │   ├── init.lua          # Loads core modules
│   │   ├── options.lua       # Neovim settings
│   │   ├── keymaps.lua       # Key mappings
│   │   ├── lazy.lua          # Plugin manager setup
│   │   └── performance.lua   # Performance optimizations
│   ├── plugins/               # Plugin configurations
│   │   ├── lsp.lua           # Language Server Protocol
│   │   ├── blink-cmp.lua     # Completion engine
│   │   ├── treesitter.lua    # Syntax highlighting
│   │   ├── dap.lua           # Debug Adapter Protocol
│   │   ├── snacks.lua        # UI framework
│   │   ├── nvim-tree.lua     # File explorer
│   │   ├── lualine.lua       # Status line
│   │   ├── flash.lua         # Motion enhancement
│   │   ├── mini-surround.lua # Surround pairs
│   │   ├── mini-pair.lua     # Auto-close pairs
│   │   ├── mini-clue.lua     # Key binding hints
│   │   ├── smart-split.lua   # Window management
│   │   ├── persistence.lua   # Session management
│   │   ├── todo-comments.lua # TODO highlighting
│   │   ├── arrow.lua         # Bookmarks
│   │   ├── dropbar.lua       # Winbar navigation
│   │   ├── smear-cursor.lua  # Cursor animation
│   │   ├── incline.lua       # Floating headers
│   │   ├── colorscheme.lua   # Theme (vague.nvim)
│   │   └── typr.lua          # Typing practice
│   └── colorify/              # Custom color plugin
│       ├── init.lua          # Entry point
│       ├── config.lua        # Configuration
│       ├── attach.lua        # Buffer attachment
│       ├── methods.lua       # Core logic
│       ├── utils.lua         # Helpers
│       └── state.lua         # State management
└── docs/                     # Documentation
    ├── colorify.md
    ├── keymaps.md
    └── troubleshooting.md
```

## Plugins

### Development Tools
- **nvim-lspconfig** - LSP client configurations
- **mason.nvim** - Portable LSP server management
- **blink.cmp** - Fast completion engine
- **nvim-treesitter** - Syntax highlighting and code navigation
- **nvim-dap** - Debug Adapter Protocol support

### UI Enhancement
- **snacks.nvim** - Comprehensive UI framework (notifications, dashboard, etc.)
- **nvim-tree.lua** - File explorer sidebar
- **lualine.nvim** - Customizable status line
- **dropbar.nvim** - Winbar/breadcrumb navigation
- **smear-cursor.nvim** - Animated cursor movement
- **incline.nvim** - Floating header for functions

### Editing Features
- **flash.nvim** - Enhanced navigation and selection
- **mini.surround** - Add/delete/change surrounding pairs
- **mini.pairs** - Auto-close brackets and quotes
- **mini.clue** - Better key binding hints

### Utilities
- **smart-splits.nvim** - Intelligent window resizing
- **persistence.nvim** - Session management
- **todo-comments.nvim** - Highlight TODO/FIXME/etc.
- **arrow.nvim** - Visual bookmark system
- **typr.nvim** - Typing practice plugin

### Visual
- **vague.nvim** - Colorscheme
- **colorify.nvim** - Custom color highlighting plugin

### Plugin Management
- **lazy.nvim** - Plugin manager and loader

---

*Last updated: $(date +%Y-%m-%d)*
