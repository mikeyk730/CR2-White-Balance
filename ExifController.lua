require "constants"

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
      [7] = {   name="WhiteBalance" },
   }
}

local ColorBalance4 = {
   name = "ColorBalance4",
   values = {
      [63] = {  name="WB_RGGBLevelsAsShot",     count=4 },
      [67] = {  name="ColorTempAsShot",                 },
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

function int16_to_bytes(x)
    local b1=x%256  x=(x-x%256)/256
    local b2=x%256  x=(x-x%256)/256
    return string.char(b1,b2)
end

function bytes_to_int32(b1, b2, b3, b4)
   return b1 + b2*256 + b3*65536 + b4*16777216
end

function bytes_to_int16(b1, b2)
   return b1 + b2*256
end

function get_label(key, map)
   return string.format("[0x%04x]", key)
end

function save_1_short(file, addr, i)
   file:seek("set", addr)
   file:write(int16_to_bytes(i))
end

function save_4_shorts(file, addr, i1, i2, i3, i4)
   file:seek("set", addr)
   file:write(int16_to_bytes(i1))
   file:write(int16_to_bytes(i2))
   file:write(int16_to_bytes(i3))
   file:write(int16_to_bytes(i4))
end

function white_balance_from_string(file, addr, s)
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

--todo: self??
function levels_from_string(file, addr, s)
   --todo: validate
   local i1,i2,i3,i4 = string.match(s, "^(%d+) (%d+) (%d+) (%d+)$")
   save_4_shorts(file, addr, i1, i2, i3, i4)
end

function color_temp_from_string(file, addr, s)
   --todo:validate
   local i = tonumber(s) or error("failed to parse "..s)
   save_1_short(file, addr, i)
end

function load_ifd_table(name, file, addr, map)
   --print(string.format("0x%x %s", addr, name))
   local t = { entries = {} }
   file:seek("set", addr)
   local entries = bytes_to_int16(file:read(2):byte(1,2))
   for i = 1,entries do
      local offset = file:seek();
      local bytes = file:read(12)
      local tag = bytes_to_int16(bytes:byte(1,2))
      local typ = bytes_to_int16(bytes:byte(3,4))
      local num = bytes_to_int32(bytes:byte(5,8))
      local val = bytes_to_int32(bytes:byte(9,12))
      t.entries[tag] = {tag_type=typ, count=num, value=val, address=addr}
      --print(string.format("0x%08x: %-15s %-35s %4d %8d 0x%x", offset, name, get_label(tag, map), typ, num, val))
   end
   t.next_ifd = bytes_to_int32(file:read(4):byte(1,4))
   return t
end

function load_i16_array(name, file, addr, count)
   --print(string.format("0x%x %s", addr, name))   
   local cb = { address=addr, size=count, array={}}
   file:seek("set", addr)
   local bytes = file:read(count*2)
   for i = 1,count do
      local offset = addr + 2 * (i - 1)
      local i16 = bytes_to_int16(bytes:byte(2*i-1,2*i))
      table.insert(cb.array, {address=offset, value=i16})
      --print(string.format("0x%08x: %-15s %-35s               %s", offset, name, get_label(i), i16))
   end
   return cb
end

function get_entries(t, map, entries)
   for i,tag in pairs(map.values) do

      local count = tag.count or 1
      local addr = t.array[i+1].address
      local value, setter
      if count == 4 then
         value = string.format(string.rep("%d ", 4), t.array[i+1].value, t.array[i+2].value, 
                               t.array[i+3].value, t.array[i+4].value)
         setter = save_4_shorts
      elseif count == 1 then
         value = string.format("%d", t.array[i+1].value)
         setter = save_1_short
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


function process_photo(filename)
   local file = io.open(filename, "r+b")

   file:seek("set", 4)
   local ifd0_offset = bytes_to_int32(file:read(4):byte(1,4))
   local ifd0_table = load_ifd_table("IFD0", file, ifd0_offset)

   local exif_offset = ifd0_table.entries[0x8769].value
   local exif_table = load_ifd_table("Exif", file, exif_offset)

   local maker_notes_offset = exif_table.entries[0x927c].value
   local maker_notes_table = load_ifd_table("MakerNotes", file, maker_notes_offset)

   local color_entry = maker_notes_table.entries[0x4001];
   local color_table = load_i16_array("ColorBalance4", file, color_entry.value, color_entry.count)

   local shot_info_entry = maker_notes_table.entries[0x04];
   local shot_info_table = load_i16_array("ShotInfo", file, shot_info_entry.value, shot_info_entry.count)

   local entries = {}
   get_entries(color_table, ColorBalance4, entries)
   get_entries(shot_info_table, CanonShotInfo, entries)

   for k,v in pairs(entries) do
      print(string.format("0x%08x: %dx  %-25s %-25s", v.address, v.count, k, v.value))
   end

   local e = entries['WhiteBalance']
   --e.setter(file, e.address, 4)
   white_balance_from_string(file, e.address, "Auto")

   local f = entries['WB_RGGBLevelsAsShot']
   --f.setter(file, f.address, 2315, 1024, 1024, 1311)
   levels_from_string(file, f.address, "1211 2211 3211 4211")

   local ct = entries['ColorTempAsShot']
   color_temp_from_string(file, ct.address, "4999")

   file:close()
end

--local filename = '20140715-IMG_6900o.CR2'
local filename = 'IMG_4576.CR2'
process_photo(filename)
