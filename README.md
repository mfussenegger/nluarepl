# nluarepl

A nvim-lua debug adapter for use with [nvim-dap][nvim-dap].

Supported features:

- Evaluate expressions
- Logpoints with optional conditions

Other features like stopping at breakpoints, is not supported due to the
architecture of this plugin. Both Client and debug adapter cannot run in the
same thread if a breakpoint needs to pause execution.

The main goal for this is to have an interactive REPL to query and modify the
running nvim instance.

If you're looking for a way to debug Neovim plugins with full breakpoint
support you should head to [osv][osv].

Watch the [Demo][demo].

## Installation

- Install [nvim-dap][nvim-dap]; it's a dependency
- Install this plugin:

```bash
git clone https://github.com/mfussenegger/nluarepl.git \
    ~/.config/nvim/pack/plugins/start/nluarepl
```

## Usage

The plugin automatically registers a `nluarepl` adapter for `nvim-dap` and
creates a `nluarepl` configuration which is always available. You can start it
using `:DapNew nluarepl` or via `dap.continue()`. Afterwards open the
`nvim-dap` REPL using `:DapToggleRepl` and start typing expressions.

For longer multi-line statements you can open a dap-eval buffer using `:sp
dap-eval://lua` and then execute expressions via `:w` inside that buffer.


## Limitations

- Logpoints won't work for functions baked into nvim. This includes functions
  like `vim.split` or other functions defined in [shared.lua][shared.lua]
  nluarepl also can't provide source locations for these functions.

---

Disclaimer: There's a chance the functionality of this plugin could get
included in [osv][osv], if that happens this plugin here will be archived.

[osv]: https://github.com/jbyuki/one-small-step-for-vimkind
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[demo]: https://zignar.net/assets/files/c6144a41526e81b82d9cac39901782a4140d3f14adec3c8b8061cb1028e700ff.webm
[shared.lua]: https://github.com/neovim/neovim/blob/master/runtime/lua/vim/shared.lua
