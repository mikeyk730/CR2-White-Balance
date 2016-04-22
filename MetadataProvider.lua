local valuesFileStatus = {
   {
      value = 'shotInAuto',
      title = LOC '$$$/Metadata/Fields/FileStatus/ShotInAuto=Shot in Auto',
   },
   {
      value = 'loadedMetadata',
      title = LOC '$$$/Metadata/Fields/FileStatus/MetadataLoaded=Metadata Loaded',
   },
   {
      value = 'changedOnDisk',
      title = LOC '$$$/Metadata/Fields/FileStatus/UpdatedOnDisk=Updated on Disk',
   }
}

return {
   metadataFieldsForPhotos = {
      {
         id = 'fileStatus',
         title = LOC '$$$/Metadata/Fields/FileStatus=Metadata Status',
         dataType = 'enum',
         values = valuesFileStatus,
         readOnly = true,
         searchable = true,
         browsable = true,
         version = 1
      },
      {
         id = 'WhiteBalance',
         title = LOC '$$$/Metadata/Fields/WhiteBalance=WhiteBalance',
         dataType = 'string',
         readOnly = true,    
         searchable = true,
         browsable = true,
         version = 1
      },
      {
         id = 'WB_RGGBLevels',
         title = LOC '$$$/Metadata/Fields/WB_RGGBLevels=WB_RGGBLevels',
         dataType = 'string',
         readOnly = true
      },
      {
         id = 'WB_RGGBLevelsAsShot',
         title = LOC '$$$/Metadata/Fields/WB_RGGBLevelsAsShot=WB_RGGBLevelsAsShot',
         dataType = 'string',
         readOnly = true
      },
      {
         id = 'ColorTempAsShot',
         title = LOC '$$$/Metadata/Fields/ColorTempAsShot=ColorTempAsShot',
         dataType = 'string',
         readOnly = true
      },
      {
         id = 'WhiteBalanceOverride',
         title = LOC '$$$/Metadata/Fields/CurrentWhiteBalance=Override',
         dataType = 'string',
         readOnly = true,
         searchable = true,
         browsable = true,
      },
   },
   schemaVersion = 1
}
