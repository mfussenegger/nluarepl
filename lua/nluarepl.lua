local json = vim.json

---@class nluarepl.Var
---@field evalname string
---@field value any?

---@class nluarepl.Client
---@field seq integer
---@field varref integer
---@field vars table<integer, nluarepl.Var>
---@field locref integer
---@field locrefs table<integer, debuginfo>
---@field hook_active boolean
---@field breakpoints table<string, table<integer, dap.SourceBreakpoint>>
---@field socket? uv.uv_pipe_t
local Client = {}
local client_mt = {__index = Client}


---@param client nluarepl.Client
---@param fn function
---@param env? table
local function setenv(client, fn, env)
  env = env or getfenv(fn)
  local result = {}

  function result.print(...)
    local args = {}
    local argc = select("#", ...)
    for i = 1, argc do
      local arg = select(i, ...)
      args[i] = tostring(arg or "nil")
    end
    local line = table.concat(args, "\t")

    ---@type dap.OutputEvent
    local output = {
      category = "stdout",
      output = line .. "\n"
    }
    client:send_event("output", output)
  end

  setmetatable(result, {
    __index = env,
    __newindex = function(_, k, v)
      env[k] = v
    end,
  })
  setfenv(fn, result)
  return result
end

---@param expression string
---@return string
---@return string?
local function addreturn(expression)
  local parser = vim.treesitter.get_string_parser(expression, "lua")
  local trees = parser:parse()
  local root = trees[1]:root() -- root is likely chunk
  local child = root:child(root:child_count() - 1)
  if child then
    if child:type() == "assignment_statement" then
      return expression, "assignment_statement"
    end
    if child:type() ~= "return_statement" then
      local slnum, scol, _, _ = child:range()
      local lines = vim.split(expression, "\n", { plain = true })
      local line = lines[slnum + 1]
      lines[slnum + 1] = line:sub(1, scol) .. "return " .. line:sub(scol or 1)
      expression = table.concat(lines, "\n")
    end
  end
  return expression, (child and child:type() or nil)
end


---@param client nluarepl.Client
---@param expression string
---@param env? table
---@return any
---@return string? error
local function eval(client, expression, env)
  local expr_type
  expression, expr_type = addreturn(expression)
  local default_value = expr_type == "assignment_statement" and "" or "nil"
  local fn, err = loadstring(expression)
  if err then
    return "nil", err
  else
    assert(fn)
    setenv(client, fn, env)
    local ok, value = pcall(fn)
    if ok then
      return value or default_value
    end
    return "nil", value
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
    self:send_err_response(request, "No handler for " .. request.command)
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
    self.socket:write(require("dap.rpc").msg_with_content_length(json.encode(payload)))
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
    self.socket:write(require("dap.rpc").msg_with_content_length(json.encode(payload)))
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
  if self.socket then
    self.socket:write(require("dap.rpc").msg_with_content_length(json.encode(payload)))
  end
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
  if self.socket then
    self.socket:write(require("dap.rpc").msg_with_content_length(json.encode(payload)))
  end
end


function Client:initialize(request)
  ---@type dap.Capabilities
  local capabilities = {
    supportsLogPoints = true,
    supportsConditionalBreakpoints = true,
    supportsCompletionsRequest = true,
    completionTriggerCharacters = {"."},
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


---@param request dap.Request
function Client:completions(request)
  ---@type dap.CompletionsArguments
  local args = request.arguments

  local lines = vim.split(args.text, "\n", { plain = true })
  local line = args.line ~= nil and lines[args.line + 1] or lines[1]
  local prefix = line:sub(1, args.column)
  local parts = vim.split(prefix, ".", { plain = true })

  local env = getfenv(1)
  for i, part in ipairs(parts) do
    if part == "" then
      break
    end
    local e = env[part]
    if type(e) == "table" then
      env = e
    else
      if i < #parts then
        env = {}
      end
      break
    end
  end

  ---@type dap.CompletionItem[]
  local items = {}

  for key, val in pairs(env) do
    if vim.startswith(key, parts[#parts]) then
      ---@type dap.CompletionItem
      local item = {
        label = key,
        ["type"] = type(val) == "function" and "function" or "value"
      }
      table.insert(items, item)
    end
  end

  table.sort(items, function(a, b)
    return a.label < b.label
  end)

  ---@type dap.CompletionsResponse
  local response = {
    targets = items
  }
  self:send_response(request, response)
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
  elseif self.hook_active and not next(self.breakpoints) then
    self.hook_active = false
    debug.sethook()
  end

  ---@type dap.SetBreakpointsResponse
  local response = {
    breakpoints = result
  }
  self:send_response(request, response)
end


---@param name string
---@param parent_expression string
---@return string
local function evalname(name, parent_expression)
  local index = string.match(name, '^%[?(%d+)%]?$')
  if index then
    return parent_expression .. "[" .. index .. "]"
  else
    return parent_expression .. "[\"" .. name .. "\"]"
  end
end


---@param value any
---@param parentexpr string
---@return integer
function Client:_nextref(value, parentexpr)
  local ref = self.varref + 1
  self.varref = ref
  self.vars[ref] = {
    value = value,
    evalname = parentexpr,
  }
  return ref
end


---@param value any
---@param parentexpr string
---@return string valuestr
---@return integer varref
---@return integer? location
function Client:_valueresult(value, parentexpr)
  local valuestr = tostring(value)
  local varref = 0
  local location = nil
  local num_children = 0
  local type_ = type(value)
  if type_ == "table" then
    num_children = vim.tbl_count(value)
    valuestr = valuestr .. " size=" .. num_children
  elseif type_ == "function" then
    local info = debug.getinfo(value, "Su")
    if info.source:sub(1, 1) == "@" then
      local locref = self.locref + 1
      location = locref
      self.locref = locref
      self.locrefs[locref] = info
    end
    num_children = num_children + info.nups
  end
  if type_ ~= "string" then
    local mt = getmetatable(value)
    if mt then
      num_children = num_children + 1
    end
  end
  if num_children > 0 then
    varref = self:_nextref(value, parentexpr)
  end
  return valuestr, varref, location
end


---@param key any
---@param value any
---@param parentexpr string
---@return dap.Variable
function Client:_to_variable(key, value, parentexpr)
  local name = tostring(key)
  local new_parentexpr = evalname(name, parentexpr)
  local valuestr, varref, location = self:_valueresult(value, new_parentexpr)
  ---@type dap.Variable
  local result = {
    name = name,
    value = valuestr,
    type = type(value),
    evaluateName = new_parentexpr,
    variablesReference = varref,
    declarationLocationReference = location
  }
  return result
end


---@param request dap.Request
function Client:evaluate(request)
  ---@type dap.EvaluateArguments
  local args = request.arguments

  local value, err = eval(self, args.expression)
  if err then
    self:send_err_response(request, tostring(err), err)
    return
  end
  assert(value, "loadstring must return result if there is no error")

  local valuestr, varref, locref = self:_valueresult(value, args.expression)

  ---@type dap.EvaluateResponse
  local response = {
    result = valuestr,
    variablesReference = varref,
    valueLocationReference = locref,
  }
  self:send_response(request, response)
end


---@param request dap.Request
function Client:variables(request)
  ---@type dap.VariablesArguments
  local args = request.arguments
  local entry = self.vars[args.variablesReference]
  if not entry then
    self:send_err_response(request, "No variable found for reference: " .. args.variablesReference)
    return
  end
  local value = entry.value
  local parent = entry.evalname
  local variables = {}
  if type(value) == "table" then
    for k, v in pairs(value) do
      table.insert(variables, self:_to_variable(k, v, parent))
    end
  elseif type(value) == "function" then
    local idx = 1
    while true do
      local upname, upvalue = debug.getupvalue(value, idx)
      if upname then
        if upname == "" then
          upname = "<upval:" .. idx .. ">"
        end
        table.insert(variables, self:_to_variable(upname, upvalue, parent))
        idx = idx + 1
      else
        break
      end
    end
  end
  local mt = getmetatable(value)
  if mt then
    local mt_eval = "getmetatable(" .. parent .. ")"
    local ref = self:_nextref(mt, mt_eval)
    local value_text = tostring(mt)
    if type(mt) == "table" then
      value_text = value_text .. " size=" .. vim.tbl_count(mt)
    end

    ---@type dap.Variable
    local var = {
      name = "[[metatable]]",
      value = value_text,
      evaluateName = mt_eval,
      variablesReference = ref
    }
    table.insert(variables, var)
  end
  self:send_response(request, {
    variables = variables
  })
end


---@param request dap.Request
function Client:locations(request)
  ---@type dap.LocationsArguments
  local args = request.arguments
  local info = self.locrefs[args.locationReference]
  if info then
    ---@type dap.LocationsResponse
    local response = {
      line = info.linedefined,
      source = {
        path = info.source:sub(2)
      }
    }
    self:send_response(request, response)
  else
    self:send_err_response(request, "location not found")
  end
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
    locref = 0,
    locrefs = {},
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
        client.locrefs = {}
        client.locref = 0
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
