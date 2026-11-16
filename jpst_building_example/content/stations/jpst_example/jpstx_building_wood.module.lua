local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

-- A building "skin" for JP Modular Station (mod jpst_station).
-- The base mod does everything functional (passenger lanes, street connection, terrain); this file only
-- chooses the slot size (type), the outline (length/depth/height) and the models.
-- Building frame: origin at the middle of the front, the front (y = 0) faces the tracks,
-- +X runs along the tracks, the building extends towards -Y. One segment is 40 m.
local config = {
	length = 23, -- along the tracks (m); default 40 * segments - 2
	depth = 20,  -- away from the tracks (m); the street lane runs at y = -(depth - 3)
	height = 8,  -- collision height (m)
	models = {
		-- "file.mdl" | { id = "file.mdl", x =, y =, z =, rotZ = degrees } | { id = "file.mdl", transf = { 16 numbers } }
		"::/stations/rail/era_b/station_1_main.mdl",
		"::/stations/rail/era_b/station_1_main_end_lft.mdl",
		"::/stations/rail/era_b/station_1_main_end_rgt.mdl",
	},
}

local SCRIPT = "jpst_station::/stations/jpst/jpst_modules.script"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_building", filterCategories = { "passenger" }, order = 200 },
			},
		},
		description = {
			name = _("JPSTX_BUILDING_WOOD_NAME"),
			description = _("JPSTX_BUILDING_WOOD_DESC"),
			icon = "::/stations/rail/modular_station/main_building_1_era_b.tga",
			previewIcon = "::/stations/rail/modular_station/main_building_1_era_b_preview@2x.tga",
			attributes = {
				cost = { 20000, -1 },
				maintenanceCost = { 3000, -1 },
			},
		},
		-- jpst_building = 1 segment (40 m); jpst_building_2 .. jpst_building_8 = 2 .. 8 segments
		type = "jpst_building",
		metadata = {
			jpst_depth = 20, -- must match config.depth: the forecourt starts behind the deepest building
			moreCapacity = { passenger = 30 },
			emissionConfig = { noise = 1, pollution = 2 },
			catchmentPassenger = { radius = 150 },
			comfortFactor = 0.1,
			price = 20000,
			maintenanceCost = 3000,
			snapPoint = transf.transl(vec3.new(0, -27, 0)), -- depth + 7: the street snaps behind the building
		},
		updateScript = { fileName = SCRIPT .. "@building.updateFn", params = config },
		getModelsScript = { fileName = SCRIPT .. "@building.getModelsFn", params = config },
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
