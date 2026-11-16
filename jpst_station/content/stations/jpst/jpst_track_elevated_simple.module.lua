local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_tracks", order = 110 },
			},
		},
		description = {
			name = _("JPST_TRACK_ELEVATED_SIMPLE_NAME"),
			description = _("JPST_TRACK_ELEVATED_DESC"),
			icon = "::/infrastructure/track/simple/simple.tga",
			previewIcon = "::/infrastructure/track/simple/simple_preview.tga",
		},
		type = "jpst_track_elevated",
		metadata = {
			track = true,
			jpst_width = 5,
			jpst_level = "elevated",
			jpst_trackTemplate = "::/infrastructure/track/simple/simple.street_template",
			jpst_catenary = false,
			catenaryAdd = "jpst_station::/stations/jpst/jpst_track_elevated_simple_catenary.module",
			catenaryRemove = nil,
			price = 80000,
			maintenanceCost = 8000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.updateFn",
			params = {
				template = "::/infrastructure/track/simple/simple.street_template",
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
