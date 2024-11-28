# nluarepl

A nvim-lua debug adapter for use with [nvim-dap][nvim-dap].

This debug adapter can only evaluate expressions within the running nvim
process. The main (and only) goal is to have an interactive REPL to query and
modify the running nvim process.

If you're looking for a way to debug Neovim plugins you should head to [osv][osv].

## Installation

- Install [nvim-dap][nvim-dap]; it's a dependency
- Install this plugin:

```
git clone https://github.com/mfussenegger/nluarepl.git \
    ~/.config/nvim/pack/plugins/start/nluarepl
```

The plugin automatically registers a `nluarepl` adapter for `nvim-dap` and
creates a `nluarepl` configuration which is always available.

---

Disclaimer: There's a chance the functionality of this plugin could get
included in [osv][osv], if that happens this plugin here will be archived.

[osv]: https://github.com/jbyuki/one-small-step-for-vimkind
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
