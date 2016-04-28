require "constants"

local P = {}
complex = P

local io = io
local setmetatable = setmetatable
local table = table
local string = string
local pairs = pairs
local print = print
local tonumber = tonumber

setfenv(1, P)

local function int16_to_bytes(x)
    local b1=x%256  x=(x-x%256)/256
    local b2=x%256  x=(x-x%256)/256
    return string.char(b1,b2)
end

local function bytes_to_int32(b1, b2, b3, b4)
   return b1 + b2*256 + b3*65536 + b4*16777216
end

local function bytes_to_int16(b1, b2)
   return b1 + b2*256
end

local function save_1_short(file, addr, i)
   file:seek("set", addr)
   file:write(int16_to_bytes(i))
end

local function save_4_shorts(file, addr, i1, i2, i3, i4)
   file:seek("set", addr)
   file:write(int16_to_bytes(i1))
   file:write(int16_to_bytes(i2))
   file:write(int16_to_bytes(i3))
   file:write(int16_to_bytes(i4))
end


local function white_balance_from_string(file, addr, s)
   local map = {
      Auto=0,
      Daylight=1,
      Shade=8,
      Cloudy=2,
      Tungsten=3,
      Fluorescent=4,
      Flash=5,
   }
   --todo:validate
   local i = map[s] 
   save_1_short(file, addr, i)
end


--Entry = {tag, tag_type, count, address, raw_value, display_value }
--local function Entry:writeValue(file, s)
--   return self.setter(file, self.address, s)
--end
--local function Entry:readValue()
--   return self.getter(self.raw_value)
--end



--todo: self??
local function levels_from_string(file, addr, s)
   --todo: validate
   local i1,i2,i3,i4 = string.match(s, "^(%d+) (%d+) (%d+) (%d+)$")
   save_4_shorts(file, addr, i1, i2, i3, i4)
end

local function color_temp_from_string(file, addr, s)
   --todo:validate
   local i = tonumber(s) or error("failed to parse "..s)
   save_1_short(file, addr, i)
end




local IFD0 = {
   name = "IFD0",
   values = {
      [0x8769] = {  name="ExifOffset" },
   }
}

local Exif = {
   name = "Exif",
   values = {
      [0x927c] = {  name="MakerNoteCanon" },
   }   
}

local MakerNoteCanon = {
   name = "MakerNoteCanon",
   values = {
      [0x04] = {  name="CanonShotInfo" },
      [0x4001] = {  name="ColorData4" },
   }   
}

local CanonShotInfo = {
   name = "CanonShotInfo",
   values = {
      [7] = {   name="WhiteBalance",                      setter=white_balance_from_string },
   }
}

local ColorBalance4 = {
   name = "ColorBalance4",
   values = {
      [63] = {  name="WB_RGGBLevelsAsShot",     count=4,  setter=levels_from_string        },
      [67] = {  name="ColorTempAsShot",                   setter=color_temp_from_string    },
      [68] = {  name="WB_RGGBLevelsAuto",       count=4 },
      [72] = {  name="ColorTempAuto",                   },
      [73] = {  name="WB_RGGBLevelsMeasured",   count=4 },
      [77] = {  name="ColorTempMeasured",               },
      [83] = {  name="WB_RGGBLevelsDaylight",   count=4 },
      [87] = {  name="ColorTempDaylight",               },
      [88] = {  name="WB_RGGBLevelsShade",      count=4 },
      [92] = {  name="ColorTempShade",                  },
      [93] = {  name="WB_RGGBLevelsCloudy",     count=4 },
      [97] = {  name="ColorTempCloudy",                 },
      [98] = {  name="WB_RGGBLevelsTungsten",   count=4 },
      [102] = { name="ColorTempTungsten",               },
      [103] = { name="WB_RGGBLevelsFluorescent",count=4 },
      [107] = { name="ColorTempFluorescent",            },
      [108] = { name="WB_RGGBLevelsKelvin",     count=4 },
      [112] = { name="ColorTempKelvin",                 },
      [113] = { name="WB_RGGBLevelsFlash",      count=4 },
      [117] = { name="ColorTempFlash",                  },
   }
}

local function get_label(key, map)
   return string.format("[0x%04x]", key)
end





I16Array = {}

function I16Array:new(name, file, addr, count)
   --print(string.format("0x%x %s", addr, name))   
   local o = { address=addr, size=count, array={}}
   file:seek("set", addr)
   local bytes = file:read(count*2)
   for i = 1,count do
      local offset = addr + 2 * (i - 1)
      local i16 = bytes_to_int16(bytes:byte(2*i-1,2*i))
      table.insert(o.array, {address=offset, value=i16})
      --print(string.format("0x%08x: %-15s %-35s               %s", offset, name, get_label(i), i16))
   end


   setmetatable(o, self)
   self.__index = self
   return o
end

function I16Array:get_entries(map, entries)
    for i,tag in pairs(map.values) do

      local count = tag.count or 1
      local setter = tag.setter
      local addr = self.array[i+1].address
      local value
      if count == 4 then
         value = string.format(string.rep("%d ", 4), self.array[i+1].value, self.array[i+2].value, 
                               self.array[i+3].value, self.array[i+4].value)
      elseif count == 1 then
         value = string.format("%d", self.array[i+1].value)
      end

      entries[tag.name] = { 
         address = addr, 
         count = count, 
         value = value, 
         setter = setter
      }
      --print(string.format("0x%08x: %-15s %-35s               %s", addr, map.name, get_label(i).." "..tag.name, value))
   end
end





IfdTable = {}
function IfdTable:new(name, file, addr, map)
   --print(string.format("0x%x %s", addr, name))
   local o = { entries = {} }
   file:seek("set", addr)
   local entries = bytes_to_int16(file:read(2):byte(1,2))
   for i = 1,entries do
      local offset = file:seek();
      local bytes = file:read(12)
      local tag = bytes_to_int16(bytes:byte(1,2))
      local typ = bytes_to_int16(bytes:byte(3,4))
      local num = bytes_to_int32(bytes:byte(5,8))
      local val = bytes_to_int32(bytes:byte(9,12))
      o.entries[tag] = {tag_type=typ, count=num, value=val, address=addr}
      --print(string.format("0x%08x: %-15s %-35s %4d %8d 0x%x", offset, name, get_label(tag, map), typ, num, val))
   end
   o.next_ifd = bytes_to_int32(file:read(4):byte(1,4))

   setmetatable(o, self)
   self.__index = self
   return o
end

function IfdTable:LoadTable(name, file, tag, map)
   local offset = self.entries[tag].value
   return IfdTable:new(name, file, offset, map)
end

function IfdTable:LoadArray(name, file, tag, map)
   local entry = self.entries[tag];
   return I16Array:new(name, file, entry.value, entry.count)

end


Cr2File = {}
function Cr2File:new(filename)
   o = {}

   o.file = io.open(filename, "r+b")

   o.file:seek("set", 4)
   local ifd0_offset = bytes_to_int32(o.file:read(4):byte(1,4))
   o.ifd_0 = IfdTable:new("IFD0", o.file, ifd0_offset)
   o.ifd_exif = o.ifd_0:LoadTable("Exif", o.file, 0x8769)
   o.ifd_canon_maker_notes = o.ifd_exif:LoadTable("MakerNotes", o.file, 0x927c)
   o.array_color_balance_4 = o.ifd_canon_maker_notes:LoadArray("ColorBalance4", o.file, 0x4001)
   o.array_shot_info = o.ifd_canon_maker_notes:LoadArray("ShotInfo", o.file, 0x04)

   o.entries = {}
   o.array_color_balance_4:get_entries(ColorBalance4, o.entries)
   o.array_shot_info:get_entries(CanonShotInfo, o.entries)


   setmetatable(o, self)
   self.__index = self
   return o
end

function Cr2File:PrintEntries()
   for k,v in pairs(self.entries) do
      print(string.format("0x%08x: %dx  %-25s %-25s", v.address, v.count, k, v.value))
   end
end

function Cr2File:GetValue(tag)
   local e = self.entries[tag]
   if e then 
      return e.value
   end
   return nil
end

function Cr2File:SetValue(tag,s)
   local e = self.entries[tag]
   e.setter(self.file, e.address, s)
end

function Cr2File:close()
   self.file:close()
end

local function process_photo(filename)

   local cr2 = Cr2File:new(filename)

   cr2:PrintEntries()

   print (cr2:GetValue('WhiteBalance'))
   print (cr2:GetValue('WB_RGGBLevelsAsShot'))
   print (cr2:GetValue('ColorTempAsShot'))

   cr2:SetValue('WB_RGGBLevelsAsShot', '1 2 3 4')
   cr2:SetValue('WhiteBalance', 'Shade')
   cr2:SetValue('ColorTempAsShot', '4444')

   cr2:close()
end

--local filename = '20140715-IMG_6900o.CR2'
local filename = 'IMG_4576.CR2'
process_photo(filename)

Cr2ExifController = {
   new = new,
   get_value = get_value,
   set_value = set_value
}
