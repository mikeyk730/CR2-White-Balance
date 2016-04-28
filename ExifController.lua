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
local error = error

setfenv(1, P)




--move to io package
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




local Conversion = {
   Convert = function(i, map)
      local v = map[i]
      if v then
         return v
      else
         error("Couldn't convert input '"..i.."'")
      end
   end
}

Conversion.WhiteBalance = {
   FromString = {
      Auto=0,
      Daylight=1,
      Cloudy=2,
      Tungsten=3,
      Fluorescent=4,
      Flash=5,
      Shade=8,
   },
   ToString = {
      [0]="Auto",
      [1]="Daylight",
      [2]="Cloudy",
      [3]="Tungsten",
      [4]="Fluorescent",
      [5]="Flash",
      [8]="Shade",
   }
}

local function white_balance_to_string(s)
   return Conversion.Convert(s, Conversion.WhiteBalance.ToString)
end

local function white_balance_from_string(file, addr, s)
   local i = Conversion.Convert(s, Conversion.WhiteBalance.FromString)
   save_1_short(file, addr, i)
   return i
end

--todo: self??
local function levels_from_string(file, addr, s)
   --todo: validate
   local i1,i2,i3,i4 = string.match(s, "^(%d+) (%d+) (%d+) (%d+)$")
   save_4_shorts(file, addr, i1, i2, i3, i4)
   return {i1,i2,i3,i4}
end

local function levels_to_string(a)
   return string.format(string.rep("%d ", 4), a[1], a[2], a[3], a[4])
end

local function color_temp_from_string(file, addr, s)
   --todo:validate
   local i = tonumber(s) or error("failed to parse "..s)
   save_1_short(file, addr, i)
   return i
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
      [7] = {   name="WhiteBalance",            count=1,   setter=white_balance_from_string,   getter=white_balance_to_string },
   }
}

local ColorBalance4 = {
   name = "ColorBalance4",
   values = {
      [63] = {  name="WB_RGGBLevelsAsShot",     count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [67] = {  name="ColorTempAsShot",         count=1,   setter=color_temp_from_string                                      },
      [68] = {  name="WB_RGGBLevelsAuto",       count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [72] = {  name="ColorTempAuto",           count=1,   setter=color_temp_from_string                                      },
      [73] = {  name="WB_RGGBLevelsMeasured",   count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [77] = {  name="ColorTempMeasured",       count=1,   setter=color_temp_from_string                                      },
      [83] = {  name="WB_RGGBLevelsDaylight",   count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [87] = {  name="ColorTempDaylight",       count=1,   setter=color_temp_from_string                                      },
      [88] = {  name="WB_RGGBLevelsShade",      count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [92] = {  name="ColorTempShade",          count=1,   setter=color_temp_from_string                                      },
      [93] = {  name="WB_RGGBLevelsCloudy",     count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [97] = {  name="ColorTempCloudy",         count=1,   setter=color_temp_from_string                                      },
      [98] = {  name="WB_RGGBLevelsTungsten",   count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [102] = { name="ColorTempTungsten",       count=1,   setter=color_temp_from_string                                      },
      [103] = { name="WB_RGGBLevelsFluorescent",count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [107] = { name="ColorTempFluorescent",    count=1,   setter=color_temp_from_string                                      },
      [108] = { name="WB_RGGBLevelsKelvin",     count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [112] = { name="ColorTempKelvin",         count=1,   setter=color_temp_from_string                                      },
      [113] = { name="WB_RGGBLevelsFlash",      count=4,   setter=levels_from_string,          getter=levels_to_string        },
      [117] = { name="ColorTempFlash",          count=1,   setter=color_temp_from_string                                      },
   }
}




SettableMetadata = {}
function SettableMetadata:new(name, file, addr, value, setter, getter)
   local o = {
      name = name,
      file = file,
      address = addr,
      value = value, 
      setter = setter,
      getter = getter
   }

   setmetatable(o, self)
   self.__index = self
   return o
end

function SettableMetadata:SetValue(s)
   local v = self.setter(self.file, self.address, s)
   self.value = v
end

function SettableMetadata:GetValue()
   if self.getter then 
      return self.getter(self.value)
   else
      return self.value
   end
end




I16Array = {}
function I16Array:new(name, file, addr, count)
   --print(string.format("0x%x %s", addr, name))   
   local o = { file=file, address=addr, size=count, array={}}
   o.file:seek("set", o.address)
   local bytes = o.file:read(count*2)
   for i = 1,count do
      local offset = addr + 2 * (i - 1)
      local i16 = bytes_to_int16(bytes:byte(2*i-1,2*i))
      table.insert(o.array, {address=offset, value=i16})
   end

   setmetatable(o, self)
   self.__index = self
   return o
end

function I16Array:get_settable_entries(map, entries)
    for i,tag in pairs(map.values) do

      local count = tag.count or 1
      local addr = self.array[i+1].address
      local value
      if count == 4 then
         value = {self.array[i+1].value, self.array[i+2].value, 
                  self.array[i+3].value, self.array[i+4].value }
      elseif count == 1 then
         value = self.array[i+1].value
      end

      entries[tag.name] = SettableMetadata:new(tag.name, self.file, addr, value, tag.setter, tag.getter)
   end
end




IfdTable = {}
function IfdTable:new(name, file, addr, map)
   --print(string.format("0x%x %s", addr, name))
   local o = { file=file, address=addr, entries = {} }
   o.file:seek("set", o.address)
   local entries = bytes_to_int16(o.file:read(2):byte(1,2))
   for i = 1,entries do
      local offset = o.file:seek();
      local bytes = o.file:read(12)
      local tag = bytes_to_int16(bytes:byte(1,2))
      local typ = bytes_to_int16(bytes:byte(3,4))
      local num = bytes_to_int32(bytes:byte(5,8))
      local val = bytes_to_int32(bytes:byte(9,12))
      o.entries[tag] = {tag_type=typ, count=num, value=val, address=addr}
   end
   o.next_ifd = bytes_to_int32(o.file:read(4):byte(1,4))

   setmetatable(o, self)
   self.__index = self
   return o
end

function IfdTable:LoadSubTable(name, tag, map)
   local offset = self.entries[tag].value
   return IfdTable:new(name, self.file, offset, map)
end

function IfdTable:LoadSubArray(name, tag, map)
   local entry = self.entries[tag];
   return I16Array:new(name, self.file, entry.value, entry.count)
end




Cr2File = {}
function Cr2File:new(filename)
   local o = {}

   o.file = io.open(filename, "r+b")

   o.file:seek("set", 4)
   local ifd0_offset = bytes_to_int32(o.file:read(4):byte(1,4))
   local ifd_0 = IfdTable:new("IFD0", o.file, ifd0_offset)
   local ifd_exif = ifd_0:LoadSubTable("Exif", 0x8769)
   local ifd_canon_maker_notes = ifd_exif:LoadSubTable("MakerNotes", 0x927c)
   local array_color_balance_4 = ifd_canon_maker_notes:LoadSubArray("ColorBalance4",0x4001)
   local array_shot_info = ifd_canon_maker_notes:LoadSubArray("ShotInfo", 0x04)

   o.metadata = {}
   array_color_balance_4:get_settable_entries(ColorBalance4, o.metadata)
   array_shot_info:get_settable_entries(CanonShotInfo, o.metadata)

   setmetatable(o, self)
   self.__index = self
   return o
end

function Cr2File:PrintEntries()
   for k,v in pairs(self.metadata) do
      print(string.format("0x%08x:  %-25s %-25s", v.address, k, v:GetValue()))
   end
end

function Cr2File:GetValue(tag)
   local e = self.metadata[tag]
   if e then 
      return e:GetValue()
   end
   error("Couldn't get value")
end

function Cr2File:SetValue(tag,s)
   local e = self.metadata[tag]
   if e then 
      e:SetValue(s)
   else
      error("Couldn't set value")
   end
end

function Cr2File:close()
   self.file:close()
end




local function process_photo(filename)

   local cr2 = Cr2File:new(filename)

   cr2:PrintEntries()

   print (cr2:GetValue('WB_RGGBLevelsAuto'))
   print (cr2:GetValue('ColorTempAuto'))

   cr2:SetValue('WB_RGGBLevelsAsShot', '1 2 3 4')
   cr2:SetValue('WhiteBalance', 'Shade')
   cr2:SetValue('ColorTempAsShot', '4444')

   print (cr2:GetValue('WhiteBalance'))
   print (cr2:GetValue('WB_RGGBLevelsAsShot'))
   print (cr2:GetValue('ColorTempAsShot'))

   cr2:close()
end





--local filename = '20140715-IMG_6900o.CR2'
local filename = 'IMG_4576.CR2'
process_photo(filename)
