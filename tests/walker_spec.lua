-- Routes compile and dispatch one complete stack. Later game output only
-- confirms/cancels tracking; it must never send another gameplay command.
return function(test,H)
  local eq=H.equal
  local function settle(env) for _=1,6 do env.advance(0) end end
  local function ready(options)
    options=options or {}; if options.mapperFirst==nil then options.mapperFirst=true end
    local D,env=H.reset(options)
    env.exits={[100]={east=101,north=103},[101]={north=102,west=100},[102]={west=103,south=101},[103]={east=102,south=100}}
    env.room(100,'Spaceport'); settle(env); return D,env
  end
  local function save(D,room,dir,steps)
    local ok,err=D.setRule(room,'Room '..room,dir,steps); assert(ok,err)
  end
  local function queue(D,dirs,path)
    local env=H.env; local before=#env.sent
    local ok,err=D.walker.start(dirs or {'e','n'},path or {101,102}); assert(ok,err)
    eq(#env.sent,before,'startup must finish the current event before dispatch')
  end
  local function dispatch(D,dirs,path) queue(D,dirs,path); H.env.advance(0) end
  local function finish(env) env.room(101); env.room(102); settle(env) end
  local function noLaterSends(env,expected) finish(env); env.advance(20); settle(env); eq(env.sent,expected) end
  local function standardRoute() speedWalkDir={'east','north'}; speedWalkPath={101,102} end

  test('map walking dispatches every saved command before any room event',function()
    local D,env=ready(); save(D,100,'e',{'say enter'}); save(D,101,'n',{'open north','north'})
    standardRoute(); assert(doSpeedWalk()); eq(env.sent,{}); env.advance(0)
    eq(env.sent,{'say enter','open north','north'}); eq(#env.stockWalkCalls,0); eq(gmcp.Room.Info.vnum,100)
    assert(D.walker.active); finish(env); eq(D.walker.active,nil); eq(env.sent,{'say enter','open north','north'})
  end)
  test('unmatched directions are sent together in the same dispatch',function()
    local D,env=ready(); dispatch(D); eq(env.sent,{'e','n'}); noLaterSends(env,{'e','n'}); eq(D.walker.active,nil)
  end)
  test('replacement-only say exit receives no appended direction',function()
    local D,env=ready(); save(D,100,'e',{'say exit'}); dispatch(D,{'e'},{101}); eq(env.sent,{'say exit'})
    env.room(101); settle(env); eq(env.sent,{'say exit'})
  end)
  test('revisiting a source expands its saved rule on each visit',function()
    local D,env=ready(); save(D,100,'e',{'say enter'}); save(D,101,'w',{'say west'}); save(D,101,'n',{'say north'})
    dispatch(D,{'e','w','e','n'},{101,100,101,102}); eq(env.sent,{'say enter','say west','say enter','say north'})
    for _,room in ipairs({101,100,101,102}) do env.room(room) end
    settle(env); eq(D.walker.active,nil); eq(env.sent,{'say enter','say west','say enter','say north'})
  end)
  test('global route arrays are copied before deferred dispatch',function()
    local D,env=ready(); standardRoute(); assert(doSpeedWalk())
    speedWalkDir[2]='south'; speedWalkPath[2]=999; speedWalkDir={'w'}; speedWalkPath={888}
    env.advance(0); eq(env.sent,{'east','north'}); finish(env); eq(D.walker.active,nil)
  end)
  test('public route arrays are copied before deferred dispatch',function()
    local D,env=ready(); local dirs,path={'e','n'},{101,102}; queue(D,dirs,path)
    dirs[2]='s'; path[2]=999; env.advance(0); eq(env.sent,{'e','n'})
  end)
  test('another rooms edited rule cannot change the compiled command stack',function()
    local D,env=ready(); save(D,101,'n',{'say original'}); queue(D); save(D,101,'n',{'say changed'})
    assert(D.walker.active); env.advance(0); eq(env.sent,{'e','say original'}); eq(D.getRule(101,'n').commands,{'say changed'})
  end)
  test('editing the current room cancels the queued stack before sending',function()
    local D,env=ready(); queue(D); save(D,100,'e',{'say new'}); settle(env); eq(D.walker.active,nil); eq(env.sent,{})
  end)
  test('unknown location and pending manual movement reject startup',function()
    local D,env=H.reset({mapperFirst=true}); local ok,err=D.walker.start({'e'},{101}); assert(not ok and err); eq(env.sent,{})
    D,env=ready(); D.move('e'); ok,err=D.walker.start({'e','n'},{101,102}); assert(not ok and err)
    settle(env); eq(env.sent,{'e'}); eq(D.walker.active,nil)
  end)
  test('the full route shape and every map link are validated before sending',function()
    local invalid={{nil,{101}},{{'e'},nil},{{'e','n'},{101}},{{[1]='e',[3]='n'},{101,102}},
      {{'e','n'},{[1]=101,[3]=102}},{{'e','say north'},{101,102}},{{'e','n'},{101,'invalid'}},
      {{'e','n'},{101,100}},{{'n'},{101}},{{'e'},{100}}}
    for _,args in ipairs(invalid) do
      local D,env=ready(); local ok,err=D.walker.start(args[1],args[2]); assert(not ok and err)
      settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
    end
  end)
  test('a future saved action with an active separator rejects the entire stack',function()
    local D,env=ready(); save(D,101,'n',{'say enter|north'}); env.separator='|'
    local ok,err=D.walker.start({'e','n'},{101,102}); assert(not ok and err); settle(env); eq(env.sent,{})
  end)
  test('an invalid later saved rule rejects the entire stack',function()
    local D,env=ready(); save(D,101,'n',{'north'}); D.rules['101'].n.commands={'north','east'}
    local ok,err=D.walker.start({'e','n'},{101,102}); assert(not ok and err); settle(env); eq(env.sent,{})
  end)
  test('empty route is a successful no-op',function()
    local D,env=ready(); assert(D.walker.start({},{})); settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
  end)
  test('locks on later exits or destinations reject the entire stack',function()
    for _,lock in ipairs({'exit','room'}) do
      local D,env=ready(); if lock=='exit' then env.exitLocks[101]={north=true} else env.roomLocks[102]=true end
      local ok,err=D.walker.start({'e','n'},{101,102}); assert(not ok and err); settle(env); eq(env.sent,{})
    end
  end)
  test('a changed separator before dispatch prevents the entire unsafe stack',function()
    local D,env=ready(); save(D,101,'n',{'say enter|north'}); queue(D); env.separator='|'
    settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
  end)
  test('map changes before deferred dispatch cancel before any command is sent',function()
    for _,change in ipairs({'exit','exit lock','room lock'}) do
      local D,env=ready(); queue(D)
      if change=='exit' then env.exits[101].north=999
      elseif change=='exit lock' then env.exitLocks[101]={north=true}
      else env.roomLocks[102]=true end
      settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
    end
  end)
  test('ordinary in and out commands share the immediate stack',function()
    local D,env=ready(); env.exits[100]['in']=101; env.exits[101]['out']=102
    dispatch(D,{'in','out'},{101,102}); eq(env.sent,{'in','out'}); finish(env); eq(D.walker.active,nil); eq(env.sent,{'in','out'})
  end)
  test('validated special exits are sent immediately alongside later commands',function()
    local D,env=ready(); env.specialExits[100]={[101]={['say Enter']='0'}}
    dispatch(D,{'say Enter','n'},{101,102}); eq(env.sent,{'say Enter','n'}); finish(env); eq(D.walker.active,nil)
  end)
  test('direction-named special exits bypass saved rules and mapper direction hints',function()
    local D,env=ready(); env.exits[100].east=103; env.specialExits[100]={[101]={e='0'}}
    save(D,100,'e',{'say saved-door'}); dispatch(D,{'e'},{101}); eq(env.sent,{'e'}); eq(#lotj.mapper.lastMoveDirs,0)
    env.room(101); settle(env); eq(lotj.mapper.processed[#lotj.mapper.processed].direction,false); eq(D.walker.active,nil)
  end)
  test('direction-looking special commands retain their exact stored case',function()
    local D,env=ready(); env.exits[100].east=103; env.specialExits[100]={[101]={EAST='0'}}
    dispatch(D,{'EAST'},{101}); eq(env.sent,{'EAST'})
  end)
  test('locked destinations and locked or unsafe special exits reject startup',function()
    for _,command in ipairs({'say enter','say enter\nlook','say enter;;north','say enter|north'}) do
      local D,env=ready(); env.specialExits[100]={[101]={[command]=command=='say enter' and '1' or '0'}}
      if command:find('|',1,true) then env.separator='|' end
      local ok,err=D.walker.start({command},{101}); assert(not ok and err); settle(env); eq(env.sent,{})
    end
    local D,env=ready(); env.specialExits[100]={[101]={['say enter']='0'}}; env.roomLocks[101]=true
    assert(not D.walker.start({'say enter'},{101})); settle(env); eq(env.sent,{})
  end)
  test('directions suppress duplicate echo while door actions remain visible',function()
    local D,env=ready(); save(D,100,'e',{'say enter'}); save(D,101,'n',{'open north','north'}); dispatch(D)
    eq(env.sendCalls,{{command='say enter',echo=true},{command='open north',echo=true},{command='north',echo=false}})
  end)
  test('GMCP-listener startup defers only until that event then sends the full stack',function()
    local D,env=ready({mapperFirst=false})
    registerAnonymousEventHandler('gmcp.Room.Info',function() if gmcp.Room.Info.vnum==101 then queue(D,{'n','w'},{102,103}); eq(env.sent,{}) end end)
    env.mapper(); env.emit('lotjUiLoaded'); env.room(100); settle(env); env.room(101)
    eq(env.sent,{}); eq(lotj.mapper.processed[#lotj.mapper.processed].direction,false)
    env.advance(0); eq(env.sent,{'n','w'}); eq(#lotj.mapper.lastMoveDirs,0)
    env.room(102); env.room(103); settle(env); eq(D.walker.active,nil)
  end)
  test('stop before queued dispatch sends nothing',function()
    local D,env=ready(); queue(D); assert(D.command('stop')); settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
    env.advance(20); eq(env.sent,{})
  end)
  test('an intervening command cancels the queued stack before dispatch',function()
    local D,env=ready(); queue(D); send('look'); settle(env); eq(env.sent,{'look'}); eq(D.walker.active,nil)
  end)
  test('source refreshes never send commands or consume future directions',function()
    local D,env=ready(); dispatch(D); local before=#lotj.mapper.processed; eq(#lotj.mapper.lastMoveDirs,0)
    for _=1,3 do env.room(100); settle(env) end
    eq(env.sent,{'e','n'}); eq(#lotj.mapper.processed,before); assert(D.walker.active)
  end)
  test('unexpected or invalid rooms stop passive tracking without another send',function()
    for _,room in ipairs({999,'unknown'}) do
      local D,env=ready(); dispatch(D); env.room(room); settle(env); eq(D.walker.active,nil); noLaterSends(env,{'e','n'})
    end
  end)
  test('timeout stops passive tracking without retrying any command',function()
    local D,env=ready(); dispatch(D); env.advance(4.9); assert(D.walker.active); env.advance(0.1); settle(env)
    eq(D.walker.active,nil); noLaterSends(env,{'e','n'})
  end)
  test('an already captured timeout cannot misreport the final confirmed arrival',function()
    local D,env=ready(); dispatch(D,{'e'},{101}); local callbacks={}
    for _,timer in pairs(env.timers) do if timer.at>env.now then callbacks[#callbacks+1]=timer.fn end end
    assert(#callbacks>0); env.room(101)
    for _,callback in ipairs(callbacks) do callback() end
    settle(env); eq(D.walker.active,nil); eq(env.sent,{'e'})
    local complete=false
    for _,message in ipairs(env.messages) do
      for _,fragment in ipairs(message) do
        if type(fragment)=='string' then
          assert(not fragment:find('within five seconds',1,true),'final arrival reported a timeout')
          if fragment:find('complete',1,true) then complete=true end
        end
      end
    end
    assert(complete,'normal completion should be reported')
  end)
  for _,hook in ipairs({'onFailure','onDark','onDisconnect'}) do
    test(hook..' stops tracking and never resends the stack',function()
      local D,env=ready(); dispatch(D); D[hook](); eq(D.walker.active,nil); noLaterSends(env,{'e','n'})
    end)
  end
  for _,method in ipairs({'move','raw'}) do
    test('manual '..method..' stops tracking without retracting the sent stack',function()
      local D,env=ready(); dispatch(D); D[method]('s'); eq(D.walker.active,nil); noLaterSends(env,{'e','n','s'})
    end)
  end
  test('doorway stop after dispatch sends nothing and cannot recall earlier commands',function()
    local D,env=ready(); dispatch(D); assert(D.command('stop')); eq(D.walker.active,nil)
    noLaterSends(env,{'e','n'}); D.command('stop'); eq(env.sent,{'e','n'})
  end)
  test('disable and package removal never resend a dispatched stack',function()
    for _,action in ipairs({'disable','uninstall','ui uninstall'}) do
      local D,env=ready(); dispatch(D)
      if action=='disable' then D.setEnabled(false) else env.emit('sysUninstallPackage',action=='uninstall' and 'lotj-doorways' or 'lotj-ui') end
      eq(D.walker.active,nil); noLaterSends(env,{'e','n'}); if action~='disable' then eq(doSpeedWalk,env.originalSpeedWalk) end
    end
  end)
  test('removing LotJ UI leaves manual Doorways usable',function()
    local D,env=ready(); dispatch(D); env.emit('sysUninstallPackage','lotj-ui'); env.room(101); settle(env)
    save(D,101,'n',{'say north'}); D.move('n'); eq(env.sent,{'e','n','say north'})
  end)
  test('replacing the mapper before dispatch cancels the queued stack',function()
    local D,env=ready(); queue(D); lotj.mapper={}; settle(env); eq(env.sent,{}); eq(D.walker.active,nil)
  end)
  test('a send exception stops the unsent remainder without retries',function()
    local D,env=ready(); local original=send
    send=function(command,show) if command=='n' then error('simulated transport failure') end; original(command,show) end
    dispatch(D,{'e','n','w'},{101,102,103}); eq(env.sent,{'e'}); eq(D.walker.active,nil)
    send=original; noLaterSends(env,{'e'}); eq(D.state.sending,0)
  end)
  test('synchronous cancellation during dispatch stops the unsent remainder',function()
    local D,env=ready(); local original=send
    send=function(command,show) original(command,show); if command=='e' then D.onFailure() end end
    dispatch(D); eq(env.sent,{'e'}); eq(D.walker.active,nil); send=original; noLaterSends(env,{'e'})
  end)
  test('obsolete callbacks cannot resend commands or stop a newer route',function()
    local D,env=ready(); dispatch(D); local callbacks={}; for _,timer in pairs(env.timers) do callbacks[#callbacks+1]=timer.fn end
    D.walker.stop('cancelled',true); env.room(100); settle(env); dispatch(D,{'n'},{103}); eq(env.sent,{'e','n','n'})
    for _,callback in ipairs(callbacks) do callback() end
    settle(env); eq(env.sent,{'e','n','n'}); assert(D.walker.active); env.room(103); settle(env); eq(D.walker.active,nil)
  end)
  test('disabled integration preserves the original burst and its arguments',function()
    local D,env=ready(); save(D,100,'e',{'say enter'}); D.setEnabled(false); standardRoute()
    local first,second=doSpeedWalk('forwarded',8); eq(first,'original-speedwalk-result'); eq(second,27)
    eq(env.stockWalkCalls,{{'forwarded',8}}); eq(env.sent,{'east','north'}); eq(D.walker.active,nil)
  end)
  test('absence of LotJ mapper leaves the original walking function untouched',function()
    local D,env=ready({mapperFirst=false}); D.walker.attach(); eq(doSpeedWalk,env.originalSpeedWalk)
  end)
  test('a mapper loaded later attaches the stack wrapper exactly once',function()
    local D,env=ready({mapperFirst=false}); env.mapper(); env.emit('lotjUiLoaded'); env.room(100); settle(env)
    local wrapper=doSpeedWalk; assert(wrapper~=env.originalSpeedWalk); D.walker.attach(); env.emit('lotjUiLoaded'); eq(doSpeedWalk,wrapper)
    standardRoute(); assert(doSpeedWalk()); env.advance(0); eq(env.sent,{'east','north'}); eq(#env.stockWalkCalls,0)
  end)
  test('mapper reload and cleanup preserve wrapper ownership',function()
    local D,env=ready(); local calls=0; local replacement=function(arg) calls=calls+1; return arg,'reloaded' end
    doSpeedWalk=replacement; env.emit('lotjUiLoaded'); assert(doSpeedWalk~=replacement); D.setEnabled(false)
    local first,second=doSpeedWalk('value'); eq(first,'value'); eq(second,'reloaded'); eq(calls,1)
    D.shutdown(); eq(doSpeedWalk,replacement); D.init(); local unrelated=function() end
    doSpeedWalk=unrelated; D.walker.detach(); eq(doSpeedWalk,unrelated)
  end)
  test('queue extraction preserves an unrelated canonical same-direction entry',function()
    local D,env=ready(); local unrelated=lotj.mapper.directionObjects.e; lotj.mapper.lastMoveDirs={unrelated}
    dispatch(D); eq(env.sent,{'e','n'}); eq(#lotj.mapper.lastMoveDirs,1); assert(lotj.mapper.lastMoveDirs[1]==unrelated)
  end)
  test('ambiguous mapper queue changes preserve entries and disable only synthetic hints',function()
    local D,env=ready(); local mapper=lotj.mapper
    registerAnonymousEventHandler('sysDataSendRequest',function(_,command)
      if command=='e' then table.insert(mapper.lastMoveDirs,mapper.directionObjects.s) end
    end)
    dispatch(D); eq(env.sent,{'e','n'}); eq(#mapper.lastMoveDirs,2)
    assert(mapper.lastMoveDirs[1]==mapper.directionObjects.e); assert(mapper.lastMoveDirs[2]==mapper.directionObjects.s)
    finish(env); eq(env.mapperRecords,{'e','n'}); eq(env.sent,{'e','n'})
  end)
  for _,mapperFirst in ipairs({true,false}) do
    local order=mapperFirst and 'mapper first' or 'Doorways first'
    test('one-way arrival attribution cannot drain future movements: '..order,function()
      local D,env=ready({mapperFirst=mapperFirst})
      if not mapperFirst then env.mapper(); env.emit('lotjUiLoaded'); env.room(100); settle(env) end
      env.mapperDrainQueue=true; save(D,100,'e',{'say enter'}); save(D,101,'n',{'open north','north'}); dispatch(D)
      eq(env.sent,{'say enter','open north','north'}); eq(#lotj.mapper.lastMoveDirs,0)
      local before=#lotj.mapper.processed; env.room(100); eq(#lotj.mapper.processed,before)
      gmcp.Room.Info={vnum=101,name='One-way room',exits={'north'}}; env.emit('gmcp.Room.Info')
      eq(lotj.mapper.processed[#lotj.mapper.processed].direction,'e'); eq(#lotj.mapper.lastMoveDirs,0)
      local count=#lotj.mapper.processed; env.room(101); eq(#lotj.mapper.processed,count)
      env.room(102); settle(env); eq(lotj.mapper.processed[#lotj.mapper.processed].direction,'n')
      eq(#lotj.mapper.lastMoveDirs,0); eq(D.walker.active,nil); eq(env.sent,{'say enter','open north','north'})
    end)
    test('repeated canonical directions are attributed once per arrival: '..order,function()
      local D,env=ready({mapperFirst=mapperFirst})
      if not mapperFirst then env.mapper(); env.emit('lotjUiLoaded'); env.room(100); settle(env) end
      env.exits[101].east=102; dispatch(D,{'e','e'},{101,102}); eq(env.sent,{'e','e'}); eq(#lotj.mapper.lastMoveDirs,0)
      local before=#lotj.mapper.processed; env.room(101); env.room(102); settle(env); eq(#lotj.mapper.processed,before+2)
      eq(lotj.mapper.processed[before+1].direction,'e'); eq(lotj.mapper.processed[before+2].direction,'e')
      eq(D.walker.active,nil); eq(env.sent,{'e','e'})
    end)
  end
end
