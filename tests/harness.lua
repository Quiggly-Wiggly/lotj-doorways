local H = {}
local json = dofile('tests/json.lua')
local profile = assert(os.getenv('DOOR_TEST_HOME'), 'DOOR_TEST_HOME must be an isolated test directory')
local originalOpen, originalRename = io.open, os.rename
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
H.count = count
function H.equal(actual, expected, detail)
  if actual == expected then return end
  if type(actual) == 'table' then actual = json.encode(actual) end
  if type(expected) == 'table' then expected = json.encode(expected) end
  assert(actual == expected, (detail or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end
function H.write(text)
  local file = assert(originalOpen(profile .. '/lotj-doorways.json', 'w'))
  file:write(text); file:close()
end
function H.read()
  local file = originalOpen(profile .. '/lotj-doorways.json', 'r')
  if not file then return nil end
  local text = file:read('*a'); file:close(); return text
end
function H.reset(options)
  options = options or {}
  io.open, os.rename = originalOpen, originalRename
  if lotjDoorways and lotjDoorways.shutdown then lotjDoorways.shutdown() end
  os.remove(profile .. '/lotj-doorways.json')
  os.remove(profile .. '/lotj-doorways.json.tmp')
  os.remove(profile .. '/lotj-doorways.json.bak')
  if options.storage then H.write(options.storage) end
  if options.backup then
    local file=assert(originalOpen(profile .. '/lotj-doorways.json.bak','w'))
    file:write(options.backup); file:close()
  end
  lotjDoorways, lotj, gmcp, matches = nil, nil, {}, {}
  if options.initialRoom then
    gmcp.Room={Info={vnum=options.initialRoom.vnum,name=options.initialRoom.name}}
  end
  speedWalkDir, speedWalkPath = {}, {}
  Geyser, Adjustable = nil, nil
  local env = {handlers={}, aliases={}, triggers={}, timers={}, sent={}, sendCalls={}, messages={}, mapperRecords={}, nextId=0, now=0,
    version=options.version or '4.20.0', separator=options.separator or ';;', stockWalkCalls={}, exits={}, specialExits={}, exitLocks={}, roomLocks={}, connected=options.connected~=false,
    mapUserData={}, mapWrites=0}
  for key,value in pairs(options.mapUserData or {}) do env.mapUserData[key]=value end
  H.env = env
  local function id() env.nextId=env.nextId+1; return env.nextId end
  local function callback(fn, ...)
    if type(fn) == 'string' then return assert(loadstring(fn))() end
    return fn(...)
  end
  function env.emit(event, ...)
    local handlers = {}
    for key, item in pairs(env.handlers) do if item.event == event then handlers[#handlers+1] = {key,item} end end
    table.sort(handlers, function(a,b) return a[1]<b[1] end)
    for _, item in ipairs(handlers) do if env.handlers[item[1]] then callback(item[2].fn,event,...) end end
  end
  function env.advance(seconds)
    env.now=env.now+seconds
    local due={}
    for key,item in pairs(env.timers) do if item.at <= env.now then due[#due+1]={key,item} end end
    table.sort(due,function(a,b) return a[1]<b[1] end)
    for _,item in ipairs(due) do
      if env.timers[item[1]] then env.timers[item[1]]=nil; callback(item[2].fn) end
    end
  end
  function getMudletHomeDir() return profile end
  function getMudletVersion(format)
    env.versionFormat = format
    if format == 'string' then return env.version end
    local major,minor,patch=env.version:match('(%d+)%.(%d+)%.(%d+)')
    return {major=tonumber(major),minor=tonumber(minor),patch=tonumber(patch)}
  end
  function getCommandSeparator() return env.separator end
  function toJSON(value) return json.encode(value) end
  function fromJSON(value) return json.decode(value) end
  yajl = {to_string=json.encode, to_value=json.decode}
  function cecho(...) env.messages[#env.messages+1]={...} end
  echo = cecho
  function resetFormat() end
  function setUnderline() end
  function setBold() end
  function setItalics() end
  function setFgColor() end
  function getEpoch() return env.now * 1000 end
  function getConnectionInfo() return 'localhost', 4000, env.connected end
  function getRoomExits(id) return env.exits[tonumber(id)] or {} end
  function hasExitLock(id,direction)
    local locks=env.exitLocks[tonumber(id)] or {}
    return locks[direction]==true
  end
  function roomLocked(id) return env.roomLocks[tonumber(id)]==true end
  function getMapUserData(key)
    if env.mapReadFailure then return nil,tostring(env.mapReadFailure) end
    return env.mapUserData[key],env.mapUserData[key]==nil and 'map key not found' or nil
  end
  function setMapUserData(key,value)
    if env.mapWriteFailure then return nil,tostring(env.mapWriteFailure) end
    env.mapUserData[key]=value; env.mapWrites=env.mapWrites+1; return true
  end
  function getSpecialExits(id,showAll)
    assert(showAll==true,'walker must request all special-exit commands')
    return env.specialExits[tonumber(id)] or {}
  end
  function registerAnonymousEventHandler(event, fn)
    local key=id(); env.handlers[key]={event=event,fn=fn}; return key
  end
  function killAnonymousEventHandler(key) env.handlers[key]=nil; return true end
  function registerNamedEventHandler(packageName,name,event,fn)
    for key,item in pairs(env.handlers) do if item.name==name and item.packageName==packageName then env.handlers[key]=nil end end
    local key=id(); env.handlers[key]={packageName=packageName,name=name,event=event,fn=fn}; return true
  end
  function deleteNamedEventHandler(packageName,name)
    for key,item in pairs(env.handlers) do if item.name==name and item.packageName==packageName then env.handlers[key]=nil end end
    return true
  end
  function tempAlias(pattern,fn)
    local key=id(); env.aliases[key]={pattern=pattern,fn=fn}; return key
  end
  function killAlias(key) env.aliases[key]=nil; return true end
  function tempRegexTrigger(pattern,fn)
    local key=id(); env.triggers[key]={pattern=pattern,fn=fn}; return key
  end
  function killTrigger(key) env.triggers[key]=nil; return true end
  function tempTimer(seconds,fn)
    local key=id(); env.timers[key]={at=env.now+seconds,fn=fn}; return key
  end
  function killTimer(key) env.timers[key]=nil; return true end
  function send(command,showOnScreen)
    env.sent[#env.sent+1]=command
    env.sendCalls[#env.sendCalls+1]={command=command,echo=showOnScreen}
    env.emit('sysDataSendRequest',command)
  end
  env.originalSpeedWalk=function(...)
    env.stockWalkCalls[#env.stockWalkCalls+1]={...}
    for _,direction in ipairs(speedWalkDir or {}) do send(direction) end
    return 'original-speedwalk-result', 27
  end
  doSpeedWalk=env.originalSpeedWalk
  function expandAlias() error('replacement commands must use send(), never expandAlias()') end
  function denyCurrentSend() error('Doorways must never cancel sysDataSendRequest') end
  function raiseEvent(event,...) return env.emit(event,...) end
  function env.room(vnum,name)
    gmcp.Room={Info={vnum=vnum,name=name or ('Room '..tostring(vnum)),exits={'north','east','south','west'}}}
    env.emit('gmcp.Room.Info')
  end
  function env.mapper()
    local mapper={mappingArea='Test area',lastMoveDirs={},processed={},directionObjects={}}
    for short,long in pairs({n='north',ne='northeast',e='east',se='southeast',s='south',sw='southwest',w='west',nw='northwest',u='up',d='down'}) do
      mapper.directionObjects[short]={short=short,long=long}
    end
    lotj={mapper=mapper}
    mapper.handleSentCommand=function(_,command)
      local dir
      command=command:match('^%s*(.-)%s*$')
      for _,candidate in ipairs(lotjDoorways and lotjDoorways.directions or {}) do
        if command==candidate.short or command==candidate.long then dir=candidate.short end
      end
      if not dir or mapper.mappingArea==nil then return end
      mapper.lastMoveDirs[#mapper.lastMoveDirs+1]=mapper.directionObjects[dir]
      env.mapperRecords[#env.mapperRecords+1]=dir
    end
    mapper.processCurrentRoom=function()
      local dir=table.remove(mapper.lastMoveDirs,1)
      if env.mapperDrainQueue then
        local reverse={n='south',ne='southwest',e='west',se='northwest',s='north',sw='northeast',w='east',nw='southeast',u='down',d='up'}
        local exits=gmcp.Room.Info.exits or {}
        local function hasReverse(direction)
          for _,exit in ipairs(exits) do if exit==reverse[direction.short] then return true end end
          return false
        end
        while dir and not hasReverse(dir) and #mapper.lastMoveDirs>0 do dir=table.remove(mapper.lastMoveDirs,1) end
      end
      mapper.processed[#mapper.processed+1]={vnum=tostring(mapper.current.vnum),direction=dir and dir.short or false}
      return 'mapper-result', 17
    end
    mapper.onEnterRoom=function()
      mapper.last=mapper.current
      mapper.current={vnum=gmcp.Room.Info.vnum}
      return mapper.processCurrentRoom()
    end
    registerAnonymousEventHandler('sysDataSendRequest',mapper.handleSentCommand)
    registerAnonymousEventHandler('gmcp.Room.Info',mapper.onEnterRoom)
    return mapper
  end
  if options.named == false then registerNamedEventHandler=nil; deleteNamedEventHandler=nil end
  if options.mapperFirst then env.mapper() end
  dofile('src/core.lua')
  dofile('src/map_storage.lua')
  dofile('src/walker.lua')
  if options.ui then
    dofile('tests/widgets.lua')()
    dofile('src/ui.lua')
  else
    -- Most tests use a local-only view spy. Widget behavior uses the actual UI
    -- Lua with doubles; native appearance remains a manual acceptance check.
    lotjDoorways.ui = {refresh=function() end,open=function() env.uiShown=true end,destroy=function() env.uiDestroyed=true end}
  end
  dofile('src/runtime.lua')
  return lotjDoorways, env
end
return H
