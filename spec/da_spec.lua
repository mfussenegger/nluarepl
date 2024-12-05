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

  ---@param method string
  ---@param args any
  local function request(method, args)
    local session = assert(dap.session())
    local err
    local resp
    session:request(method, args, function(e, r)
      err = e
      resp = r
    end)
    vim.wait(1000, function() return resp ~= nil or err ~= nil end)
    return resp, err
  end

  ---@param text string
  ---@return dap.CompletionsResponse?
  ---@return dap.ErrorResponse?
  local function getcompletions(text)
    ---@type dap.CompletionsArguments
    local args = {
      text = text,
      column = #text
    }
    return request("completions", args)
  end

  ---@param ref integer
  ---@return dap.VariableResponse?
  ---@return dap.ErrorResponse?
  local function vars(ref)
    ---@type dap.VariablesArguments
    local args = {
      variablesReference = ref
    }
    return request("variables", args)
  end

  ---@param loc integer
  ---@return dap.LocationsResponse?
  ---@return dap.ErrorResponse?
  local function getlocations(loc)
    ---@type dap.LocationsArguments
    local args = {
      locationReference = loc
    }
    return request("locations", args)
  end

  ---@param expression string
  ---@return dap.EvaluateResponse?
  ---@return dap.ErrorResponse?
  local function eval(expression)
    ---@type dap.EvaluateArguments
    local args = {
      expression = expression
    }
    return request("evaluate", args)
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

  it("shows metatable info on userdata values", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local expression = [[
local parser = vim.treesitter.get_parser(%d, 'lua')
local tree = parser:parse()
return tree[1]
]]
    local result, err = eval(string.format(expression, bufnr))
    assert.is_nil(err)
    assert(result)
    assert.are.same("<tree> size=4", result.result)

    local vars_result
    vars_result, err = vars(result.variablesReference)
    assert.is_nil(err)
    assert(vars_result)
    local names = vim.tbl_map(function(v) return v.name end, vars_result.variables)
    table.sort(names)
    assert.are.same({"copy", "edit", "included_ranges", "root"}, names)
  end)

  it("provides location ref for functions", function()
    local result, err = eval("vim.lsp.get_clients")
    assert.is_nil(err)
    local expected = {
      result = tostring(vim.lsp.get_clients),
      valueLocationReference = 1,
      variablesReference = 1
    }
    assert.are.same(expected, result)

    local locations, err2 = getlocations(1)
    assert.is_nil(err2)
    local info = debug.getinfo(vim.lsp.get_clients, "S")
    expected = {
      line = info.linedefined,
      source = {
        path = info.source:sub(2)
      }
    }
    assert.are.same(expected, locations)
  end)
end)
