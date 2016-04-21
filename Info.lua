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
         title = "&Load Metadata",
         file = "MenuItemCheckWhiteBalance.lua",
      },
      {
         title = "Clear Metadata",
         file = "MenuItemClearWhiteBalance.lua",
      },
      {
         title = "&Save White Balance",
         file = "MenuItemSaveWhiteBalance.lua",
      },
      {
         title = "&Revert White Balance",
         file = "MenuItemRevertWhiteBalance.lua",
      },
      {
         title = "Save Sidecar",
         file = "MenuItemSaveSidecar.lua",
      },
      {
         title = "Load From Sidecar",
         file = "MenuItemLoadSidecar.lua",
      },
   },
}
