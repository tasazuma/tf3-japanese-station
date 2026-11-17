local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_tracks", order = 11 },
			},
		},
		description = {
			name = _("JPST_TRACK_SIMPLE_CATENARY_NAME"),
			description = _("JPST_TRACK_DESC"),
			icon = "::/infrastructure/track/simple/simple_catenary.tga",
			previewIcon = "::/infrastructure/track/simple/simple_catenary_preview.tga",
		},
		type = "jpst_track",
		metadata = {
			track = true,
			jpst_width = 5,
			jpst_level = "ground",
			jpst_trackTemplate = "::/infrastructure/track/simple/simple_catenary.street_template",
			jpst_catenary = true,
			jpst_noPole = false,
			catenaryAdd = nil,
			catenaryRemove = "jpst_station::/stations/jpst/jpst_track_simple.module",
			price = 40000,
			maintenanceCost = 4000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@track.updateFn",
			params = {
				template = "::/infrastructure/track/simple/simple_catenary.street_template",
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
