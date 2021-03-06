local LrApplication = import 'LrApplication'
local LrErrors = import 'LrErrors'

require 'ExifController'


local function getFileMetadataFields()
   return {
      'WhiteBalance', 
      'WB_RGGBLevelsAsShot', 
      'ColorTempAsShot',
   }
end


ExifControllerInterface = {}

function ExifControllerInterface.readMetadataFromFile(photo)
   logger:trace("Entering readMetadataFromFile", photo.path)

   local cr2 = Cr2File:Create(photo.path)

   t = {}
   local fields = getFileMetadataFields()
   for i, k in ipairs(fields) do
      t[k] = tostring(cr2:GetValue(k))
      --logger:trace(k,t[k],type(t[k]))
   end

   cr2:Close()

   return t
end


function ExifControllerInterface.saveMetadataToFile(photo, metadata, newWb)
   MetadataTools.expectValidWbSelection(newWb)
   MetadataTools.expectCachedMetadata(metadata)
   
   local cr2 = Cr2File:Create(photo.path)

   local levels = cr2:GetValue("WB_RGGBLevels"..newWb)
   local temp = tostring(cr2:GetValue("ColorTemp"..newWb))
   assert(levels)
   assert(temp)
   logger:trace("saveMetadataToFile", newWb, levels, temp)

   cr2:SetValue('WhiteBalance', newWb)
   cr2:SetValue('WB_RGGBLevelsAsShot', levels)
   cr2:SetValue('ColorTempAsShot', temp)

   cr2:Close()

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', newWb)
   end, { timeout=60 })
end


function ExifControllerInterface.restoreFileMetadata(photo, metadata)
   MetadataTools.expectCachedMetadata(metadata)
   
   local cr2 = Cr2File:Create(photo.path)

   local fields = getFileMetadataFields()
   for i, k in ipairs(fields) do
      cr2:SetValue(k, metadata[k])   
   end

   cr2:Close()

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', nil)     
   end, { timeout=60 })
end
