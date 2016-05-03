local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'


require 'MetadataTools'
--require 'ExiftoolInterface'
require 'ExifControllerInterface'

--todo: code review error handling
--todo: make sure catalog metadata never gets overwritten

Prefs = {
   writeSidecarOnLoad = true,
   --exifInterface = ExiftoolInterface,
   exifInterface = ExifControllerInterface,
}

PhotoProcessor = {}

PhotoProcessor.dialogWbOptions = {
   { value = "AsShot", title = "Revert to Shot Settings" },
   { value = "Auto", title = "Auto" },
   { value = "Daylight", title = "Daylight" },
   { value = "Cloudy", title = "Cloudy" },
   { value = "Shade", title = "Shade" },
   { value = "Tungsten", title = "Tungsten" },
   { value = "Fluorescent", title = "Fluorescent" },
   { value = "Flash", title = "Flash" },
}


function PhotoProcessor.promptForWhiteBalance(selectedOption)
   if selectedOption == nil then
      selectedOption = 'Auto'
   end

   LrFunctionContext.callWithContext("promptForWhiteBalance", function(context)
      local props = LrBinding.makePropertyTable(context)
      props.option = selectedOption

      local f = LrView.osFactory()
      local c = f:row {
         bind_to_object = props,
         f:popup_menu {
            value = LrView.bind("option"),
            items = PhotoProcessor.dialogWbOptions
         },
      }

      local result = LrDialogs.presentModalDialog({
            title = "Select New White Balance",
            contents = c
      })

      if result == "ok" then
         selectedOption = props.option
      else 
         logger:trace("User canceled dialog")
         LrErrors.throwCanceled()
      end
   end)

   return selectedOption
end


function PhotoProcessor.getSidecarFilename(photo)
   return photo.path .. ".wb"
end


--Reads white balance metadata from the photo's sidecar file.  Returns a table of the values
function PhotoProcessor.readMetadataFromSidecar(photo)
   local sidecar = PhotoProcessor.getSidecarFilename(photo)

   if not LrFileUtils.exists(sidecar) then
      logger:info("Sidecar doesn't exisit", sidecar)
      return nil
   end
     
   local content = LrFileUtils.readFile(sidecar)
   logger:trace("sidecar content",content)
   return MetadataTools.parseArgOutput(content)
end


--Writes the supplied metadata to a sidecar file.
function PhotoProcessor.saveMetadataToSidecar(photo, metadata)
   MetadataTools.expectCachedMetadata(metadata)

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
   local keys = MetadataTools.getMetadataFields()
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
         local keys = MetadataTools.getMetadataFields()
         for i, k in ipairs(keys) do            
            photo:setPropertyForPlugin(_PLUGIN, k, nil)
         end
   end, { timeout=60 })      
end


--Saves the provided white balance metadata into the catalog 
function PhotoProcessor.saveMetadataToCatalog(photo, metadata, writeSidecar)
   MetadataTools.expectCachedMetadata(metadata)
   
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
end


--Reads white balance metadata from the provided file.  Returns a table of the values
function PhotoProcessor.readMetadataFromFile(photo)
   return Prefs.exifInterface.readMetadataFromFile(photo)
end


function PhotoProcessor.saveMetadataToFile(photo, metadata, newWb)
   return Prefs.exifInterface.saveMetadataToFile(photo, metadata, newWb)
end


function PhotoProcessor.restoreFileMetadata(photo, metadata)
   return Prefs.exifInterface.restoreFileMetadata(photo, metadata)
end


function PhotoProcessor.runCommandChange(photo, props)
   logger:trace("Entering runCommandChange", photo.path)
   local newWb = props.newWb
   assert(newWb)

   logger:trace("Changing white balance", newWb, photo.path)
   PhotoProcessor.runCommandLoad(photo)
   if newWb == "AsShot" then
      return PhotoProcessor.runCommandRevert(photo)
   else
      return PhotoProcessor.runCommandSave(photo, newWb)
   end
end


--Save metadata from the catalog into a sidecar file
function PhotoProcessor.runCommandSaveSidecar(photo)
   logger:trace("Entering runCommandSaveSidecar", photo.path)

   --Don't write sidecar if there's no metadata in the catalog
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.fileStatus ~= 'loadedMetadata' then
      logger:info("No metadata to save to sidecar", metadata.fileStatus, photo.path)
      return false
   else
      logger:trace("Saving metadata to sidecar", photo.path)
      PhotoProcessor.saveMetadataToSidecar(photo, metadata)
      return true
   end
end


--Load metadata from the sidecar into the catalog
function PhotoProcessor.runCommandLoadSidecar(photo)
   logger:trace("Entering runCommandLoadSidecar", photo.path)

   --Skip files whose metadata is already in the catalog
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:info("Skipped loading sidecar", status, photo.path)
      return false
   else
      logger:trace("Loading metadata from sidecar", photo.path)
      local metadata = PhotoProcessor.readMetadataFromSidecar(photo)
      if metadata == nil then
         return false
      end
      PhotoProcessor.saveMetadataToCatalog(photo, metadata, false)
      return true
   end
end


--Load metadata from the file into the catalog
function PhotoProcessor.runCommandLoad(photo)
   logger:trace("Entering runCommandLoad", photo.path)

   --Skip files whose metadata is already in the catalog
   local status = photo:getPropertyForPlugin(_PLUGIN, 'fileStatus')
   if status ~= nil then
      logger:info("Skipped loading", status, photo.path)
      return false
   else
      logger:trace("Loading metadata from file", photo.path)
      local metadata = PhotoProcessor.readMetadataFromFile(photo)
      PhotoProcessor.saveMetadataToCatalog(photo, metadata, Prefs.writeSidecarOnLoad)
      return true
   end
end


--Set new white balance metadata into the image.  This function overwrites 
--the .CR2 metadata, which means this is a destructive operation
function PhotoProcessor.runCommandSave(photo, newWb)
   logger:trace("Entering runCommandSave", photo.path)

   --todo: revisit, take into account override

   --Don't write the file unless the original metadata is stored in the catalog
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.fileStatus ~= 'loadedMetadata' then
      logger:info("Can't save file", metadata.fileStatus, photo.path)
      return false
   else
      logger:trace("Saving metadata to file", photo.path)
      PhotoProcessor.saveMetadataToFile(photo, metadata, newWb)
      return true
   end
end


--Restores the original white balance to the image.  This function overwrites
--the .CR2 metadata, which means this is a destructive operation
function PhotoProcessor.runCommandRevert(photo)
   logger:trace("Entering runCommandRevert", photo.path)

   --Only saved files can be reverted
   local metadata = PhotoProcessor.loadMetadataFromCatalog(photo)
   if metadata.WhiteBalanceOverride == nil then
      logger:info("Can't revert file", metadata.WhiteBalanceOverride, photo.path)
      return false
   else
      logger:trace("Reverting file", photo.path)
      PhotoProcessor.restoreFileMetadata(photo, metadata)
      return true
   end
end


--Clears white balance metadata from the Lightroom catalog.
function PhotoProcessor.runCommandClear(photo)
   logger:trace("Entering runCommandClear", photo.path)

   --Files that have changed on disk can't be cleared since the original
   --information would be lost
   local override = photo:getPropertyForPlugin(_PLUGIN, 'WhiteBalanceOverride')
   --todo: remove shotInAuto
   if override ~= nil then
      logger:info("Can't clear metadata", override, photo.path)
      return false
   else
      logger:trace("Clearing metadata", photo.path)
      PhotoProcessor.clearMetadataFromCatalog(photo)
      return true
   end
end


function PhotoProcessor.getActionAttr(action, attr)
   local map = {
      change =      { title = "Setting White Balance",   handler = PhotoProcessor.runCommandChange },
      load =        { title = "Loading White Balance",   handler = PhotoProcessor.runCommandLoad },
      revert =      { title = "Reverting White Balance", handler = PhotoProcessor.runCommandRevert },
      clear =       { title = "Clearing Metadata",       handler = PhotoProcessor.runCommandClear },
      loadSidecar = { title = "Loading WB Sidecar",      handler = PhotoProcessor.runCommandLoadSidecar },
      saveSidecar = { title = "Saving WB Sidecar",       handler = PhotoProcessor.runCommandSaveSidecar },
   }
   return map[action][attr]
end


function PhotoProcessor.promptUser(action)
   local props = {}

   if action == "change" then
      props.newWb = PhotoProcessor.promptForWhiteBalance()
   end

   return props
end


function PhotoProcessor.updateProgress(progress, status)
   progress.complete = progress.complete + 1
   progress.scope:setPortionComplete(progress.complete, progress.total)
   progress.scope:setCaption(progress.complete.." of "..progress.total)

   progress.stats[status] = progress.stats[status] + 1

   if progress.complete == progress.total then
      local success = string.format("%d of %d completed successfully", progress.stats.success, progress.total)
      local failure = string.format("%d failures, %d bad format, %d unavailable", progress.stats.failure, progress.stats.bad_type, progress.stats.unavailable)

      logger:info("----------------------------------")
      logger:info(success)
      logger:info(failure)
      logger:info("----------------------------------")

      progress.scope:done()
      LrDialogs.message(progress.title, success.."\n"..failure)
   end
end


function PhotoProcessor.processPhoto(photo, action, args, progress)
   --Use pcall so errors with a single photo can be captured, and not interrupt
   --the whole operation
   local status, err = LrTasks.pcall(function () 
         --Skip files that aren't mounted
         local available = photo:checkPhotoAvailability()
         if not available then         
            logger:warn("Photo not available: " .. photo.path)
            PhotoProcessor.updateProgress(progress, 'unavailable')
            return
         end
         
         --Skip files that are not Canon Raw files
         local ft = photo:getFormattedMetadata('fileType')
         local make = photo:getFormattedMetadata('cameraMake')
         if ft ~= 'Raw' or make ~= 'Canon' then
            logger:info("Skipping unsupported file", make, ft, photo.path)
            PhotoProcessor.updateProgress(progress, 'bad_type')
            return
         end
         
         local handler = PhotoProcessor.getActionAttr(action, 'handler')
         if handler(photo, args) then
            PhotoProcessor.updateProgress(progress, 'success')
         else 
            PhotoProcessor.updateProgress(progress, 'failure')
         end
   end)
   if not status then
      logger:error(err)
      --LrDialogs.message("Error with "..photo.path, err)
      PhotoProcessor.updateProgress(progress, 'failure')
   end
end


function PhotoProcessor.processPhotosWithOneTask(action, photos, progress)
   LrTasks.startAsyncTask(function(c)
      LrFunctionContext.callWithContext("processPhotos", function(context) 

         progress.scope:attachToFunctionContext(context)
         local args = PhotoProcessor.promptUser(action)
         for i,photo in ipairs(photos) do
            if progress.scope:isCanceled() then 
               logger:info("Canceled task", progress.title, progress.complete)
               break
            end
            PhotoProcessor.processPhoto(photo, action, args, progress)
         end

      end)
   end)
end


function PhotoProcessor.processPhotosWithManyTasks(action, photos, progress)
   local args = PhotoProcessor.promptUser(action)
   for i,photo in ipairs(photos) do
      LrTasks.startAsyncTask(function(context)
            if not progress.scope:isCanceled() then 
               PhotoProcessor.processPhotoAsync(photo, action, args, progress)
            end
      end)
   end
end


--Returns an array of the files that are currently selected in Lightroom
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
   local total_photos = #photos

   local title = PhotoProcessor.getActionAttr(action, 'title')
   local display_title = title.." for "..total_photos.." Photos"

   logger:info("==================")
   logger:info(display_title)
   logger:info("==================")

   local progressScope = LrProgressScope {title=display_title}
   progressScope:setCancelable(true)
   local progress = {
      scope = progressScope, 
      title = title,  
      complete = 0, 
      total = total_photos,
      stats = { 
         unavailable = 0, 
         bad_type = 0, 
         success = 0, 
         failure = 0,
      }
   }

   PhotoProcessor.processPhotosWithOneTask(action, photos, progress)
end
