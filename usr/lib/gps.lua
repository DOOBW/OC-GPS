local component = require('component')
local computer = require('computer')
local modem, deb = nil, nil
if component.isAvailable('modem') then
  modem = component.modem
end
if component.isAvailable('debug') then
  deb = component.debug
end

local floor, sqrt, abs = math.floor, math.sqrt, math.abs

local CHANNEL_GPS, gps = 65534, {}

local function round(v, m)
  m = m or 1.0
  return {
    x = floor((v.x+(m*0.5))/m)*m,
    y = floor((v.y+(m*0.5))/m)*m,
    z = floor((v.z+(m*0.5))/m)*m
  }
end

local function len(v)
  return sqrt(v.x^2 + v.y^2 + v.z^2)
end

local function cross(v, b)
  return {x = v.y*b.z-v.z*b.y, y = v.z*b.x-v.x*b.z, z = v.x*b.y-v.y*b.x}
end

local function dot(v, b)
  return v.x*b.x + v.y*b.y + v.z*b.z
end

local function add(v, b)
  return {x = v.x+b.x, y = v.y+b.y, z = v.z+b.z}
end

local function sub(v, b)
  return {x = v.x-b.x, y = v.y-b.y, z = v.z-b.z}
end

local function mul(v, m)
  return {x = v.x*m, y = v.y*m, z = v.z*m}
end

local function norm(v)
  return mul(v, 1/len(v))
end

local function trilaterate(A, B, C)
  local a2b = {x = B.x-A.x, y = B.y-A.y, z = B.z-A.z}
  local a2c = {x = C.x-A.x, y = C.y-A.y, z = C.z-A.z}
  if abs(dot(norm(a2b), norm(a2c))) > 0.999 then
    return nil
  end
  local d = len(a2b)
  local ex = norm(a2b)
  local i = dot(ex, a2c)
  local ey = norm(sub(mul(ex, i), a2c))
  local j = dot(ey, a2c)
  local ez = cross(ex, ey)
  local r1 = A.d
  local r2 = B.d
  local r3 = C.d
  local x = (r1^2 - r2^2 + d^2) / (2*d)
  local y = (r1^2 - r3^2 - x^2 + (x-i)^2 + j^2) / (2*j)
  local result = add(A, add(mul(ex, x), mul(ey, y)))
  local zSquared = r1^2 - x^2 - y^2
  if zSquared > 0 then
    local z = sqrt( zSquared )
    local result1 = add(result, mul(ez, z))
    local result2 = add(result, mul(ez, z))
    local rounded1, rounded2 = round(result1, 0.01), round(result2, 0.01)
    if rounded1.x ~= rounded2.x or
       rounded1.y ~= rounded2.y or
       rounded1.z ~= rounded2.z then
      return rounded1, rounded2
    else
      return rounded1
    end
  end
  return round(result, 0.01)
end

local function narrow(p1, p2, fix)
  local dist1 = abs(len(sub(p1, fix)) - fix.d)
  local dist2 = abs(len(sub(p2, fix)) - fix.d)
  if abs(dist1 - dist2) < 0.01 then
    return p1, p2
  elseif dist1 < dist2 then
    return round(p1, 0.01)
  else
    return round(p2, 0.01)
  end
end

function gps.locate(TIMEOUT, DEBUG)
  if deb then
    local X, Y, Z = floor(deb.getX()), floor(deb.getY()), floor(deb.getZ())
    if DEBUG then
      print('Position obtained by the magic '..X..', '..Y..', '..Z)
    end
    return X, Y, Z
  end
  if not modem or not modem.isWireless() then
    if DEBUG then
      print('No wireless modem attached')
    end
    return nil
  end
  if DEBUG then
    print('Finding position...')
  end
  modem.open(CHANNEL_GPS)
  modem.setStrength(math.huge)
  modem.broadcast(CHANNEL_GPS, 'PING')
  local fixes = {}
  local pos1, pos2 = nil, nil
  TIMEOUT = TIMEOUT or 2
  local deadline = computer.uptime()+TIMEOUT
  repeat
    local event = {computer.pullSignal(deadline-computer.uptime())}
    if event[1] == 'modem_message' and event[6] == 'GPS' then
      local fix = {x = event[7], y = event[8], z = event[9], d = event[5]}
      if DEBUG then
        print(fix.d .. ' blocks from ' .. fix.x .. ', ' .. fix.y .. ', ' .. fix.z)
      end
      if fix.d == 0 then
        pos1, pos2 = {fix.x, fix.y, fix.z}, nil
      else
        table.insert(fixes, fix)
        if #fixes >= 3 then
          if not pos1 then
            pos1, pos2 = trilaterate(fixes[1], fixes[2], fixes[#fixes])
          else
            pos1, pos2 = narrow(pos1, pos2, fixes[#fixes]) --fixes[math.random(1, #fixes)]
          end
        end        
      end
      if pos1 and not pos2 then
        break
      end
    end
  until computer.uptime() >= deadline
  modem.close(CHANNEL_GPS)
  if pos1 and pos2 then
    if DEBUG then
      print('Ambiguous position')
      print('Could be '..pos1.x..', '..pos1.y..', '..pos1.z..
            ' or '..pos2.x..', '..pos2.y..', '..pos2.z)
    end
    return nil
  elseif pos1 then
    if DEBUG then
      print('Position is '..pos1.x..', '..pos1.y..', '..pos1.z)
    end
    return pos1.x, pos1.y, pos1.z
  else
    if DEBUG then
      print('Could not determine position')
    end
    return nil
  end
end

return gps
