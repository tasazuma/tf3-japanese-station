local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_tracks", order = 122 },
			},
		},
		description = {
			name = _("JPST_TRACK_ELEVATED_STANDARD_CATENARY_NOPOLE_NAME"),
			description = _("JPST_TRACK_ELEVATED_DESC"),
			icon = "::/infrastructure/track/standard/standard_catenary.tga",
			previewIcon = "::/infrastructure/track/standard/standard_catenary_preview.tga",
		},
		type = "jpst_track_elevated",
		metadata = {
			track = true,
			jpst_width = 5,
			jpst_level = "elevated",
			jpst_trackTemplate = "jpst_station::/infrastructure/jpst_track/standard_catenary_nopole.street_template",
			jpst_catenary = true,
			jpst_noPole = true,
			catenaryAdd = nil,
			catenaryRemove = "jpst_station::/stations/jpst/jpst_track_elevated_standard.module",
			price = 120000,
			maintenanceCost = 12000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.updateFn",
			params = {
				template = "jpst_station::/infrastructure/jpst_track/standard_catenary_nopole.street_template",
				catenary = true,
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.getModelsFn",
			params = {},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
