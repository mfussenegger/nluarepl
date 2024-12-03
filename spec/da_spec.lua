local dap = require("dap")
dap.adapters.nluarepl = require("nluarepl").nluarepl
local config = {
  name = "nluarepl",
  type = "nluarepl",
  request = "launch",
}

describe("nluarepl", function()
  before_each(function()
    dap.run(config)
    vim.wait(5000, function()
      local session = dap.session()
      return session ~= nil and session.initialized == true
    end)
  end)
  after_each(function()
    dap.terminate()
    vim.wait(5000, function()
      return dap.session() == nil
    end)
  end)

  ---@param text string
  ---@return dap.CompletionsResponse
  local function getcompletions(text)
    local session = assert(dap.session())
    ---@type dap.CompletionsArguments
    local args = {
      text = text,
      column = #text
    }
    local resp
    session:request("completions", args, function(_, r)
      resp = r
    end)
    vim.wait(1000, function() return resp ~= nil end)
    return resp
  end

  it("shows completions for vi", function()
    local expected = {
      {
        label = "vim",
        ["type"] = "value"
      }
    }
    assert.are.same(expected,  getcompletions("vi").targets)
    assert.are.same({},  getcompletions("vim").targets)
  end)

  it("doesn't show completions for unknown module", function()
    assert.are.same({},  getcompletions("invalid.").targets)
  end)

  it("shows completions for vim.sp", function()
    local expected = {
      targets = {
        {
          label = "spairs",
          ["type"] = "function"
        },
        {
          label = "spell",
          ["type"] = "value"
        },
        {
          label = "split",
          ["type"] = "function"
        }
      }
    }
    local result = getcompletions("vim.sp")
    assert.are.same(expected,  result)
  end)

  it("Can evaluate assignments", function()
    local err, result
    local session = assert(dap.session())
    ---@type dap.EvaluateArguments
    local params = {
      expression = "_G.x = 10"
    }
    session:request("evaluate", params, function(e, r)
      err = e
      result = r
    end)
    vim.wait(1000, function() return result ~= nil end)
    assert.is_nil(err)
    assert.are.same({ result = "", variablesReference = 0 }, result)

    err = nil
    result = nil
    params = {
      expression = "_G.x"
    }
    session:request("evaluate", params, function(e, r)
      err = e
      result = r
    end)
    vim.wait(1000, function() return result ~= nil end)
    assert.is_nil(err)
    assert.are.same({ result = "10", variablesReference = 0 }, result)
  end)
end)
