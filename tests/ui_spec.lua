-- Editor regression tests. No Mudlet process, profile, GUI, or game connection
-- is touched. Installed Geyser Lua sources are optionally read as plain files.
local function check(value, message) assert(value, message or "check failed") end
local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then error(name .. ": " .. tostring(err), 0) end
  passed = passed + 1
end

local widgets, deleted, timers, nextTimer = {}, {}, {}, 0
local nativeSends, aliasSends = 0, 0
function send() nativeSends = nativeSends + 1; error("Editor sent game text") end
function expandAlias() aliasSends = aliasSends + 1; error("Editor expanded an alias") end
function echo() end
function tempTimer(_, fn) nextTimer = nextTimer + 1; timers[nextTimer] = fn; return nextTimer end
function killTimer(id) timers[id] = nil end
function killAnonymousEventHandler() end
local function flushTimers()
  local pending = timers
  timers = {}
  for _, callback in pairs(pending) do callback() end
end
function table.index_of(items, wanted)
  for index, value in ipairs(items) do if value == wanted then return index end end
end

Geyser = { windowList = {}, windows = {}, Dynamic = 1 }
Geyser.__index = Geyser
Geyser.get_x = function() return 0 end
Geyser.get_y = function() return 0 end
Geyser.get_width = function() return 1280 end
Geyser.get_height = function() return 900 end
function Geyser:remove(child)
  self.windowList[child.name] = nil
  local index = table.index_of(self.windows, child.name)
  check(index, "attempted duplicate removal of " .. child.name)
  table.remove(self.windows, index)
end

local geyserPath = os.getenv("MUDLET_GEYSER_PATH")
  or "/Applications/Mudlet.app/Contents/Resources/mudlet-lua/lua/geyser"
local parser = loadfile(geyserPath .. "/GeyserSetConstraints.lua")
local containers = loadfile(geyserPath .. "/GeyserContainer.lua")
local realGeyser = parser and containers
if realGeyser then parser(); containers() end

local W = {}
W.__index = W
function W:new(options, parent)
  options = options or {}
  local widget = {}
  for key, value in pairs(options) do widget[key] = value end
  parent = parent or Geyser
  if parent.Inside then parent = parent.Inside end
  widget.container, widget.windowList, widget.windows = parent, {}, {}
  widget.text, widget.links = "", {}
  setmetatable(widget, W)
  check(not widgets[widget.name], "duplicate widget " .. widget.name)
  widgets[widget.name] = widget
  parent.windowList[widget.name] = widget
  parent.windows[#parent.windows + 1] = widget.name
  if realGeyser then Geyser.calc_constraints(widget, widget, parent) end
  return widget
end
function W:echo(text)
  self.text = self.kind == "console" and (self.text .. text) or text
end
function W:echoLink(text, callback) self.links[#self.links+1] = {text=text, callback=callback} end
function W:print(text) self.text = text end
function W:getText() return self.text end
function W:clear() self.text, self.links = "", {} end
function W:setStyleSheet(css) self.css = css end
function W:setClickCallback(callback) self.callback = callback end
function W:setAction(callback) self.action = callback end
function W:hide() self.hidden = true end
function W:show() self.hidden = false end
function W:raiseAll() end
function W:changeMenuStyle() end
function W:restore() self.minimized = false end
W.remove = Geyser.remove
function W:type_delete()
  check(widgets[self.name] == self, "duplicate native delete " .. self.name)
  widgets[self.name] = nil
  deleted[self.name] = (deleted[self.name] or 0) + 1
end
function W:delete()
  if realGeyser then return Geyser.Container.delete(self) end
  local children = {}
  for _, child in pairs(self.windowList) do children[#children+1] = child end
  for _, child in ipairs(children) do child:delete() end
  self.container:remove(self)
  self:type_delete()
end
local function class(kind)
  return {new=function(_, options, parent) options.kind = kind; return W:new(options, parent) end}
end
Geyser.Label, Geyser.CommandLine, Geyser.MiniConsole = class("label"), class("input"), class("console")
Adjustable = { Container = { all = {}, all_windows = {} } }
function Adjustable.Container:new(options)
  local window = W:new(options)
  local padding = options.padding
  window.Inside = W:new({name=options.name .. "Inside", x=padding, y=padding*2,
    width="-" .. padding, height="-" .. padding}, window)
  self.all[options.name] = window
  self.all_windows[#self.all_windows+1] = options.name
  return window
end

dofile("src/core.lua")
local D = lotjDoorways
local saveCount, saveError = 0, nil
D.save = function()
  if saveError then return nil, saveError end
  saveCount = saveCount + 1
  return true
end
D.state.known = true
D.state.room = {vnum="101", name="First room"}
gmcp = {Room={Info={vnum=101, name="First room"}}}
dofile("src/ui.lua")
local ui = D.ui
local function submit(text, callbackLines)
  ui.widgets.sequence:print(text)
  for _, line in ipairs(callbackLines or {text}) do ui.widgets.sequence.action(line) end
  -- TCommandLine::enterCommand clears the field AFTER callbacks when the profile
  -- has autoClearInputLine enabled. Timers run on the following event-loop tick.
  ui.widgets.sequence:clear()
  flushTimers()
end

check(ui.open())

test("editor shows current version, direction examples, and mapper state", function()
  check(ui.window.titleText == "LotJ Doorways v" .. D.version)
  ui.selectDirection("nw")
  check(ui.widgets.sequenceHint.text:find("open nw;;nw", 1, true))
  check(ui.widgets.status.text:find("map walking unavailable", 1, true))
  local savedWalker, savedAdapter, savedSpeedwalk = D.walker, D.adapter, doSpeedWalk
  doSpeedWalk = function() end
  D.walker = {hook={wrapper=doSpeedWalk}}
  D.adapter = {}
  ui.refresh()
  check(ui.widgets.status.text:find("map walking connected", 1, true))
  D.state.enabled = false
  ui.refresh()
  check(ui.widgets.status.text:find("Doorways disabled", 1, true))
  D.state.enabled = true
  D.walker, D.adapter, doSpeedWalk = savedWalker, savedAdapter, savedSpeedwalk
  local savedHelp, calls = D.printHelp, 0
  D.printHelp = function() calls = calls + 1 end
  ui.widgets.help.callback()
  check(calls == 1 and ui.message:find("main console", 1, true))
  D.printHelp = savedHelp
  ui.selectDirection("n")
end)

test("layout uses Geyser percentage offsets and stays inside its content area", function()
  if not realGeyser then return end
  local area = ui.window.Inside
  local north = ui.widgets.directions.n
  check(math.abs(north:get_width() - (area:get_width() * .1 - 5)) < .001,
    "10%-5px must subtract five pixels after percentage scaling")
  for name, widget in pairs(ui.widgets) do
    if name ~= "directions" then
      check(widget:get_width() > 0 and widget:get_height() > 0, name .. " has nonpositive dimensions")
      check(widget:get_x() + widget:get_width() <= area:get_x() + area:get_width() + .001,
        name .. " extends beyond right edge")
      check(widget:get_y() + widget:get_height() <= area:get_y() + area:get_height() + .001,
        name .. " extends below content")
    end
  end
end)

test("persistence errors preserve existing rules and drafts", function()
  check(D.setRule("101", "First room", "n", {"open n", "n"}))
  saveError = "Disk full"
  submit("say north")
  check(ui.message == "Disk full" and D.getRule("101", "n").commands[1] == "open n")
  check(ui.widgets.sequence:getText() == "say north")
  check(not ui.deleteSelected() and D.getRule("101", "n"))
  saveError = nil
end)

test("room names are escaped and never become executable label links", function()
  ui.selectRoom({vnum="303",name='<a href="send:danger">Door & room</a>'})
  check(ui.widgets.selection.text:find("&lt;a href=&quot;send:danger&quot;&gt;", 1, true))
  check(not ui.widgets.selection.text:find('<a href="send:', 1, true))
end)

test("missing room does not save or discard the submitted draft", function()
  ui.selection = nil
  D.state.known = false
  gmcp.Room.Info = nil
  local before = saveCount
  submit("say enter")
  check(saveCount == before and ui.messageIsError)
  check(ui.widgets.sequence:getText() == "say enter")
  ui.widgets.useCurrent.callback()
  check(not ui.selection)
end)

test("destroy removes detached menu widgets and cancels pending Enter", function()
  local window = ui.window
  -- Adjustable moves menu labels out to Geyser's root after opening its menu.
  local menu = W:new({name="lotjDoorwaysEditorMenu", x=0,y=0,width=20,height=20})
  local item = W:new({name="lotjDoorwaysEditorMenuItem", x=0,y=0,width=20,height=20})
  menu.MenuLabels = {child=item}
  window.rCLabel = menu
  local unrelated = W:new({name="unrelatedWidget", x=0,y=0,width=20,height=20})
  ui.selectRoom({vnum="101", name="First room"}, "e")
  ui.widgets.sequence:print("say enter")
  ui.widgets.sequence.action("say enter")
  local before = saveCount
  ui.destroy()
  flushTimers()
  check(saveCount == before and not ui.window)
  check(not Adjustable.Container.all.lotjDoorwaysEditor and #Adjustable.Container.all_windows == 0)
  for name in pairs(widgets) do check(not name:find("lotjDoorwaysEditor", 1, true), "surviving widget " .. name) end
  check(widgets.unrelatedWidget == unrelated)
  ui.destroy()
  check(ui.open(), "destroyed editor cannot reopen")
  ui.destroy()
  unrelated:delete()
end)

check(nativeSends == 0 and aliasSends == 0, "editor actions must never send")
print(string.format("%d editor checks passed (%s).", passed,
  realGeyser and "installed Geyser constraint parser and recursive deletion" or "portable widget mocks; installed Geyser sources unavailable"))
