return {
   LrSdkVersion = 5.0,
   LrToolkitIdentifier = 'com.mkaminski.metadata',
   LrPluginName = LOC "$$$/Metadata/PluginName=CR2 White Balance",

   LrInitPlugin = 'PluginInit.lua',
   LrPluginInfoProvider = "PluginInfoProvider.lua",
   LrPluginInfoUrl = "http://www.mkaminski.com",

   LrMetadataProvider = "MetadataProvider.lua",
   LrMetadataTagsetFactory = "MetadataTagsetFactory.lua",

   LrLibraryMenuItems = {
      {
         title = "Change &White Balance",
         file = "MenuItemChangeWhiteBalance.lua",
         enabledWhen = "photosSelected",
      },
      {
         title = "&Load Metadata From File",
         file = "MenuItemCheckWhiteBalance.lua",
         enabledWhen = "photosSelected",
      },
      --{
      --   title = "Clear Unsaved Metadata",
      --   file = "MenuItemClearWhiteBalance.lua",
      --   enabledWhen = "photosSelected",
      --},
      --{
      --   title = "&Save Metadata to File",
      --   file = "MenuItemSaveWhiteBalance.lua",
      --   enabledWhen = "photosSelected",
      --},
      --{
      --   title = "&Revert Saved Metadata",
      --   file = "MenuItemRevertWhiteBalance.lua",
      --   enabledWhen = "photosSelected",
      --},
      --{
      --   title = "Save Sidecar",
      --   file = "MenuItemSaveSidecar.lua",
      --   enabledWhen = "photosSelected",
      --},
      --{
      --   title = "Load From Sidecar",
      --   file = "MenuItemLoadSidecar.lua",
      --   enabledWhen = "photosSelected",
      --},
      {
         title = "Create &Snapshot",
         file = "MenuItemCreateSnapshot.lua",
         enabledWhen = "photosSelected",
      },

   },
}
