local dap = require("dap")
dap.adapters.nluarepl = function(cb, config)
  return require("nluarepl").nluarepl(cb, config)
end
dap.providers.configs["nluarepl"] = function()
  return {
    {
      name = "nluarepl",
      type = "nluarepl",
      request = "launch",
    }
  }
end
