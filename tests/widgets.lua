-- Geyser boundary doubles. These verify Lua actions/lifecycle, not native layout.
local function install()
  local W = {}
  W.__index = W
  function W:new(options, parent)
    options = options or {}
    options.parent, options.windowList, options.text = parent, {}, ''
    setmetatable(options, W)
    if parent then parent.windowList[options.name] = options end
    return options
  end
  function W:echo(text) self.text = text end
  function W:echoLink(text, fn)
    self.links = self.links or {}; self.links[#self.links+1] = fn
  end
  function W:print(text) self.text = text end
  function W:getText() return self.text end
  function W:clear() self.text = ''; self.links = {} end
  function W:setStyleSheet(text) self.style = text end
  function W:setClickCallback(fn) self.callback = fn end
  function W:setAction(fn) self.action = fn end
  function W:hide() self.hidden = true end
  function W:show() self.hidden = false end
  function W:raiseAll() end
  function W:changeMenuStyle() end
  function W:delete() self.deleted = true end
  function W:restore() self.minimized = false end
  Geyser = {Label=W, CommandLine=W, MiniConsole=W}
  Adjustable = {Container={all={}, all_windows={}}}
  function Adjustable.Container:new(options)
    local window = W:new(options)
    self.all[options.name] = window
    self.all_windows[#self.all_windows+1] = options.name
    return window
  end
end
return install
