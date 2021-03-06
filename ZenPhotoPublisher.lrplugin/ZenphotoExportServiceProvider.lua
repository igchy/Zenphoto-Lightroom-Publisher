--[[----------------------------------------------------------------------------

ZenphotoExportServiceProvider.lua
Export service provider description for Lightroom Zenphoto uploader

------------------------------------------------------------------------------]]
local LrBinding         = import 'LrBinding'
local LrView            = import 'LrView'
local LrApplication     = import 'LrApplication'
local LrDialogs         = import 'LrDialogs'
local LrFunctionContext	= import 'LrFunctionContext'
local LrHttp            = import 'LrHttp'
local LrColor           = import 'LrColor'
local LrDate           	= import 'LrDate'
local LrLogger          = import 'LrLogger'
local prefs 			= import 'LrPrefs'.prefsForPlugin()
local LrPathUtils		= import 'LrPathUtils'
local LrStringUtils		= import 'LrStringUtils'
local LrFileUtils		= import 'LrFileUtils'
local LrTasks			= import 'LrTasks'
local LrProgressScope	= import 'LrProgressScope'

local util              = require 'Utils'

local bind = LrView.bind
local share = LrView.share

--============================================================================--

	-- ZenPhoto plugin
require 'ZenphotoPublishSupport'
require 'ZenphotoPublishSupportExtention'

exportServiceProvider = {}

for name, value in pairs( ZenphotoPublishSupport ) do
	exportServiceProvider[ name ] = value
end

exportServiceProvider.supportsIncrementalPublish = 'only'
--exportServiceProvider.hideSections = { 'exportLocation', 'postProcessing', 'metadata', 'fileNaming', 'watermarking' }
exportServiceProvider.hideSections = { 'exportLocation' }
exportServiceProvider.allowFileFormats = { 'JPEG' }
exportServiceProvider.allowColorSpaces = { 'sRGB'  }
exportServiceProvider.hidePrintResolution = true
exportServiceProvider.exportPresetFields = {
		{ key = 'LR_jpeg_quality', default = 100 },	
		{ key = 'LR_size_resizeType', default = 'longEdge' },
		{ key = 'LR_size_maxHeight', default = '1024' },
		{ key = 'LR_size_maxWidth', default = '1024' },
		{ key = 'LR_outputSharpeningMedia', default = 'screen' },
		{ key = 'LR_size_doNotEnlarge', default = 'true' },
		{ key = 'instance_ID', default = 00000 },
		{ key = 'newService', default = "Please fill out the available sections and save to enable this service" },
		{ key = 'accountStatus', default = "Not Available" },
		{ key = 'host', default = "yourzenphotoinstall.com" },
		{ key = 'loginButtonTitle', default = "DISABLED" },
		{ key = 'instanceKey', default=(import 'LrDate').currentTime()},
		{ key = 'uploadMethod', default = "POST" },
		{ key = 'deepscan', default = true },
	}
--------------------------------------------------------------------------------

function exportServiceProvider.startDialog( propertyTable )
log:trace("exportServiceProvider.startDialog")

	-- clear login if it's a new publishing instance
	if not propertyTable.LR_editingExistingPublishConnection and propertyTable.LR_isExportForPublish then
	log:info('guess this is a new publishing service')
	end
	
	--This is a new service so return
	if not propertyTable.LR_publishService then	return end
	
	local publishService = propertyTable.LR_publishService

	instanceID = publishService.localIdentifier
		
		--set Gobal instance mandotory to support multiple publisher instances.
propertyTable.instance_ID = instanceID
	
	log:info("instanceID:" ..instanceID)
			-- creating instance table in prefs
				if prefs[instanceID] == nil then
					log:info("Creating instance table (exportServiceProvider)")
					prefs[instanceID] = {}
			log:trace("Inserting new instance")
				table.insert(prefs[instanceID],
					{
					host = propertyTable.host, 
					instance_ID = propertyTable.instance_ID,
					webpath = propertyTable.webpath,
					uploadMethod = propertyTable.uploadMethod,
					username = "yourname",
					password = "password",
					token = false,
					deepscan = propertyTable.deepscan
					}
				)	
				--adds album table
	if not prefs[instanceID].albums then
	log:info("Creating albums table")
	  --prefs[instanceID].albums = nil
		prefs[instanceID].albums = {}
	end	
end			
			
	prefs[instanceID].serviceIsRunning = publishService
log:info("prefs.serviceIsRunning ".. table_show(publishService))
	if prefs[instanceID].serviceIsRunning then
		propertyTable.serviceIsRunning = true
		propertyTable.instanceID = instanceID
	else
		propertyTable.serviceIsRunning = false
		propertyTable.instanceID = nil
	end
	
	-- Make sure we're logged in.
	require 'ZenphotoUser'
	ZenphotoUser.initLogin( propertyTable )

	propertyTable.host = prefs[instanceID].host or propertyTable.host
	prefs[instanceID].host = propertyTable.host
	propertyTable:addObserver( 'host', function() 
		prefs[instanceID].host = propertyTable.host
		ZenphotoUser.resetLogin( propertyTable )
	end)
	
	propertyTable.deepscan = prefs[instanceID].deepscan or true
	prefs[instanceID].deepscan = propertyTable.deepscan
	propertyTable:addObserver( 'deepscan', function() 
		prefs[instanceID].deepscan = propertyTable.deepscan
		ZenphotoUser.resetLogin( propertyTable )
	end)

	propertyTable.uploadMethod = prefs[instanceID].uploadMethod or 'POST'
	prefs[instanceID].uploadMethod = propertyTable.uploadMethod
	propertyTable:addObserver( 'uploadMethod', function() 
		prefs[instanceID].uploadMethod = propertyTable.uploadMethod
	end)	
	
log:debug(table_show(prefs))
end

--------------------------------------------------------------------------------
function exportServiceProvider.sectionsForTopOfDialog( f, propertyTable )
log:info('exportServiceProvider.sectionsForTopOfDialog')

--cleaning up old data
if instanceID then
if prefs[instanceID].missing then
prefs[instanceID].missing = nil
end
table.remove (prefs[instanceID], missing)
table.remove (prefs,instanceTable)
prefs.instanceTable = nil
end

    return {
			{
			title = "Login to ZenPhoto",
			synopsis = bind 'accountStatus',
			bind_to_object = propertyTable,
			
			f:row {
				f:static_text {
					title = 'Enter ZenPhoto-URL (without \'http://\'):',
					width = 300,
				},

				f:edit_field {
					fill_horizontal = 1,
					value = bind 'host',
					immediate = true,
				},
			},
								f:static_text {
					fill_horizontal = 1,
					title = bind 'newService',
					alignment = 'right',
				},
f:group_box {			
	title = "User Login",
	fill_horizontal = 1,
f:row {
	spacing = f:label_spacing(),
				f:picture {
					value = _PLUGIN:resourceId('zenphoto_album.png'),
					},
	f:column {
	spacing = f:control_spacing(),
	fill_horizontal = 1,
	f:group_box {
		fill_horizontal = 1,
			f:row {
				f:static_text {
					fill_horizontal = 1,
					title = bind 'accountStatus',
					alignment = 'right',
				},
				f:push_button {
					width = share 'button_width',
					title = bind 'loginButtonTitle',
					enabled = bind {
						keys = { 'loginButtonEnabled', 'serviceIsRunning' }, -- bind to both keys
						operation = function( binder, values, fromTable ) 
							return values.loginButtonEnabled == true and values.serviceIsRunning == true
						end,
						},
					action = function()
						LrFunctionContext.postAsyncTaskWithContext ('LoginTask', function() 
																					ZenphotoUser.login( propertyTable )
																				 end
																   )						
					end,
				},
			},
----------------------------
	f:checkbox {
		title = "Detailed scan",
		checked_value = 'true',
		tooltip = "(more accurate results if you have multiple images with the same name validates filename and capture time.)",
		unchecked_value = 'false',
		value = bind 'deepscan',
	},
},

},
},
},
			f:row {
				margin_top = 10,

				f:static_text {
					fill_horizontal = 1,
					height_in_lines = 9,
					width = 70,
					title = 'Once you have logged-in, close the Publishing Manager and go to the "Publish Services" menu on the left side of the Lightroom window. There you will find the "Zenphoto Publisher" with a default node called "Sync Albums/Images". Right-click on it press the appropriate button.." from the menu. \n\nA dialog will be opened. \n\nFurther details and instructions can be found on http://philbertphotos.github.com/Zenphoto-Lightroom-Publisher.',
				},
			},
		},
	}
end

--------------------------------------------------------------------------------
function exportServiceProvider.sync( fullsync, publishService, context, publishSettings )
log:trace('exportServiceProvider.sync')

		--set instance ID
	local instanceID = publishSettings.instance_ID
	
	local catalog = import 'LrApplication'.activeCatalog()
	local albums = ZenphotoAPI.getAlbums()
	LrFunctionContext.callWithContext('sync Albums', function(context)

		local progressScope = LrDialogs.showModalProgressDialog({
			title = 'Syncing albums',
			caption = 'loading albums info from server',
			cannotCancel = false,
			functionContext = context,
		})

		for i, collection in pairs ( publishService:getChildCollections() ) do
			
			infoSummary = collection:getCollectionInfoSummary()
			if infoSummary and not infoSummary.isDefaultCollection then
				catalog:withWriteAccessDo( "delete local lightroom collections (albums)", function()
					collection:delete()
				end)
			end
		end


		local albumtable = {}	
		for i, album in pairs ( albums ) do
			log:info("add album: -" .. tostring(album.name) .. "-")

			progressScope:setCaption('reading album: ' .. tostring(album.name) .. ' (' .. i .. ' of ' .. #albums .. ')' )
			progressScope:setPortionComplete( i, #albums )
			if progressScope:isCanceled() then break end
		--TODO Parent and Sub Albums
		--[[if not publishServiceExtention.collectionNameExists(publishService,'+'..album.name) then
				catalog:withWriteAccessDo( "create collection set", function()
					if album.hasSubalbum == '1' then
					pubCollectionSet = publishService:createPublishedCollectionSet( '+'..album.name, nil, true )
					pubCollectionSet:setRemoteId( album.id )
					pubCollectionSet:setRemoteUrl( album.url )
					end
				end)
			else
				LrDialogs.message('Album '..album.name..' already exists', 'This album is not created in Lightroom. Albumnames must be unique.','info')
			end--]]
			
			if not publishServiceExtention.collectionNameExists(publishService, album.name) then
				catalog:withWriteAccessDo( "create album", function()
					--pubCollection = publishService:createPublishedCollection( album.name, pubCollectionSet, true )					
					pubCollection = publishService:createPublishedCollection( album.name, nil, true )					
					pubCollection:setCollectionSettings(album)
					pubCollection:setRemoteId( album.id )
					pubCollection:setRemoteUrl( album.url )				
				end)
			else
				LrDialogs.message('Album '..album.name..' already exists', 'This album is not created in Lightroom. Albumnames must be unique.','info')
			end
					--table.insert( albumtable, { album = album.name,parent = album.parentFolder,subalbum = album.hasSubalbum} )
			
				
		end
		progressScope:done()
		--log:info('AlbumTable', table_show(albumtable))
	end)
		
	LrTasks.yield()
	
	--
	--	sync images for all collections
	--
	if fullsync then
		local syncmissing = {}
		
		log:info('start syncing album and images')
		for i, pubCollection in pairs (publishService:getChildCollections()) do

			LrTasks.yield()
			
			remoteId = pubCollection:getRemoteId()
			if remoteId and pubCollection:getName() ~= 'Sync Albums/Images' then
				LrFunctionContext.callWithContext('sync Images', function(context)
					result = publishServiceExtention.getImages( pubCollection, remoteId, publishSettings, context)
					syncmissing = result
					log:info("exportServiceProvider.missing table result ", table_show(result))
					--syncmissing = Utils.joinTables(syncmissing, result)
				end)
			end
		end
		log:info('finish syncing album and images')
		
--		if #syncmissing > 0 then Utils.showMissingFilesDialog(syncmissing) end
		log:trace('missing greater than 0')
	end
end
--------------------------------------------------------------------------------
--
--
--	HELPER function to delete missing images
--
--
function exportServiceProvider.deleteMissingPhotos(arrayOfPhotoNames)
log:trace('exportServiceProvider.deleteMissingPhotos')
	result = LrDialogs.confirm( 'Delete the "not found images" from the server', 
								'Do you really want to delete the images that were not found on your Zenphoto webserver?',
								'Delete', 
								'Cancel' 
								)
	
	if result == 'ok' then 

		LrFunctionContext.callWithContext('delete images', function(context)

			local progressScope = LrDialogs.showModalProgressDialog({
				title = 'Delete images from server',
				cannotCancel = false,
				functionContext = context,
			})

			for i, photoName in ipairs( arrayOfPhotoNames ) do

				progressScope:setCaption('delete image: ' .. tostring(photoName) .. ' (' .. i .. ' of ' .. #arrayOfPhotoNames .. ')' )
				progressScope:setPortionComplete( i, #arrayOfPhotoNames )
				if progressScope:isCanceled() then break end

				local errors = ZenphotoAPI.deletePhoto({	name = photoName,	})

				if errors ~= '' then
					LrDialogs.message( 'Unable to delete image with name: ' .. photoName, errors, 'critical' )
					log:fatal('Unable to delete image with name: ' .. photoName, errors, 'critical')
				end
			end
			
			progressScope:done()
		end)
			
	end

end


--------------------------------------------------------------------------------


function exportServiceProvider.processRenderedPhotos( functionContext, exportContext )
	log:trace('exportServiceProvider.processRenderedPhotos')

	-- Check for photos that have been uploaded already.
	local exportSession = exportContext.exportSession

	-- Make a local reference to the export parameters.
	local nPhotos = exportSession:countRenditions()

	-- Set progress title.
	local progressScope = exportContext:configureProgress{
												title = nPhotos > 1
													and LOC( "$$$/zenphoto/Upload/Progress=Uploading ^1 photos to ZenPhoto", nPhotos )
													or LOC "$$$/zenphoto/Upload/Progress/One=Uploading one photo to ZenPhoto",
										}
	local propertyTable = {}

	-- check if in Publish Service or not ("not" is the normal export)
	local pubCollection = exportContext.publishedCollection
	-- show the custom export dialog

	infoSummary = pubCollection:getCollectionInfoSummary()
	local params = infoSummary.collectionSettings

	-- Iterate through photo renditions.
	for i, rendition in exportContext:renditions{ stopIfCanceled = true } do

		local result = {}
		local errors = nil
		local photo = rendition.photo
		local photoname = photo:getFormattedMetadata('fileName')
		local photodate = photo:getFormattedMetadata('dateTimeOriginal')
		
		params[photoname] = string.gsub(tostring(photo), "[(%a%p%s)]", "")
		
		log:info('Getting next photo...' .. photoname)
		
		if not rendition.wasSkipped then
			
			-- render photo
			local success, pathOrMessage = rendition:waitForRender()
			-- Check for cancellation again after photo has been rendered.
			if progressScope:isCanceled() then break end
			
			--
			-- if redition was successful
			--
			if success then

				--if prefs.uploadMethod == 'POST' then
				--	result, errors = ZenphotoAPI.uploadPhoto (pathOrMessage, params)
				--else
					-- read file
					local filename  = LrPathUtils.leafName( pathOrMessage )
					local file = assert(io.open(pathOrMessage, "rb"))
					local photoBinaryData = file:read("*all")
					file:close()
					-- convert to base64
					local base64Data = LrStringUtils.encodeBase64(photoBinaryData)
					result, errors = ZenphotoAPI.uploadImage ( filename, params, base64Data )
				--end
					
				-- delete tmp-image file
				LrFileUtils.delete( pathOrMessage )

				--
				-- if image uploaded OK
				--
				if result then 
					log:info ('Image ' .. photoname .. ' uploaded successfully')
					rendition:recordPublishedPhotoId( result.id )
					rendition:recordPublishedPhotoUrl( result.url )
--write information to metadata			
log:info ('write information to custom metadata')
        photo.catalog:withWriteAccessDo( "set.metadata",
                                    function()
	photo:setPropertyForPlugin(_PLUGIN,"uploaded","true")
	photo:setPropertyForPlugin(_PLUGIN,"albumurl",result.url)
                                    end)
				else
					-- upload was not successful and returned an error
					LrDialogs.message( 'Unable to upload image ' .. photoname, errors, 'critical' )
					log:fatal( 'Unable to upload image ' .. photoname, errors, 'critical' )
				end
				-- Adjust progesss scope
				progressScope:setPortionComplete(i, nPhotos)
				
			end -- if success then
		end
		
	end -- for i renditions

	progressScope:done()
end

return exportServiceProvider