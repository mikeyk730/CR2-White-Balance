local LrStringUtils = import 'LrStringUtils'
local LrLogger = import 'LrLogger'

logger = LrLogger('CR2-White-Balance')
logger:enable("logfile")

--Split the input string on the provided separator
local function split(inputstr, sep)
   if sep == nil then
      sep = "%s"
   end
   local t={};
   for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
      table.insert(t,str)
   end
   return t
end


MetadataTools = {}

MetadataTools.canonWbOptions = {
   "Auto",
   "Daylight",
   "Cloudy",
   "Shade",
   "Tungsten",
   "Fluorescent",
   "Flash",
   "Measured", --todo:What is this?
}


function MetadataTools.getMetadataFields()
   --todo:get programatically
   return {
      'fileStatus', 
      'WhiteBalance', 
      'WB_RGGBLevelsAsShot', 
      'ColorTempAsShot',
      'WhiteBalanceOverride',
   }
end


function MetadataTools.getMetadataSet()
   --todo:get programatically
   return {
      fileStatus = true,
      WhiteBalance = true,
      WB_RGGBLevelsAsShot = true,
      ColorTempAsShot = true,
      WhiteBalanceOverride = true,
   }
end


function MetadataTools.expectCachedMetadata(metadata)
   assert(metadata)
   assert(metadata.WhiteBalance)
   assert(metadata.WB_RGGBLevelsAsShot)
   assert(metadata.ColorTempAsShot)
end


function MetadataTools.expectValidWbSelection(wb)
   for i,v in pairs(MetadataTools.canonWbOptions) do
      if wb == v then
         return
      end
   end
   error("Invalid white balance: "..wb)
end


function MetadataTools.parseArgOutput(output)
   --logger:trace("parseArgOutput", output)
   local metadataSet = MetadataTools.getMetadataSet()
   local t = {}

   local lines = split(output, '\n')
   for i, line in pairs(lines) do
      k, v = string.match(line, '-([%w_]+)=(.+)')
      if k and v then
         k = LrStringUtils.trimWhitespace(k)
         v = LrStringUtils.trimWhitespace(v)
         --logger:trace("parseArgOutput",k,v)
         if metadataSet[k] then
            t[k]=v
         else
            logger:warn("dropping key", k)
         end
      end
   end
   
   return t
end
