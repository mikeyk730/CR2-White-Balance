local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrView = import 'LrView'
local LrStringUtils = import 'LrStringUtils'
local LrProgressScope = import 'LrProgressScope'
local LrErrors = import 'LrErrors'
--todo:can i write backup info to CR2 instead of sidecars? could reuse adj fields

local logger = LrLogger('CorrectWhiteBalance')
logger:enable("logfile")

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
   }
end


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

--Shell execute the provided command.  Return the output of the command
function PhotoProcessor.runCmd(cmd)
   logger:trace("Running command ", '"'..cmd..'"')

   local f = assert(io.popen(cmd, 'r'))
   local s = assert(f:read('*a'))
   --todo:check exit code, handle errors
   f:close()
   return s
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

function PhotoProcessor.createSnapshot(photo)
   local name = PhotoProcessor.promptForSnapshotName()
   logger:trace("Creating snapshot", name, photo.path)

   local catalog = LrApplication.activeCatalog()
   catalog:withWriteAccessDo("Create Snapshot", function(context) 
         photo:createDevelopSnapshot(name, true)
   end, { timeout=60 })
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
   local values = PhotoProcessor.parseArgOutput(content)
   PhotoProcessor.saveMetadataToCatalog(photo, values, false)
end

--Writes the supplied metadata to a sidecar file.
function PhotoProcessor.writeMetadataToSidecar(photo, values)
   values.fileStatus = nil
   local sidecar = PhotoProcessor.getSidecarFilename(photo)
   logger:trace("Writing values to sidecar", sidecar)
   local f = assert(io.open(sidecar, "w"))
   for k, v in pairs(values) do
      --logger:trace(k,v)
      f:write("-"..k.."="..v.."\n")
   end
   f:close()
end

function PhotoProcessor.getMetadataTable(photo)
   local values = {}
   local keys = PhotoProcessor.getMetadataFields()
   for i, k in ipairs(keys) do
      local v = photo:getPropertyForPlugin(_PLUGIN, k)
      if v then
         values[k] = v
      end
   end
   return values
end

function PhotoProcessor.saveSidecar(photo)
   logger:trace("Entering saveSidecar")
   local values = PhotoProcessor.getMetadataTable(photo)
   if values.fileStatus == 'loadedMetadata' or values.fileStatus == 'changedOnDisk' then
      PhotoProcessor.writeMetadataToSidecar(photo, values)
   else
      logger:trace("Can't save sidecar", values.fileStatus)
   end
end

function PhotoProcessor.loadSidecar(photo)
   logger:trace("Entering loadSidecar", sidecar)
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:trace("Skipping file with metadata", photo.path)
      return
   end
   PhotoProcessor.readMetadataFromSidecar(photo)
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

--Reads white balance metadata from the provided file.  Returns a table of the values
function PhotoProcessor.readMetadataFromFile(photo)
   logger:trace("Entering readMetadataFromFile", photo.path)

   local args = '-args -WhiteBalance -WB_RGGBLevelsAsShot -WB_RGGBLevels -ColorTempAsShot "%s"'
   local cmd = string.format(PhotoProcessor.exiftool .. " " .. args, photo.path)
   local output = PhotoProcessor.runCmd(cmd)
   return PhotoProcessor.parseArgOutput(output)
end

--Saves the provided white balance metadata into the catalog 
function PhotoProcessor.saveMetadataToCatalog(photo, values, writeSidecar)
   --LrTasks.startAsyncTask(function(context)
        --TODO: checks before running command
        --dont set data if was !auto
        --todo: validate input

        local wb = values['WhiteBalance']
        local catalog = LrApplication.activeCatalog()
        
        if wb == nil then
           logger:error("Failed to read white balance", photo.path)
        elseif wb == "Auto" then
           catalog:withPrivateWriteAccessDo(function(context) 
                 logger:trace("Saving Metadata Auto", photo.path)
                 photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'shotInAuto')
           end, { timeout=60 })      
        else
           if writeSidecar then
              PhotoProcessor.writeMetadataToSidecar(photo, values)
           end
           catalog:withPrivateWriteAccessDo(function(context) 
                 logger:trace("Saving Metadata", wb, photo.path)
                 for k, v in pairs(values) do
                    photo:setPropertyForPlugin(_PLUGIN, k, v)
                 end
                 photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'loadedMetadata')           
           end, { timeout=60 })
        end
   --end)
end

function PhotoProcessor.cacheMetadata(photo)
   logger:trace("Entering cacheMetadata", photo.path)

   --Skip files whose metadata is already saved in the catalog
   local catalog = LrApplication.activeCatalog()
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:trace("Skipping file with metadata", photo.path)
      return
   end

   local values = PhotoProcessor.readMetadataFromFile(photo)
   PhotoProcessor.saveMetadataToCatalog(photo, values, true)
end

function PhotoProcessor.clearMetadataFields(photo)
   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         logger:trace("Clearing metadata", photo.path)
         local keys = PhotoProcessor.getMetadataFields()
         for i, k in ipairs(keys) do            
            photo:setPropertyForPlugin(_PLUGIN, k, nil)
         end
   end, { timeout=60 })      
end


function PhotoProcessor.saveFile(photo, newWb)
   --TODO: checks before running command
   --dont save unless 3 values are cached in metadata
   logger:trace("Overwriting original settings", photo.path)

   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= 'loadedMetadata' then
      logger:trace("Can't save file", status, photo.path)
      return
   end

   local args = string.format('-tagsfromfile "%s" "-WhiteBalance=%s" "-WB_RGGBLevelsAsShot<WB_RGGBLevels%s" "-WB_RGGBLevels<WB_RGGBLevels%s" "-ColorTempAsShot<ColorTemp%s" "%s"', photo.path, newWb, newWb, newWb, newWb, photo.path)
   local cmd = PhotoProcessor.exiftool .. " " .. args,

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'changedOnDisk')
   end, { timeout=60 })

   local output = PhotoProcessor.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("Save failed")
      logger:trace(output)
      LrErrors.throwUserError("Save failed")
   end
end

function PhotoProcessor.revertFile(photo)
   logger:trace("Reverting original settings", photo.path)

   metadata = PhotoProcessor.getMetadataTable()

   if metadata.fileStatus ~= 'changedOnDisk' then
      logger:trace("Can't revert file", metadata.fileStatus,  photo.path)
      return
   end

   assert(metadata.WhiteBalance)
   assert(metadata.WB_RGGBLevelsAsShot)
   assert(metadata.WB_RGGBLevels)
   assert(metadata.ColorTempAsShot)

   local args = string.format('"-WhiteBalance=%s" "-WB_RGGBLevelsAsShot=%s" "-WB_RGGBLevels=%s" "-ColorTempAsShot=%s" "%s"', metadata.WhiteBalance, metadata.WB_RGGBLevelsAsShot, metadata.WB_RGGBLevels, metadata.ColorTempAsShot, photo.path)
   local cmd = PhotoProcessor.exiftool .. " " .. args

   local output = PhotoProcessor.runCmd(cmd)
   if not string.find(output, "1 image files updated") then
      logger:error("revert failed")
      logger:trace(output)
      LrErrors.throwUserError("Revert failed")
   end

   local catalog = LrApplication.activeCatalog()
   catalog:withPrivateWriteAccessDo(function(context) 
         photo:setPropertyForPlugin(_PLUGIN, 'fileStatus', 'loadedMetadata')           
   end, { timeout=60 })
end

function PhotoProcessor.clearMetadata(photo)
   logger:trace("Entering clearMetadata", photo.path)

   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status == 'loadedMetadata' or status == 'shotInAuto' then
      PhotoProcessor.clearMetadataFields(photo)
   else
      logger:trace("Can't clear metadata", status, photo.path)
   end
end

PhotoProcessor.taskCount = 0

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

            if action == "check" then
               PhotoProcessor.cacheMetadata(photo)
            elseif action == "save" then
               PhotoProcessor.saveFile(photo, "Auto")
            elseif action == "revert" then
               PhotoProcessor.revertFile(photo)
            elseif action == "clear" then
               PhotoProcessor.clearMetadata(photo)
            elseif action == "loadSidecar" then
               PhotoProcessor.loadSidecar(photo)
            elseif action == "saveSidecar" then
               PhotoProcessor.saveSidecar(photo)
            elseif action == "createSnapshot" then
               PhotoProcessor.createSnapshot(photo)
            else
               logger:error("Unknown action: " .. action)
            end
         else
            logger:warn("Photo not available: " .. photo.path)
         end
   --end)
end

--Returns a table of the files that are currently selected
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

--Main entry point for the scripts associated with the menu items
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
            logger:trace("Canceled task", action, i)
            if progressScope:isCanceled() then 
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
