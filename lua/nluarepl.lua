local json = vim.json

---@class nluarepl.Client
---@field seq integer
---@field varref integer
---@field vars table<integer, dap.Variable[]>
---@field hook_active boolean
---@field breakpoints table<string, table<integer, dap.SourceBreakpoint>>
---@field socket? uv.uv_pipe_t
local Client = {}
local client_mt = {__index = Client}
local rpc = require("dap.rpc")


---@param client nluarepl.Client
---@param fn function
---@param env? table
local function setenv(client, fn, env)
  env = env or getfenv(fn)
  local result = {}

  function result.print(...)
    local line = table.concat({...})

    ---@type dap.OutputEvent
    local output = {
      category = "stdout",
      output = line .. "\n"
    }
    client:send_event("output", output)
  end

  setmetatable(result, {__index = env})
  setfenv(fn, result)
  return result
end

---@param expression string
---@return string
local function addreturn(expression)
  local parser = vim.treesitter.get_string_parser(expression, "lua")
  local trees = parser:parse()
  local root = trees[1]:root() -- root is likely chunk
  local child = root:child(root:child_count() - 1)
  if child and child:type() ~= "return_statement" then
    local slnum, scol, _, _ = child:range()
    local lines = vim.split(expression, "\n", { plain = true })
    local line = lines[slnum + 1]
    lines[slnum + 1] = line:sub(1, scol) .. "return " .. line:sub(scol or 1)
    expression = table.concat(lines, "\n")
  end
  return expression
end


---@param client nluarepl.Client
---@param expression string
---@param env? table
---@return any
---@return string? error
local function eval(client, expression, env)
  local fn, err = loadstring(addreturn(expression))
  if err then
    return "nil", err
  else
    assert(fn)
    setenv(client, fn, env)
    local value = fn()
    return value or "nil"
  end
end


function Client:handle_input(body)
  local request = json.decode(body)
  local handler = self[request.command]
  if handler then
    vim.schedule(function()
      handler(self, request)
    end)
  else
    print('no handler for ' .. request.command)
  end
end


---@param request dap.Request
---@param message string
function Client:send_err_response(request, message, error)
  self.seq = request.seq + 1
  local payload = {
    seq = self.seq,
    type = 'response',
    command = request.command,
    success = false,
    request_seq = request.seq,
    message = message,
    body = {
      error = error,
    },
  }
  if self.socket then
    self.socket:write(rpc.msg_with_content_length(json.encode(payload)))
  end
end


---@param request dap.Request
---@param body any
function Client:send_response(request, body)
  self.seq = request.seq + 1
  local payload = {
    seq = self.seq,
    type = 'response',
    command = request.command,
    success = true,
    request_seq = request.seq,
    body = body,
  }
  if self.socket then
    self.socket:write(rpc.msg_with_content_length(json.encode(payload)))
  end
end


---@param event string
---@param body any
function Client:send_event(event, body)
  self.seq = self.seq + 1
  local payload = {
    seq = self.seq,
    type = 'event',
    event = event,
    body = body,
  }
  self.socket:write(rpc.msg_with_content_length(json.encode(payload)))
end


---@param command string
---@param arguments any
function Client:send_request(command, arguments)
  self.seq = self.seq + 1
  local payload = {
    seq = self.seq,
    type = "request",
    command = command,
    arguments = arguments,
  }
  self.socket:write(rpc.msg_with_content_length(json.encode(payload)))
end


function Client:initialize(request)
  ---@type dap.Capabilities
  local capabilities = {
    supportsLogPoints = true,
    supportsConditionalBreakpoints = true,
  }
  self:send_response(request, capabilities)
  self:send_event("initialized", {})
end


function Client:disconnect(request)
  debug.sethook()
  self:send_event("terminated", {})
  self:send_response(request, {})
end


function Client:terminate(request)
  debug.sethook()
  self:send_event("terminated", {})
  self:send_response(request, {})
end

function Client:launch(request)
  self:send_response(request, {})
end


---@param client nluarepl.Client
---@param expression string
---@param env? table
---@return boolean
local function matches(client, expression, env)
  local value, err = eval(client, expression, env)
  if err then
    ---@type dap.OutputEvent
    local output = {
      output = err,
      category = "console"
    }
    client:send_event("output", output)
    return false
  else
    return value == true
  end
end


function Client:setBreakpoints(request)
  ---@type dap.SetBreakpointsArguments
  local args = request.arguments

  ---@type dap.Breakpoint[]
  local result = {}

  local path = args.source.path
  if not path then
    self:send_err_response(request, "source in setBreakpoints request requires a path")
    return
  end
  self.breakpoints[path] = nil
  for _, bp in ipairs(args.breakpoints or {}) do
    local logMessage = bp.logMessage
    if logMessage == nil then
      table.insert(result, {
        verified = false
      })
    else
      table.insert(result, {
        verified = true,
        line = bp.line,
      })
      local source_bps = self.breakpoints[path]
      if not source_bps then
        source_bps = {}
        self.breakpoints[path] = source_bps
      end
      source_bps[bp.line] = bp
    end
  end

  if not self.hook_active and next(self.breakpoints) then
    self.hook_active = true
    local function hook(_, lnum)
      local frame = 2
      local debuginfo = debug.getinfo(frame, "Sf")
      local source = debuginfo.source:sub(2)
      local bps = self.breakpoints[source] or {}
      local bp = bps[lnum]
      if bp then
        local env = debug.getfenv(debuginfo.func)
        local localidx =1
        while true do
          local name, value = debug.getlocal(frame, localidx)
          localidx = localidx + 1
          if name then
            env[name] = value or vim.NIL
          else
            break
          end
        end
        local condition = bp.condition
        if condition and not matches(self, condition, env) then
          return
        end
        local msg = assert(bp.logMessage)
        if not vim.endswith(msg, "\n") then
          msg = msg .. "\n"
        end
        ---@type dap.OutputEvent
        local output = {
          category = "console",
          output = msg:gsub("{([%w_%.]+)}", function(match)
            local value = env[match]
            if value then
              return vim.inspect(value)
            end
            local val, err = eval(self, match, env)
            if err then
              return err
            end
            return vim.inspect(val)
          end)
        }
        self:send_event("output", output)
      end
    end
    debug.sethook(hook, "l")
  end

  ---@type dap.SetBreakpointsResponse
  local response = {
    breakpoints = result
  }
  self:send_response(request, response)
end


---@param key any
---@param value any
---@param parent_expression string
---@return dap.Variable
function Client:_to_variable(key, value, parent_expression)
  local result = {
    name = tostring(key),
    value = tostring(value),
    type = type(value)
  }
  local name = result.name
  local index = string.match(result.name, '^%[?(%d+)%]?$')
  if index then
    result.evaluateName = parent_expression .. "[" .. index .. "]"
  else
    result.evaluateName = parent_expression .. "[\"" .. name .. "\"]"
  end
  if type(value) == "table" then
    result.value = result.value .. " size=" .. vim.tbl_count(value)
    local variables = {}
    for k, v in pairs(value) do
      table.insert(variables, self:_to_variable(k, v, result.evaluateName))
    end
    local varref = self.varref + 1
    self.varref = varref
    self.vars[varref] = variables
    result.variablesReference = varref
  else
    result.variablesReference = 0
  end
  return result
end


---@param request dap.Request
function Client:evaluate(request)
  ---@type dap.EvaluateArguments
  local args = request.arguments

  local result, err = eval(self, args.expression)
  if err then
    self:send_err_response(request, tostring(err), err)
    return
  end
  assert(result, "loadstring must return result if there is no error")

  if type(result) == "table" then
    local tbl = result
    local variables = {}
    for k, v in pairs(tbl) do
      table.insert(variables, self:_to_variable(k, v, args.expression))
    end

    local varref = 0
    if next(variables) then
      varref = self.varref + 1
      self.varref = varref
      self.vars[varref] = variables
    end

    ---@type dap.EvaluateResponse
    local response = {
      result = tostring(tbl) .. " size=" .. tostring(vim.tbl_count(tbl)),
      variablesReference = varref,
    }
    self:send_response(request, response)
  else
    ---@type dap.EvaluateResponse
    local response = {
      result = tostring(result),
      variablesReference = 0,
    }
    self:send_response(request, response)
  end
end


---@param request dap.Request
function Client:variables(request)
  ---@type dap.VariablesArguments
  local args = request.arguments
  local variables = self.vars[args.variablesReference]
  self:send_response(request, {
    variables = variables or {}
  })
end


---@param cb fun(adapter: dap.Adapter)
local function nluarepl(cb)
  local server = assert(vim.uv.new_pipe())
  local pipe = os.tmpname()
  os.remove(pipe)
  server:bind(pipe)

  ---@type nluarepl.Client
  local client = {
    seq = 0,
    varref = 0,
    vars = {},
    breakpoints = {},
    hook_active = false,
  }
  setmetatable(client, client_mt)
  server:listen(128, function(err)
    if err then
      error(vim.inspect(err))
    else
      local socket = assert(vim.uv.new_pipe())
      client.socket = socket
      server:accept(socket)
      local function on_chunk(body)
        client:handle_input(body)
      end
      local function on_eof()
        client.vars = {}
        client.varref = 0
        client.breakpoints = {}
        client.hook_active = false
        debug.sethook()
        socket:close(function()
          server:close()
        end)
      end
      socket:read_start(require("dap.rpc").create_read_loop(on_chunk, on_eof))
    end
  end)
  local adapter = {
    type = "pipe",
    pipe = pipe
  }
  cb(adapter)
end


return {
  nluarepl = nluarepl
}
