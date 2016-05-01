--todo:only run if cannon 60d
BinaryIo = {}

BinaryIo.Int16ToBytes = function(x)
    local b1=x%256  x=(x-x%256)/256
    local b2=x%256  x=(x-x%256)/256
    return string.char(b1,b2)
end

BinaryIo.BytesToInt32 = function(b1, b2, b3, b4)
   return b1 + b2*256 + b3*65536 + b4*16777216
end

BinaryIo.BytesToInt16 = function(b1, b2)
   return b1 + b2*256
end

BinaryIo.ReadInt16 = function(file)
   return BinaryIo.BytesToInt16(file:read(2):byte(1,2))
end

BinaryIo.ReadInt32 = function(file)
   return BinaryIo.BytesToInt32(file:read(4):byte(1,4))
end

BinaryIo.WriteInt16 = function(file, i)
   file:write(BinaryIo.Int16ToBytes(i))
end

BinaryIo.WriteInt16Array = function(file, a)
   for i,v in ipairs(a) do
      file:write(BinaryIo.Int16ToBytes(v))
   end
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
   logger:trace("Writing WhiteBalance", i)

   file:seek("set", addr)
   BinaryIo.WriteInt16(file, i)
   return i
end

local function levels_from_string(file, addr, s)
   local i1,i2,i3,i4 = string.match(s, "^%s*(%d+) (%d+) (%d+) (%d+)%s*$")
   assert(i1)
   assert(i2)
   assert(i3)
   assert(i4)
   logger:trace("Writing Levels", i1, i2, i3, i4)

   file:seek("set", addr)
   BinaryIo.WriteInt16Array(file, {i1, i2, i3, i4})
   return {i1,i2,i3,i4}
end

local function levels_to_string(a)
   return string.format(string.rep("%d ", 4), a[1], a[2], a[3], a[4])
end

local function color_temp_from_string(file, addr, s)
   local i = tonumber(s) or error("failed to parse "..s)
   logger:trace("Writing Temperature", i)

   file:seek("set", addr)
   BinaryIo.WriteInt16(file, i)
   return i
end




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




MetadataEntry = {}
function MetadataEntry:Create(name, file, addr, value, setter, getter)
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

function MetadataEntry:SetValue(s)
   local v = self.setter(self.file, self.address, s)
   self.value = v
end

function MetadataEntry:GetValue()
   if self.getter then 
      return self.getter(self.value)
   else
      return self.value
   end
end




I16Array = {}
function I16Array:Create(name, file, addr, count)
   --print(string.format("0x%x %s", addr, name))   
   local o = { file=file, address=addr, size=count, array={}}
   o.file:seek("set", o.address)
   local bytes = o.file:read(count*2)
   for i = 1,count do
      local offset = addr + 2 * (i - 1)
      local i16 = BinaryIo.BytesToInt16(bytes:byte(2*i-1,2*i))
      table.insert(o.array, {address=offset, value=i16})
   end

   setmetatable(o, self)
   self.__index = self
   return o
end

function I16Array:GetMetadataInterface(map, entries)
   for offset,tag in pairs(map.values) do      
      local i = offset + 1

      local addr = self.array[i].address

      local count = tag.count or 1
      local value
      if count == 1 then
         value = self.array[i].value
      elseif count > 1 then
         value = {}
         for j=i,i+count-1 do
            table.insert(value, self.array[j].value)
         end
      else
         error("Unknown value for count")
      end

      entries[tag.name] = MetadataEntry:Create(tag.name, self.file, addr, value, tag.setter, tag.getter)
   end
end




IfdTable = {}
function IfdTable:Create(name, file, addr, map)
   --print(string.format("0x%x %s", addr, name))
   local o = { file=file, address=addr, entries = {} }
   o.file:seek("set", o.address)
   local entries = BinaryIo.ReadInt16(o.file)
   for i = 1,entries do
      local offset = o.file:seek();
      local bytes = o.file:read(12)
      local tag = BinaryIo.BytesToInt16(bytes:byte(1,2))
      local typ = BinaryIo.BytesToInt16(bytes:byte(3,4))
      local num = BinaryIo.BytesToInt32(bytes:byte(5,8))
      local val = BinaryIo.BytesToInt32(bytes:byte(9,12))
      o.entries[tag] = {tag_type=typ, count=num, value=val, address=addr}
   end
   o.next_ifd = BinaryIo.ReadInt32(o.file)

   setmetatable(o, self)
   self.__index = self
   return o
end

function IfdTable:LoadSubTable(name, tag, map)
   local offset = self.entries[tag].value
   return IfdTable:Create(name, self.file, offset, map)
end

function IfdTable:LoadSubArray(name, tag, map)
   local entry = self.entries[tag];
   return I16Array:Create(name, self.file, entry.value, entry.count)
end




Cr2File = {}
function Cr2File:Create(filename)
   local o = { metadata={} }

   o.file = assert(io.open(filename, "r+b"))
   o.file:seek("set", 4)
   local ifd0_offset = BinaryIo.ReadInt32(o.file)

   local ifd_0 = IfdTable:Create("IFD0", o.file, ifd0_offset)
   local ifd_exif = ifd_0:LoadSubTable("Exif", 0x8769)
   local ifd_canon_maker_notes = ifd_exif:LoadSubTable("MakerNotes", 0x927c)
   local array_color_balance_4 = ifd_canon_maker_notes:LoadSubArray("ColorBalance4",0x4001)
   local array_shot_info = ifd_canon_maker_notes:LoadSubArray("ShotInfo", 0x04)
   
   array_color_balance_4:GetMetadataInterface(ColorBalance4, o.metadata)
   array_shot_info:GetMetadataInterface(CanonShotInfo, o.metadata)

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

function Cr2File:Close()
   self.file:close()
end
