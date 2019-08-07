local args = {...}
package.loaded.gps = nil
local gps = require('gps')
local component = require('component')
local CHANNEL_GPS = 65534
local X, Y, Z = nil, nil, nil
local command = args[1]

local firmware = [[CHANNEL_GPS = 65534
X, Y, Z = nil, nil, nil

local function add_component(name)
  name = component.list(name)()
  if name then
    return assert(component.proxy(name))
  end
end

local modem = add_component('modem')
local eeprom = add_component('eeprom')
local deb = add_component('debug')

if not modem or not modem.isWireless() then error('No wireless modem attached', 0) end

local floor, sqrt, abs = math.floor, math.sqrt, math.abs
local A1, A4, A5, C5, D5, E6 = 55, 440, 880, 523.251, 587.33, 1318.51
local label = load(eeprom.getLabel())
if label then 
  label()
end
modem.open(CHANNEL_GPS)
modem.setWakeMessage('PING')
modem.setStrength(math.huge)

local function round(v, m)
  return {x = floor((v.x+(m*0.5))/m)*m, y = floor((v.y+(m*0.5))/m)*m, z = floor((v.z+(m*0.5))/m)*m}
end

local function cross(v, b)
  return {x = v.y*b.z-v.z*b.y, y = v.z*b.x-v.x*b.z, z = v.x*b.y-v.y*b.x}
end

local function len(v) return sqrt(v.x^2+v.y^2+v.z^2) end
local function dot(v, b) return v.x*b.x+v.y*b.y+v.z*b.z end
local function add(v, b) return {x=v.x+b.x, y=v.y+b.y, z=v.z+b.z} end
local function sub(v, b) return {x=v.x-b.x, y=v.y-b.y, z=v.z-b.z} end
local function mul(v, m) return {x=v.x*m, y=v.y*m, z=v.z*m} end
local function norm(v) return mul(v, 1/len(v)) end

local function trilaterate(A, B, C)
  local a2b = {x=B.x-A.x, y=B.y-A.y, z=B.z-A.z}
  local a2c = {x=C.x-A.x, y=C.y-A.y, z=C.z-A.z}
  if abs(dot(norm(a2b), norm(a2c))) > 0.999 then
    return nil
  end
  local d, ex = len(a2b), norm(a2b)
  local i = dot(ex, a2c)
  local ey = norm(sub(mul(ex, i), a2c))
  local j, ez = dot(ey, a2c), cross(ex, ey)
  local r1, r2, r3 = A.d, B.d, C.d
  local x = (r1^2 - r2^2 + d^2) / (2*d)
  local y = (r1^2 - r3^2 - x^2 + (x-i)^2 + j^2) / (2*j)
  local result = add(A, add(mul(ex, x), mul(ey, y)))
  local zSquared = r1^2 - x^2 - y^2
  if zSquared > 0 then
    local z = sqrt( zSquared )
    local result1 = add(result, mul(ez, z))
    local result2 = add(result, mul(ez, z))
    local rnd1, rnd2 = round(result1, 0.01), round(result2, 0.01)
    if rnd1.x ~= rnd2.x or rnd1.y ~= rnd2.y or rnd1.z ~= rnd2.z then
      return rnd1, rnd2
    else
      return rnd1
    end
  end
  return round(result, 0.01)
end

local function narrow(p1, p2, fix)
  local d1 = abs(len(sub(p1, fix))-fix.d)
  local d2 = abs(len(sub(p2, fix))-fix.d)
  if abs(d1-d2) < 0.01 then
    return p1, p2
  elseif d1 < d2 then
    return round(p1, 0.01)
  else
    return round(p2, 0.01)
  end
end

local function locate()
  if deb then X, Y, Z = floor(deb.getX()), floor(deb.getY()), floor(deb.getZ()) return true end
  modem.broadcast(CHANNEL_GPS, 'PING')
  local fixes = {}
  local pos1, pos2 = nil, nil
  local deadline = computer.uptime()+2
  repeat
    local event = {computer.pullSignal(deadline-computer.uptime())}
    if event[1] == 'modem_message' and event[6] == 'GPS' then
      local fix = {x = event[7], y = event[8], z = event[9], d = event[5]}
      if fix.d == 0 then
        pos1, pos2 = {fix.x, fix.y, fix.z}, nil
      else
        table.insert(fixes, fix)
        if #fixes >= 3 then
          if not pos1 then
            pos1, pos2 = trilaterate(fixes[1], fixes[2], fixes[#fixes])
          else
            pos1, pos2 = narrow(pos1, pos2, fixes[#fixes])
          end
        end        
      end
      if pos1 and not pos2 then break end
    end
  until computer.uptime() >= deadline
  modem.close(CHANNEL_GPS)
  if pos1 and pos2 then
    return nil
  elseif pos1 then
    X, Y, Z = pos1.x, pos1.y, pos1.z
    return true
  else
    return nil
  end
end

if not X then
  locate()
  if not X then
    computer.beep(A1, 0.3) computer.beep(E6, 0.05) computer.beep(A5, 0.2)
    error('Could not determine position', 0)
    computer.shutdown()
  else
    if not deb then
      computer.beep(A4, 0.2) computer.beep(C5, 0.3) computer.beep(D5, 0.2)
      eeprom.setLabel('X,Y,Z='..X..','..Y..','..Z)
    end
  end
end

modem.broadcast(CHANNEL_GPS, 'GPS', X, Y, Z)
computer.shutdown()]]

local function usage()
  print('Usages:')
  print('gps locate')
  print('gps host [<x> <y> <z>]')
  print('gps flash [<x> <y> <z>]')
  os.exit()
end

if command == 'locate' then
  gps.locate(2, true)
elseif command == 'host' then
  if #args >= 4 then
    X = tonumber(args[2])
    Y = tonumber(args[3])
    Z = tonumber(args[4])
    if X == nil or Y == nil or Z == nil then
      usage()
    end
    print('Position is '..X..', '..Y..', '..Z)
  else
    X, Y, Z = gps.locate(2, true)
    if X == nil then
      print('Run \"gps host <x> <y> <z>\" to set position manually')
      os.exit()
    end
  end
  local event = require('event')
  local modem = component.modem
  if modem.isWireless() then
    print('Serving GPS requests')
  else
    print('No modem attached')
    os.exit()
  end
  local term = require('term')
  modem.open(CHANNEL_GPS)
  local served = 0
  while true do
    local e = {event.pull('modem_message')}
    if e[6] == 'PING' then
      modem.broadcast(CHANNEL_GPS, 'GPS', X, Y, Z)
      served = served + 1
      if served > 1 then
        local x, y = term.getCursor()
        term.setCursor(x, y-1)
      end
      print(served..' GPS Requests served')
    end
  end
elseif command == 'flash' then
  local eeprom = component.eeprom
  if #args >= 4 then
    X = tonumber(args[2])
    Y = tonumber(args[3])
    Z = tonumber(args[4])
    if X == nil or Y == nil or Z == nil then
      usage()
    end
    eeprom.setLabel('X,Y,Z='..X..','..Y..','..Z)
  else
    eeprom.setLabel('GPS SATELLITE')
  end
  eeprom.set(firmware)
else
  usage()
end
