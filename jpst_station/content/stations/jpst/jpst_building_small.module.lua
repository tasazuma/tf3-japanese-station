local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local config = {
	length = 22,
	depth = 17,
	height = 8,
	models = {
		"::/stations/rail/era_c/station_1_main.mdl",
		"::/stations/rail/era_c/station_1_main_end_lft.mdl",
		"::/stations/rail/era_c/station_1_main_end_rgt.mdl",
	},
}

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_building", filterCategories = { "passenger" }, order = 10 },
			},
		},
		description = {
			name = _("JPST_BUILDING_SMALL_NAME"),
			description = _("JPST_BUILDING_SMALL_DESC"),
			icon = "::/stations/rail/modular_station/main_building_1_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/main_building_1_era_c_preview@2x.tga",
			attributes = {
				cost = { 18000, -1 },
				maintenanceCost = { 3000, -1 },
			},
		},
		type = "jpst_building",
		metadata = {
			jpst_depth = 17,
			moreCapacity = { passenger = 30 },
			emissionConfig = { noise = 1, pollution = 2 },
			catchmentPassenger = { radius = 150 },
			comfortFactor = 0.1,
			price = 18000,
			maintenanceCost = 3000,
			-- street snaps behind the building, running along local X
			snapPoint = transf.transl(vec3.new(0, -24, 0)),
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@building.updateFn",
			params = config,
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@building.getModelsFn",
			params = config,
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
