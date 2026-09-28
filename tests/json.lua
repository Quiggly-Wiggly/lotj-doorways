-- Small independent JSON fixture codec for the tests, not shipped in the package.
local J = {}
local escapes = {['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f',
                 ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return escapes[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end
function J.encode(value)
  local kind = type(value)
  if kind == 'nil' then return 'null' end
  if kind == 'string' then return quote(value) end
  if kind == 'boolean' or kind == 'number' then return tostring(value) end
  assert(kind == 'table', 'unsupported JSON type: ' .. kind)
  local count, array, out = 0, true, {}
  for k in pairs(value) do
    count = count + 1
    if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 then array = false end
  end
  if array and count == #value then
    for _, item in ipairs(value) do out[#out+1] = J.encode(item) end
    return '[' .. table.concat(out, ',') .. ']'
  end
  local keys = {}
  for key in pairs(value) do keys[#keys+1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do out[#out+1] = quote(key) .. ':' .. J.encode(value[key]) end
  return '{' .. table.concat(out, ',') .. '}'
end
function J.decode(text)
  assert(type(text) == 'string', 'JSON must be text')
  local pos = 1
  local function skip() pos = text:find('%S', pos) or (#text+1) end
  local parse
  local function str()
    pos = pos + 1
    local out = {}
    while pos <= #text do
      local c = text:sub(pos,pos); pos = pos+1
      if c == '"' then return table.concat(out) end
      if c == '\\' then
        c = text:sub(pos,pos); pos = pos+1
        local decode = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
        if c == 'u' then
          local hex = text:sub(pos,pos+3); pos = pos+4
          local n = assert(tonumber(hex,16), 'invalid unicode escape')
          if n < 128 then c = string.char(n)
          elseif n < 2048 then c = string.char(192+math.floor(n/64),128+n%64)
          else c = string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
        else c = assert(decode[c], 'invalid escape') end
      else assert(c:byte() >= 32, 'control character in JSON string') end
      out[#out+1] = c
    end
    error('unterminated JSON string')
  end
  parse = function()
    skip()
    local c = text:sub(pos,pos)
    if c == '"' then return str() end
    if c == '{' or c == '[' then
      local object, result = c == '{', {}
      local close = object and '}' or ']'
      pos = pos+1; skip()
      if text:sub(pos,pos) == close then pos = pos+1; return result end
      while true do
        local key
        if object then
          assert(text:sub(pos,pos) == '"', 'expected key'); key = str(); skip()
          assert(text:sub(pos,pos) == ':', 'expected colon'); pos = pos+1
        end
        local value = parse()
        if object then result[key] = value else result[#result+1] = value end
        skip(); c = text:sub(pos,pos); pos = pos+1
        if c == close then return result end
        assert(c == ',', 'expected comma'); skip()
      end
    end
    for word, value in pairs({['true']=true, ['false']=false}) do
      if text:sub(pos,pos+#word-1) == word then pos = pos+#word; return value end
    end
    if text:sub(pos,pos+3) == 'null' then pos = pos+4; return nil end
    local number = text:sub(pos):match('^%-?%d+%.?%d*[eE]?[+-]?%d*')
    assert(number and tonumber(number), 'invalid JSON at byte ' .. pos)
    pos = pos+#number; return tonumber(number)
  end
  local value = parse(); skip(); assert(pos > #text, 'trailing JSON data')
  return value
end
return J
