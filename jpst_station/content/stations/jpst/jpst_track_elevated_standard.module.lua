local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_tracks", order = 120 },
			},
		},
		description = {
			name = _("JPST_TRACK_ELEVATED_STANDARD_NAME"),
			description = _("JPST_TRACK_ELEVATED_DESC"),
			icon = "::/infrastructure/track/standard/standard.tga",
			previewIcon = "::/infrastructure/track/standard/standard_preview.tga",
		},
		type = "jpst_track_elevated",
		metadata = {
			track = true,
			jpst_width = 5,
			jpst_level = "elevated",
			jpst_trackTemplate = "::/infrastructure/track/standard/standard.street_template",
			jpst_catenary = false,
			catenaryAdd = "jpst_station::/stations/jpst/jpst_track_elevated_standard_catenary.module",
			catenaryRemove = nil,
			price = 120000,
			maintenanceCost = 12000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.updateFn",
			params = {
				template = "::/infrastructure/track/standard/standard.street_template",
				catenary = false,
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.getModelsFn",
			params = {},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
