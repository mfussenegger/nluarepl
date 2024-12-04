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

  ---@param expression string
  ---@return dap.EvaluateResponse?
  ---@return dap.ErrorResponse?
  local function eval(expression)
    local session = assert(dap.session())
    ---@type dap.EvaluateArguments
    local args = {
      expression = expression
    }
    local err
    local resp
    session:request("evaluate", args, function(e, r)
      err = e
      resp = r
    end)
    vim.wait(1000, function() return resp ~= nil or err ~= nil end)
    return resp, err
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
    local result, err = eval("_G.x = 10")
    assert.is_nil(err)
    assert.are.same({ result = "", variablesReference = 0 }, result)

    result, err = eval("_G.x")
    assert.is_nil(err)
    assert.are.same({ result = "10", variablesReference = 0 }, result)
  end)

  it("Can handle cyclic structures", function()
    eval("_G.test_root = {}")
    eval("_G.test_child = {value = 10, parent = _G.test_root}")
    eval("_G.test_root.children = {_G.test_child}")
    local result, err = eval("_G.test_root")
    assert.is_nil(err)
    assert.is_match("^table", assert(result).result)

    result, err = eval("_G.test_child")
    assert.is_nil(err)
    assert.is_match("^table", assert(result).result)
  end)
end)
