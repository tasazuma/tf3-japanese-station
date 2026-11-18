local tu = require "/scripts/tex_util.tl"

function data()
return {
	texture = tu.makeMaterialIndexTexture("mat/platform_floor.tga", "REPEAT", "REPEAT"),
	texSize = { 4.0, 4.0 },
	materialIndexMap = {
		[255] = "::/terrain/materials/asphalt_03/asphalt_03.tmat",
		[128] = "::/terrain/materials/asphalt_05/asphalt_05.tmat",
		[64] = "::/terrain/materials/sand_yellow/sand_yellow.tmat",
	},
	priority = 16
}
end
