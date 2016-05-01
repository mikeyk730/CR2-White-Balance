local LrApplication = import 'LrApplication'
local LrErrors = import 'LrErrors'


ExiftoolInterface = {}

--todo:test with missing exe
ExiftoolInterface.exiftool = 'exiftool.exe'

--Shell execute the provided command.  Return the output of the command
function ExiftoolInterface.runCmd(cmd)
   logger:trace("Running command ", '"'..cmd..'"')

   local f = assert(io.popen(cmd, 'r'))
   local s = assert(f:read('*a'))
   --todo:check exit code, handle errors
   f:close()
   return s
end


function ExiftoolInterface.readMetadataFromFile(photo)
   logger:trace("Entering readMetadataFromFile", photo.path)

   local args = '-args -WhiteBalance -WB_RGGBLevelsAsShot -WB_RGGBLevels -ColorTempAsShot "%s"'
   local cmd = string.format(ExiftoolInterface.exiftool .. " " .. args, photo.path)
   local output = ExiftoolInterface.runCmd(cmd)
   return MetadataTools.parseArgOutput(output)
end


function ExiftoolInterface.saveMetadataToFile(photo, metadata, newWb)
   MetadataTools.expectValidWbSelection(newWb)
   MetadataTools.expectCachedMetadata(metadata)
   local args = string.format('-tagsfromfile "%s" "-WhiteBalance=%s" "-WB_RGGBLevelsAsShot<WB_RGGBLevels%s" "-WB_RGGBLevels<WB_RGGBLevels%s" "-ColorTempAsShot<ColorTemp%s" "%s"', photo.path, newWb, newWb, newWb, newWb, photo.path)
   local cmd = ExiftoolInterface.exiftool .. " " .. args

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'changedOnDisk')
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', newWb)
   end, { timeout=60 })

   local output = ExiftoolInterface.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("Save failed.  File may be locked by another process")
      logger:trace(output)
      LrErrors.throwUserError("Save failed")
   end
end


function ExiftoolInterface.restoreFileMetadata(photo, metadata)
   MetadataTools.expectCachedMetadata(metadata)
   local args = string.format('"-WhiteBalance=%s" "-WB_RGGBLevelsAsShot=%s" "-WB_RGGBLevels=%s" "-ColorTempAsShot=%s" "%s"',
                              metadata.WhiteBalance, metadata.WB_RGGBLevelsAsShot, 
                              metadata.WB_RGGBLevels, metadata.ColorTempAsShot, 
                              photo.path)
   local cmd = ExiftoolInterface.exiftool .. " " .. args

   local output = ExiftoolInterface.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("Revert failed")
      logger:trace(output)
      LrErrors.throwUserError("Revert failed.  File may be locked by another process")
   end

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'loadedMetadata')
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', nil)     
   end, { timeout=60 })
end
