local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'
local LrProgressScope = import 'LrProgressScope'
local LrStringUtils = import 'LrStringUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
--todo:can i write backup info to CR2 instead of sidecars? could reuse adj fields

local logger = LrLogger('CorrectWhiteBalance')
logger:enable("logfile")

--Split the input string on the provided separator
function split(inputstr, sep)
   if sep == nil then
      sep = "%s"
   end
   local t={};
   for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
      table.insert(t,str)
   end
   return t
end

Prefs = {
   writeSidecarOnLoad = true
}

PhotoProcessor = {}

--todo:test with missing exe
PhotoProcessor.exiftool = 'exiftool.exe'

PhotoProcessor.whiteBalanceOptions = {
   "Auto",
   "Daylight",
   "Cloudy",
   "Shade",
   "Tungsten",
   "Fluorescent",
   "Flash",
   "Measured", --todo:What is this?
}


function PhotoProcessor.getMetadataFields()
   --todo:get programatically
   return {
      'fileStatus', 
      'WhiteBalance', 
      'WB_RGGBLevels', 
      'WB_RGGBLevelsAsShot', 
      'ColorTempAsShot',
      'WhiteBalanceOverride',
   }
end


function PhotoProcessor.getMetadataSet()
   --todo:get programatically
   return {
      fileStatus = true,
      WhiteBalance = true,
      WB_RGGBLevels = true,
      WB_RGGBLevelsAsShot = true,
      ColorTempAsShot = true,
      WhiteBalanceOverride = true,
   }
end


function PhotoProcessor.expectCachedMetadata(metadata)
   assert(metadata.WhiteBalance)
   assert(metadata.WB_RGGBLevelsAsShot)
   assert(metadata.WB_RGGBLevels)
   assert(metadata.ColorTempAsShot)
end


function PhotoProcessor.expectValidWbSelection(wb)
   --todo:verify that wb is in whiteBalanceOptions
end


--Shell execute the provided command.  Return the output of the command
function PhotoProcessor.runCmd(cmd)
   logger:trace("Running command ", '"'..cmd..'"')

   local f = assert(io.popen(cmd, 'r'))
   local s = assert(f:read('*a'))
   --todo:check exit code, handle errors
   f:close()
   return s
end


function PhotoProcessor.parseArgOutput(output)
   local metadataSet = PhotoProcessor.getMetadataSet()
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


function PhotoProcessor.promptForSnapshotName()
   local r = "Untitled"
   LrFunctionContext.callWithContext("promptForSnapshotName", function(context)
      local props = LrBinding.makePropertyTable(context)
      props.name = "Untitled"

      local f = LrView.osFactory()
      local c = f:row {
         bind_to_object = props,
         f:edit_field {
            value = LrView.bind("name")
         },
      }

      local result = LrDialogs.presentModalDialog({
            title = "Custom",
            contents = c
      })

      r = props.name
   end)
   return r
end


function PhotoProcessor.getSidecarFilename(photo)
   return photo.path .. ".wb"
end


--Reads white balance metadata from the photo's sidecar file.  Returns a table of the values
function PhotoProcessor.readMetadataFromSidecar(photo)
   local sidecar = PhotoProcessor.getSidecarFilename(photo)

   if not LrFileUtils.exists(sidecar) then
      logger:trace("Sidecar doesn't exisit", sidecar)
      return
   end
     
   local content = LrFileUtils.readFile(sidecar)
   logger:trace("sidecar content",content)
   return PhotoProcessor.parseArgOutput(content)
end


--Writes the supplied metadata to a sidecar file.
function PhotoProcessor.saveMetadataToSidecar(photo, metadata)
   PhotoProcessor.expectCachedMetadata(metadata)

   local sidecar = PhotoProcessor.getSidecarFilename(photo)
   logger:trace("Writing metadata to sidecar", sidecar)
   local f = assert(io.open(sidecar, "w"))

   metadata.fileStatus = nil
   metadata.WhiteBalanceOverride = nil
   for k, v in pairs(metadata) do
      f:write("-"..k.."="..v.."\n")
   end
   f:close()
end


function PhotoProcessor.loadMetadataFromCatalog(photo)
   local metadata = {}
   local keys = PhotoProcessor.getMetadataFields()
   for i, k in ipairs(keys) do
      local v = photo:getPropertyForPlugin(_PLUGIN, k)
      if v then
         metadata[k] = v
      end
   end
   return metadata
end


function PhotoProcessor.clearMetadataFromCatalog(photo)
   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         logger:trace("Clearing metadata", photo.path)
         local keys = PhotoProcessor.getMetadataFields()
         for i, k in ipairs(keys) do            
            photo:setPropertyForPlugin(_PLUGIN, k, nil)
         end
   end, { timeout=60 })      
end


--Saves the provided white balance metadata into the catalog 
function PhotoProcessor.saveMetadataToCatalog(photo, metadata, writeSidecar)
   --LrTasks.startAsyncTask(function(context)
         PhotoProcessor.expectCachedMetadata(metadata)
         
         if writeSidecar then
            PhotoProcessor.saveMetadataToSidecar(photo, metadata)
         end
         
         local catalog = LrApplication.activeCatalog()
         catalog:withPrivateWriteAccessDo(function(context) 
               logger:trace("Have write access to catalog", photo.path)
               metadata.fileStatus = nil
               metadata.WhiteBalanceOverride = nil
               for k, v in pairs(metadata) do
                  photo:setPropertyForPlugin(_PLUGIN, k, v)
               end
               photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'loadedMetadata')           
         end, { timeout=60 })
   --end)
end


--Reads white balance metadata from the provided file.  Returns a table of the values
function PhotoProcessor.readMetadataFromFile(photo)
   logger:trace("Entering readMetadataFromFile", photo.path)

   local args = '-args -WhiteBalance -WB_RGGBLevelsAsShot -WB_RGGBLevels -ColorTempAsShot "%s"'
   local cmd = string.format(PhotoProcessor.exiftool .. " " .. args, photo.path)
   local output = PhotoProcessor.runCmd(cmd)
   return PhotoProcessor.parseArgOutput(output)
end


function PhotoProcessor.saveMetadataToFile(photo, metadata, newWb)
   PhotoProcessor.expectValidWbSelection(newWb)
   PhotoProcessor.expectCachedMetadata(metadata)
   local args = string.format('-tagsfromfile "%s" "-WhiteBalance=%s" "-WB_RGGBLevelsAsShot<WB_RGGBLevels%s" "-WB_RGGBLevels<WB_RGGBLevels%s" "-ColorTempAsShot<ColorTemp%s" "%s"', photo.path, newWb, newWb, newWb, newWb, photo.path)
   local cmd = PhotoProcessor.exiftool .. " " .. args

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'changedOnDisk')
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', newWb)
   end, { timeout=60 })

   local output = PhotoProcessor.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("Save failed")
      logger:trace(output)
      LrErrors.throwUserError("Save failed")
   end
end


function PhotoProcessor.restoreFileMetadata(photo, metadata)
   PhotoProcessor.expectCachedMetadata(metadata)
   local args = string.format('"-WhiteBalance=%s" "-WB_RGGBLevelsAsShot=%s" "-WB_RGGBLevels=%s" "-ColorTempAsShot=%s" "%s"',
                              metadata.WhiteBalance, metadata.WB_RGGBLevelsAsShot, 
                              metadata.WB_RGGBLevels, metadata.ColorTempAsShot, 
                              photo.path)
   local cmd = PhotoProcessor.exiftool .. " " .. args

   local output = PhotoProcessor.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("Revert failed")
      logger:trace(output)
      LrErrors.throwUserError("Revert failed")
   end

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'loadedMetadata')
         photo:setPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride', nil)     
   end, { timeout=60 })
end



--Create a develop snapshot fro the supplied photo.  If no name is supplied
--the user will be prompted with a dialog
function PhotoProcessor.runCommandCreateSnapshot(photo, name)
   logger:trace("Entering runCommandCreateSnapshot", photo.path)

   if name == nil then
      name = PhotoProcessor.promptForSnapshotName()
   end

   logger:trace("Creating snapshot", name, photo.path)
   local catalog = LrApplication.activeCatalog()
   catalog:withWriteAccessDo("Create Snapshot", function(context) 
         photo:createDevelopSnapshot(name, true)
   end, { timeout=60 })
end


--Save metadata from the catalog into a sidecar file
function PhotoProcessor.runCommandSaveSidecar(photo)
   logger:trace("Entering runCommandSaveSidecar", photo.path)

   --Don't write sidecar if there's no metadata in the catalog
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.fileStatus ~= 'loadedMetadata' and metadata.fileStatus ~= 'changedOnDisk' then
      logger:trace("Can't save sidecar", metadata.fileStatus, photo.path)
      return
   end

   logger:trace("Saving metadata to sidecar", photo.path)
   PhotoProcessor.saveMetadataToSidecar(photo, metadata)
end


--Load metadata from the sidecar into the catalog
function PhotoProcessor.runCommandLoadSidecar(photo)
   logger:trace("Entering runCommandLoadSidecar", photo.path)

   --Skip files whose metadata is already in the catalog
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:trace("Skipped loading sidecar", status, photo.path)
      return
   end

   logger:trace("Loading metadata from sidecar", photo.path)
   local metadata = PhotoProcessor.readMetadataFromSidecar(photo)
   PhotoProcessor.saveMetadataToCatalog(photo, metadata, false)
end


--Load metadata from the file into the catalog
function PhotoProcessor.runCommandLoad(photo)
   logger:trace("Entering runCommandLoad", photo.path)

   --Skip files whose metadata is already in the catalog
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:trace("Skipped loading", status, photo.path)
      return
   end

   logger:trace("Loading metadata from file", photo.path)
   local metadata = PhotoProcessor.readMetadataFromFile(photo)
   PhotoProcessor.saveMetadataToCatalog(photo, metadata, Prefs.writeSidecarOnLoad)
end


--Set new white balance metadata into the image.  The implementation uses 
--exiftool to modify image metadata, which means this is a destructive operation
function PhotoProcessor.runCommandSave(photo, newWb)
   logger:trace("Entering runCommandSave", photo.path)

   --Don't write the file unless the original metadata is stored in the catalog
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.fileStatus ~= 'loadedMetadata' then
      logger:trace("Can't save file", metadata.fileStatus, photo.path)
      return
   end

   logger:trace("Saving metadata to file", photo.path)
   PhotoProcessor.saveMetadataToFile(photo, metadata, newWb)
end


--Restores the original white balance to the image.  The implementation uses 
--exiftool to overwrite image metadata with metadata stored in the catalog.
--This is a destructive operation
function PhotoProcessor.runCommandRevert(photo)
   logger:trace("Entering runCommandRevert", photo.path)

   --Only saved files can be reverted
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.fileStatus ~= 'changedOnDisk' then
      logger:trace("Can't revert file", metadata.fileStatus, photo.path)
      return
   end

   logger:trace("Reverting file", photo.path)
   PhotoProcessor.restoreFileMetadata(photo, metadata)
end


--Clears white balance metadata from the Lightroom catalog.
function PhotoProcessor.runCommandClear(photo)
   logger:trace("Entering runCommandClear", photo.path)

   --Files that have changed on disk can't be cleared since the original
   --information would be lost
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= 'loadedMetadata' and status ~= 'shotInAuto' then
      logger:trace("Can't clear metadata", status, photo.path)
   end

   logger:trace("Clearing metadata", photo.path)
   PhotoProcessor.clearMetadataFromCatalog(photo)
end


function PhotoProcessor.processPhoto(photo, action)
   --LrTasks.startAsyncTask(function(context)
         local available = photo:checkPhotoAvailability()
         if available then         

            --Skip files that are not Canon Raw files
            local ft = photo:getFormattedMetadata('fileType')
            local make = photo:getFormattedMetadata('cameraMake')
            if ft ~= 'Raw' or make ~= 'Canon' then
               logger:trace("Skipping unsupported file", make, ft, photo.path)
               return
            end

            if action == "load" then
               PhotoProcessor.runCommandLoad(photo)
            elseif action == "save" then
               PhotoProcessor.runCommandSave(photo, "Auto")
            elseif action == "revert" then
               PhotoProcessor.runCommandRevert(photo)
            elseif action == "clear" then
               PhotoProcessor.runCommandClear(photo)
            elseif action == "loadSidecar" then
               PhotoProcessor.runCommandLoadSidecar(photo)
            elseif action == "saveSidecar" then
               PhotoProcessor.runCommandSaveSidecar(photo)
            elseif action == "createSnapshot" then
               PhotoProcessor.runCommandCreateSnapshot(photo)
            else
               logger:error("Unknown action: " .. action)
            end
         else
            logger:warn("Photo not available: " .. photo.path)
         end
   --end)
end


--Returns a table of the files that are currently selected in Lightroom
function PhotoProcessor.getSelectedPhotos()
   local catalog = LrApplication.activeCatalog()
   local photo = catalog:getTargetPhoto()
   local photos = catalog:getTargetPhotos()

   if photo ~= nil then
      return photos
   else
      return {}
   end
end


--Main entry point for scripts associated with menu items
function PhotoProcessor.processPhotos(action)
   local photos = PhotoProcessor.getSelectedPhotos()
   local totalPhotos = #photos
   logger:trace("Starting task", action, totalPhotos)
   --todo:rework so each photo can be a task
   LrTasks.startAsyncTask(function(context)
         local progressScope = LrProgressScope {title=action.." "..totalPhotos.." photos"}
         --todo:doens't work
         --progressScope:attachToFunctionContext(context)
         progressScope:setCancelable(true)

         for i,v in ipairs(photos) do
            if progressScope:isCanceled() then 
               logger:trace("Canceled task", action, i)
               break
            end
            progressScope:setPortionComplete(i, totalPhotos)
            progressScope:setCaption(action.." "..i.." of "..totalPhotos)
            PhotoProcessor.processPhoto(v, action)
         end

         logger:trace("Completed task", action, totalPhotos)
         progressScope:done()
   end)
end
