local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_tracks", order = 10 },
			},
		},
		description = {
			name = _("JPST_TRACK_SIMPLE_NAME"),
			description = _("JPST_TRACK_DESC"),
			icon = "::/infrastructure/track/simple/simple.tga",
			previewIcon = "::/infrastructure/track/simple/simple_preview.tga",
		},
		type = "jpst_track",
		metadata = {
			track = true,
			jpst_width = 5,
			jpst_level = "ground",
			jpst_trackTemplate = "::/infrastructure/track/simple/simple.street_template",
			jpst_catenary = false,
			catenaryAdd = "jpst_station::/stations/jpst/jpst_track_simple_catenary.module",
			catenaryRemove = nil,
			price = 40000,
			maintenanceCost = 4000,
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
