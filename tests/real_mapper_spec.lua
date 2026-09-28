-- Exercise unmodified LotJ mapper code with fake Mudlet APIs and game data.
-- LOTJ_MAPPER_SOURCE must point at a trusted checkout's mapper.lua.
local source = assert(os.getenv('LOTJ_MAPPER_SOURCE'))
local H = dofile('tests/harness.lua')
local eq = H.equal
local passed = 0

function table.contains(items, value)
  for _, item in pairs(items) do if item == value then return true end end
  return false
end
function table.is_empty(items) return next(items) == nil end
function string.trim(value) return value:match('^%s*(.-)%s*$') end

local function ready(mapperFirst)
  local D, env = H.reset()
  if mapperFirst then D.shutdown() end
  local rooms = {[100]={name='Source', coords={0,0,0}, stubs={}}}
  env.links = {}
  function setCustomEnvColor() end
  function getRooms()
    local result = {}
    for id, room in pairs(rooms) do result[id] = room.name end
    return result
  end
  function getAreaTable() return {Test=1} end
  function getRoomArea() return 1 end
  function getRoomAreaName() return 'Test' end
  function addRoom(id) rooms[id]={name='', coords={0,0,0}, stubs={}} end
  function setRoomArea() end
  function setRoomCoordinates(id,x,y,z) rooms[id].coords={x,y,z} end
  function getRoomCoordinates(id) return unpack(rooms[id].coords) end
  function setRoomName(id,name) rooms[id].name=name end
  local dirs = {n=1,ne=2,nw=3,e=4,w=5,s=6,se=7,sw=8,u=9,d=10}
  function setExitStub(id,dir) table.insert(rooms[id].stubs,dirs[dir]) end
  function getExitStubs1(id) return rooms[id].stubs end
  function setDoor() end
  function getRoomsByPosition(_,x,y,z)
    local result = {}
    for id,room in pairs(rooms) do
      if room.coords[1]==x and room.coords[2]==y and room.coords[3]==z then
        result[#result+1]=id
      end
    end
    return result
  end
  getTableSize = H.count
  function setExit(from,to,dir) env.links[#env.links+1]={from,to,dir} end
  function centerview(id) env.centered=id end
  function updateMap() end
  function env.room(id,exits)
    gmcp.Room={Info={vnum=id,name='Room '..id,planet='Test',exits=exits or {}}}
    env.emit('gmcp.Room.Info')
  end
  lotj={configTable={},settings={}}
  dofile(source)
  local originalRoom, originalWalk = lotj.mapper.processCurrentRoom, doSpeedWalk
  registerAnonymousEventHandler('sysDataSendRequest',lotj.mapper.handleSentCommand)
  registerAnonymousEventHandler('gmcp.Room.Info',lotj.mapper.onEnterRoom)
  lotj.mapper.mappingArea='Test'
  if mapperFirst then D.init() else env.emit('lotjUiLoaded') end
  env.room(100); env.advance(0)
  env.links={}
  return D,env,rooms,originalRoom,originalWalk
end

local function test(name, callback)
  local ok, err = pcall(callback)
  assert(ok, name..': '..tostring(err))
  passed=passed+1
  print('PASS '..name)
end

for _,mapperFirst in ipairs({true,false}) do
  local order=mapperFirst and 'mapper first' or 'Doorways first'
  for _,voice in ipairs({true,false}) do
    test('actual mapper records manual '..(voice and 'voice' or 'ordinary')..' door: '..order,function()
      local D,env,rooms=ready(mapperFirst)
      assert(D.setRule('100','Source','e',voice and {'say enter'} or {'open east','east'}))
      D.move('e')
      eq(env.sent,voice and {'say enter'} or {'open east','east'})
      env.room(100); env.advance(0) -- opening refresh must not create a self-exit
      eq(env.links,{})
      env.room(101,{west='O'}); env.advance(0)
      eq(env.links,{{100,101,'e'},{101,100,'w'}})
      eq(rooms[101].coords,{1,0,0})
      eq(#lotj.mapper.lastMoveDirs,0)
    end)
  end
  test('actual mapper preserves burst crossings through one-way doors: '..order,function()
    local D,env,rooms=ready(mapperFirst)
    addRoom(101); addRoom(102)
    env.exits={[100]={east=101},[101]={north=102}}
    assert(D.setRule('100','Source','e',{'say enter'}))
    assert(D.setRule('101','Next','n',{'open north','north'}))
    speedWalkDir, speedWalkPath={'e','n'},{101,102}
    assert(doSpeedWalk()); env.advance(0)
    eq(env.sent,{'say enter','open north','north'})
    eq(#(lotj.mapper.lastMoveDirs or {}),0)
    env.room(100); eq(env.links,{})
    env.room(101,{north='O'}); env.room(101,{north='O'})
    eq(env.links,{{100,101,'e'}})
    env.room(102,{}); env.advance(0)
    eq(env.links,{{100,101,'e'},{101,102,'n'}})
    eq(D.walker.active,nil)
    eq(#lotj.mapper.lastMoveDirs,0)
    eq(env.sent,{'say enter','open north','north'})
  end)
  test('actual mapper repeated directions stay aligned: '..order,function()
    local D,env=ready(mapperFirst)
    addRoom(101); addRoom(102)
    env.exits={[100]={east=101},[101]={east=102}}
    speedWalkDir,speedWalkPath={'e','e'},{101,102}
    assert(doSpeedWalk()); env.advance(0)
    env.room(101,{}); env.room(102,{}); env.advance(0)
    eq(env.sent,{'e','e'})
    eq(env.links,{{100,101,'e'},{101,102,'e'}})
    eq(D.walker.active,nil)
  end)
  test('actual mapper disabled walking and uninstall restore original functions: '..order,function()
    local D,env,_,originalRoom,originalWalk=ready(mapperFirst)
    assert(D.setRule('100','Source','e',{'say enter'}))
    assert(D.setEnabled(false))
    speedWalkDir={'e','n'}
    doSpeedWalk()
    eq(env.sent,{'e','n'})
    D.shutdown()
    eq(lotj.mapper.processCurrentRoom,originalRoom)
    eq(doSpeedWalk,originalWalk)
  end)
end
print(passed..' real mapper integration checks passed (mock Mudlet APIs).')
