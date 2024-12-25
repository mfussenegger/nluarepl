# nluarepl

A nvim-lua debug adapter for use with [nvim-dap][nvim-dap].

Supported features:

- Evaluate expressions ([Watch demo][eval-demo])
- Logpoints with optional conditions ([Watch demo][logpoint-demo])

Other features like stopping at breakpoints, is not supported due to the
architecture of this plugin. Both Client and debug adapter cannot run in the
same thread if a breakpoint needs to pause execution.

The main goal for this is to have an interactive REPL to query and modify the
running nvim instance.

If you're looking for a way to debug Neovim plugins with full breakpoint
support you should head to [osv][osv].


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

  You can start nvim with `--luamod-dev` to avoid this limitation, but be
  careful setting logpoints on these functions, some of them are called a lot -
  and many by nvim-dap/nluarepl - that can result in output spam and a
  significant slowdown of nvim.

---

Disclaimer: There's a chance the functionality of this plugin could get
included in [osv][osv], if that happens this plugin here will be archived.

[osv]: https://github.com/jbyuki/one-small-step-for-vimkind
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[eval-demo]: https://zignar.net/assets/files/c6144a41526e81b82d9cac39901782a4140d3f14adec3c8b8061cb1028e700ff.webm
[shared.lua]: https://github.com/neovim/neovim/blob/master/runtime/lua/vim/shared.lua
[logpoint-demo]: https://private-user-images.githubusercontent.com/38700/390889660-26060bf8-09f5-4ed4-bd8f-3837f8015990.webm?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3MzQxNzc2MTgsIm5iZiI6MTczNDE3NzMxOCwicGF0aCI6Ii8zODcwMC8zOTA4ODk2NjAtMjYwNjBiZjgtMDlmNS00ZWQ0LWJkOGYtMzgzN2Y4MDE1OTkwLndlYm0_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjQxMjE0JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI0MTIxNFQxMTU1MThaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1jMjJhOTg0NjI3MTVlMDEzNDhmZmMzY2JlODUxYTljZTU5M2VkOWQ2NzI3OWE1OGU4NDE3OTQyOTY1MTE3ODQ4JlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.hb9jh3Xx2yC4VrqyjpWXY1r9pStET8jElOCNI2WEtv8
