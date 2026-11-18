#!/usr/bin/env python3
"""Generate the jpst_station .module.lua files (tracks, platforms, building).

Run from anywhere:  python3 tools/gen_modules.py
Edit the tables below and re-run instead of editing the generated files by hand.
"""
import re
import zipfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "jpst_station/content/stations/jpst"
MOD = "jpst_station::/stations/jpst/"
SCRIPT = MOD + "jpst_modules.script"
ERA_C = "::/stations/rail/era_c/"
ERA_A = "::/stations/rail/era_a/"
SEG_LEN = 40
MAX_BUILDING_SEGS = 8
AUDIO = "::/gui/construction/sound/buildoze_module.builder_audio"

CONTENT = OUT.parent.parent
GAME_CONTENT = Path.home() / "Library/Application Support/Steam/steamapps/common/Transport Fever 3/base/content"
NOPOLE_DIR = "infrastructure/jpst_track"
INVISIBLE_MODEL = "jpst_station::/infrastructure/jpst_track/invisible.mdl"


def nopole_template(t):
    return f"jpst_station::/{NOPOLE_DIR}/{t}_catenary_nopole.street_template"


HEADER = '''local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

'''

# level key -> (file infix, slot type suffix, string key infix, menu order offset)
LEVELS = {
    "ground": ("", "", "", 0),
    "elevated": ("elevated_", "_elevated", "ELEVATED_", 100),
}

TRACK_TYPES = [("simple", 1, 40000), ("standard", 2, 60000), ("high_speed", 3, 90000)]

PLATFORMS = [
    # key, width, stairsX, models [(file, x)], models with a stairs module in the cell, end model, border model, price
    ("5", 5, 0, [("perron_5.mdl", 0)], [("perron_5_underpass.mdl", 0)], "perron_5_end.mdl", "perron_5_border.mdl", 60000),
    ("10", 10, -2.5, [("perron_10.mdl", 0)], [("perron_10_underpass.mdl", 0)],
     "perron_10_end.mdl", "perron_5_border.mdl", 100000),
]
STAIRS_PRICE = 30000
ELEVATED_PRICE_FACTOR = 2
# vanilla platform models replaced by the generated Japanese-style ones (tools/gen_models.py)
CUSTOM_PLATFORM_MODELS = {
    "perron_5.mdl": "jpst_station::/stations/jpst/perron/jpst_perron_5.mdl",
    "perron_5_underpass.mdl": "jpst_station::/stations/jpst/perron/jpst_perron_5_underpass.mdl",
    "perron_10.mdl": "jpst_station::/stations/jpst/perron/jpst_perron_10.mdl",
    "perron_10_underpass.mdl": "jpst_station::/stations/jpst/perron/jpst_perron_10_underpass.mdl",
}


def lua_bool(b):
    return "true" if b else "false"


def lua_str_or_nil(s):
    return f'"{s}"' if s else "nil"


def track_file(t, cat, infix, nopole=False):
    return f"jpst_track_{infix}{t}{'_catenary' if cat else ''}{'_nopole' if nopole else ''}"


def write(name, text):
    (OUT / f"{name}.module.lua").write_text(text)


def gen_tracks():
    for level, (infix, slot_suffix, str_infix, order_off) in LEVELS.items():
        factor = ELEVATED_PRICE_FACTOR if level == "elevated" else 1
        for t, order, price in TRACK_TYPES:
            price *= factor
            for cat, nopole in ((False, False), (True, False), (True, True)):
                other = MOD + track_file(t, not cat, infix) + ".module"
                c = "_catenary" if cat else ""
                tmpl = nopole_template(t) if nopole else f"::/infrastructure/track/{t}/{t}{c}.street_template"
                key = f"{t.upper()}{c.upper()}{'_NOPOLE' if nopole else ''}"
                # no-pole tracks are electrified only; adding catenary to the bare track gives the normal poles
                add = None if cat else other
                write(track_file(t, cat, infix, nopole), HEADER + f'''function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_tracks", order = {order_off + order * 10 + (1 if cat else 0) + (1 if nopole else 0)} }},
			}},
		}},
		description = {{
			name = _("JPST_TRACK_{str_infix}{key}_NAME"),
			description = _("JPST_TRACK_{str_infix}DESC"),
			icon = "::/infrastructure/track/{t}/{t}{c}.tga",
			previewIcon = "::/infrastructure/track/{t}/{t}{c}_preview.tga",
		}},
		type = "jpst_track{slot_suffix}",
		metadata = {{
			track = true,
			jpst_width = 5,
			jpst_level = "{level}",
			jpst_trackTemplate = "{tmpl}",
			jpst_catenary = {lua_bool(cat)},
			jpst_noPole = {lua_bool(nopole)},
			catenaryAdd = {lua_str_or_nil(add)},
			catenaryRemove = {lua_str_or_nil(other if cat else None)},
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@track.updateFn",
			params = {{
				template = "{tmpl}",
				catenary = {lua_bool(cat)},
			}},
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@track.getModelsFn",
			params = {{}},
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


INVISIBLE_MDL = '''function data()
return {
	boundingInfo = { bbMax = { 0.1, 0.1, 0.1 }, bbMin = { -0.1, -0.1, 0 } },
	-- same shape as the vanilla stations/air/misc/invisible.mdl, with a tiny collider
	collider = { params = { halfExtents = { 0.05, 0.05, 0.05 } }, transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, type = "BOX" },
	lods = {
		{
			node = { name = "RootNode", transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } },
			visibleFrom = 0,
			visibleTo = 1,
		},
	},
	metadata = {},
	version = 2,
}
end
'''


def gen_nopole_track_types():
    """Hidden station-only copies of the vanilla electrified tracks whose catenary poles are invisible
    (the wires stay). Generated from the game files; the output is committed, so this only needs the
    game when the vanilla tracks change."""
    zpath = GAME_CONTENT / "infrastructure/track.zip"
    out = CONTENT / NOPOLE_DIR
    if not zpath.exists():
        print("skip no-pole track types (game not found):", zpath)
        return
    out.mkdir(parents=True, exist_ok=True)
    (out / "invisible.mdl").write_text(INVISIBLE_MDL)
    with zipfile.ZipFile(zpath) as z:
        for t in TRACK_TYPES:
            t = t[0]
            base = f"::/infrastructure/track/{t}/"
            style = z.read(f"track/{t}/{t}.street.lua").decode()
            style = re.sub(r'(catenary(?:Multi(?:Girder|InnerPole|Pole)|Pole)Model\s*=\s*)"[^"]*"',
                           lambda m: f'{m.group(1)}"{INVISIBLE_MODEL}"', style)
            # the copy lives elsewhere, so the vanilla-relative model/material names need absolute paths
            style = re.sub(r'"(?!::/|jpst_station::/)([^"]+\.(?:mdl|mtl))"', lambda m: f'"{base}{m.group(1)}"', style)
            (out / f"{t}_nopole.street.lua").write_text(HEADER_COMMENT + style)
            tmpl = z.read(f"track/{t}/{t}_catenary.street_template.lua").decode()
            tmpl = re.sub(r"availability\s*=\s*\{[^}]*\}", "availability = { yearFrom = 100000, yearTo = 0 }", tmpl)
            tmpl = re.sub(r"menuCategory\s*=\s*\{.*?\n\t\t\},\n", "menuCategory = { categories = {} },\n", tmpl,
                          flags=re.S)
            tmpl = re.sub(r'streetStyle\s*=\s*"[^"]*"', f'streetStyle = "jpst_station::/{NOPOLE_DIR}/{t}_nopole.street"',
                          tmpl)
            (out / f"{t}_catenary_nopole.street_template.lua").write_text(HEADER_COMMENT + tmpl)


HEADER_COMMENT = "-- Generated by tools/gen_modules.py from the vanilla track; do not edit by hand.\n"

BRIDGE_DIR = "infrastructure/bridge"


def gen_viaduct_bridge():
    """Hidden station-only copy of the vanilla concrete bridge whose piers are invisible: the station
    draws its own rigid-frame viaduct (columns and beams) under the elevated rows."""
    zpath = GAME_CONTENT / "infrastructure/bridge.zip"
    if not zpath.exists():
        print("skip viaduct bridge (game not found):", zpath)
        return
    with zipfile.ZipFile(zpath) as z:
        src = z.read("bridge/concrete.bridge.lua").decode()
    src = src.replace('require "::/infrastructure/bridge/bridgeutil2.lua"', 'require "::/infrastructure/bridge/bridgeutil2.lua"')
    src = src.replace('local newdir = "/infrastructure/bridge/concrete/"', 'local newdir = "::/infrastructure/bridge/concrete/"')
    src = re.sub(r'newdir \.\. "c_pillar_small_\w+\.mdl"', f'"{INVISIBLE_MODEL}"', src)
    # the parapets would stand on the platform edge and clip through the tactile paving
    src = re.sub(r'newdir \.\. "c_6_rep_(?:low_)?[lr]\.mdl"', f'"{INVISIBLE_MODEL}"', src)
    # abutments (wing walls) would poke up beside the platform where a viaduct meets the ground
    src = re.sub(r'newdir \.\. "c_abut_\w+\.mdl"', f'"{INVISIBLE_MODEL}"', src)
    src = re.sub(r'icon = "concrete.tga"', 'icon = "::/infrastructure/bridge/concrete.tga"', src)
    src = re.sub(r"availability\s*=\s*\{[^}]*\}", "availability = { yearFrom = 100000, yearTo = 0 }", src)
    src = re.sub(r"menuCategory\s*=\s*\{.*?\n\t\},\n", "menuCategory = { categories = {} },\n", src, flags=re.S)
    # root-relative paths ("/terrain/...") would resolve inside this mod; point them at the game
    src = re.sub(r'= "/', '= "::/', src)
    assert '"/' not in src
    assert "c_pillar_small_bot_l.mdl" not in src and "yearFrom = 100000" in src and "categories = {} }" in src
    out = CONTENT / BRIDGE_DIR
    out.mkdir(parents=True, exist_ok=True)
    (out / "jpst_viaduct.bridge.lua").write_text(
        "-- Generated by tools/gen_modules.py from the vanilla concrete bridge; do not edit by hand.\n" + src)


# Platform furniture in the platform frame (x across, y along -20..20, z above the track bed).
# roofless = true: only placed when the platform segment has no roof (like vanilla lightpoles).
# label = "number" gets the track numbers (labels 1-2: track on -X, 3-4: track on +X), "name" the station name.
SIGNS = """	signs = {
		-- kept between the roof pillars (every 10 m from y = -20) and clear of the stairwells (5 < |y| < 9.5)
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = -15, z = 1.1, roofless = true },
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = 15, z = 1.1, roofless = true },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = -15, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = 15, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_perron_number.mdl", y = -12.5, z = 3.5, label = "number" },
	},
"""


def gen_platforms():
    for level, (infix, slot_suffix, str_infix, order_off) in LEVELS.items():
        factor = ELEVATED_PRICE_FACTOR if level == "elevated" else 1
        for i, (key, w, sx, models, stair_models, end, border, price) in enumerate(PLATFORMS):
            price *= factor
            icon = "platform_passenger_era_c"

            def model_list(lst):
                return "\n".join(f'\t\t{{ id = "{CUSTOM_PLATFORM_MODELS.get(m, ERA_C + m)}", x = {x} }},'
                                 for m, x in lst)
            ms = model_list(models)
            sms = model_list(stair_models)
            write(f"jpst_platform_{infix}island_{key}", HEADER + f'''local config = {{
	width = {w},
	stairsX = {sx},
	models = {{
{ms}
	}},
	stairModels = {{
{sms}
	}},
	endModel = "{ERA_C}{end}",
	borderModel = "{ERA_C}{border}",
{SIGNS}}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_platforms", filterCategories = {{ "passenger" }}, order = {order_off + 10 + i} }},
			}},
		}},
		description = {{
			name = _("JPST_PLATFORM_{str_infix}{key.upper()}_NAME"),
			description = _("JPST_PLATFORM_{str_infix}DESC"),
			icon = "::/stations/rail/modular_station/{icon}.tga",
			previewIcon = "::/stations/rail/modular_station/{icon}_preview.tga",
		}},
		type = "jpst_platform{slot_suffix}",
		metadata = {{
			platform = true,
			passenger_platform = true,
			jpst_width = {w},
			jpst_level = "{level}",
			price = {price},
			maintenanceCost = {price // 6},
			emissionConfig = {{ noise = 1, pollution = 5 }},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@platform.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@platform.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


def gen_stairs():
    write("jpst_stairs_basic", HEADER + f'''function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_platforms", filterCategories = {{ "passenger" }}, order = 140 }},
			}},
		}},
		description = {{
			name = _("JPST_STAIRS_BASIC_NAME"),
			description = _("JPST_STAIRS_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
			attributes = {{
				cost = {{ {STAIRS_PRICE}, -1 }},
				maintenanceCost = {{ {STAIRS_PRICE // 10}, -1 }},
			}},
		}},
		type = "jpst_stairs",
		metadata = {{
			jpst_stairs = true,
			price = {STAIRS_PRICE},
			maintenanceCost = {STAIRS_PRICE // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@stairs.updateFn",
			params = {{}},
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@stairs.getModelsFn",
			params = {{}},
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


def building_slot_type(size):
    return "jpst_building" if size <= 1 else f"jpst_building_{size}"


def gen_building():
    write("jpst_building_small", HEADER + f'''local config = {{
	length = 22,
	depth = 17,
	height = 8,
	models = {{
		"{ERA_C}station_1_main.mdl",
		"{ERA_C}station_1_main_end_lft.mdl",
		"{ERA_C}station_1_main_end_rgt.mdl",
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_building", filterCategories = {{ "passenger" }}, order = 10 }},
			}},
		}},
		description = {{
			name = _("JPST_BUILDING_SMALL_NAME"),
			description = _("JPST_BUILDING_SMALL_DESC"),
			icon = "::/stations/rail/modular_station/main_building_1_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/main_building_1_era_c_preview@2x.tga",
			attributes = {{
				cost = {{ 18000, -1 }},
				maintenanceCost = {{ 3000, -1 }},
			}},
		}},
		type = "jpst_building",
		metadata = {{
			jpst_depth = 17,
			moreCapacity = {{ passenger = 30 }},
			emissionConfig = {{ noise = 1, pollution = 2 }},
			catchmentPassenger = {{ radius = 150 }},
			comfortFactor = 0.1,
			price = 18000,
			maintenanceCost = 3000,
			-- street snaps behind the building, running along local X
			snapPoint = transf.transl(vec3.new(0, -24, 0)),
		}},
		updateScript = {{
			fileName = "{SCRIPT}@building.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@building.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


def brick_models(k):
    """Vanilla era_a brick station: main hall in the middle block, wings elsewhere (one block = 40 m)."""
    mi = (k - 1) // 2
    out = []
    for b in range(k):
        x = (b - (k - 1) / 2) * SEG_LEN
        main = b == mi
        out.append(("station_3_main" if main else "station_3", x))
        for side, nb in (("lft", b - 1), ("rgt", b + 1)):
            if not 0 <= nb < k:
                piece = "station_3_main_end" if main else "station_3_end"
            elif main:
                piece = "station_3_main_end"  # vanilla: main hall next to a wing keeps its end piece
            elif nb == mi:
                piece = "station_3_con_2"
            else:
                piece = "station_3_con_3"
            out.append((f"{piece}_{side}", x))
    return out


def gen_brick_buildings():
    for k in range(1, MAX_BUILDING_SEGS + 1):
        models = "\n".join(
            f'\t\t{{ id = "{ERA_A}{m}.mdl", x = {x:g} }},' for m, x in brick_models(k))
        price = 60000 * k
        write(f"jpst_building_brick_{k}", HEADER + f'''-- generated by tools/gen_modules.py: red brick station building over {k} segment(s) ({k * SEG_LEN} m)
local config = {{
	length = {k * SEG_LEN},
	depth = 40,
	height = 16,
	models = {{
{models}
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_building", filterCategories = {{ "passenger" }}, order = {100 + k} }},
			}},
		}},
		description = {{
			name = _("JPST_BUILDING_BRICK_{k}_NAME"),
			description = _("JPST_BUILDING_BRICK_DESC"),
			icon = "::/stations/rail/modular_station/main_building_3_era_a.tga",
			previewIcon = "::/stations/rail/modular_station/main_building_3_era_a_preview@2x.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {10000 * k}, -1 }},
			}},
		}},
		type = "{building_slot_type(k)}",
		metadata = {{
			jpst_depth = 40,
			moreCapacity = {{ passenger = {100 * k} }},
			emissionConfig = {{ noise = 1, pollution = {5 * k} }},
			catchmentPassenger = {{ radius = 250 }},
			comfortFactor = 0.2,
			price = {price},
			maintenanceCost = {10000 * k},
			snapPoint = transf.transl(vec3.new(0, -47, 0)),
		}},
		updateScript = {{
			fileName = "{SCRIPT}@building.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@building.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


STREETS = "::/assets/streets/"
BENCH = "::/stations/air/airport/ap_bench.mdl"
TREE = "::/assets/vegetation/trees/brleaf_01/brleaf_01.mdl"
BORDER = "::/infrastructure/street/shared/street_border.gtex"
PLAZAS = {
    # name: (ground fill texture, models per 40 m cell as (model, x, y, rotZ), price per cell, menu order)
    "paved": ("::/buildings/shared/building_paving_fill.gtex", [
        (STREETS + "street_light_eu_c.mdl", 12, 12, 0),
        (STREETS + "street_light_eu_c.mdl", -12, -12, 180),
        (BENCH, -12, 8, 0),
        (BENCH, 12, -8, 180),
        (STREETS + "trash_standing_c.mdl", -9, 12, 0),
    ], 8000, 10),
    "green": ("::/terrain/materials/grass_cutted_01/grass_cutted_01.gtex", [
        (TREE, 11, 11, 0),
        (TREE, -11, -11, 90),
        ("::/assets/buildings/res/flower_pots/raised_bed_c.mdl", -11, 11, 0),
        (BENCH, 11, -8, 180),
    ], 6000, 20),
}
PLAZA_SIZES = [(1, 1), (2, 1), (2, 2)]


def forecourt_slot_type(w, h):
    return "jpst_forecourt" if (w, h) == (1, 1) else f"jpst_forecourt_{w}x{h}"


def gen_forecourts():
    for name, (fill, models, cell_price, base_order) in PLAZAS.items():
        cell_models = "\n".join(
            f'\t\t{{ id = "{m}", x = {x}, y = {y}, rotZ = {r} }},' for m, x, y, r in models)
        for i, (w, h) in enumerate(PLAZA_SIZES):
            price = cell_price * w * h
            write(f"jpst_forecourt_{name}_{w}x{h}", HEADER + f'''-- generated by tools/gen_modules.py: {name} plaza, {w} x {h} cells ({w * 40} x {h * 40} m)
local config = {{
	ground = {{
		{{ type = "FILL", key = "{fill}" }},
		{{ type = "STROKE_OUTER", key = "{BORDER}" }},
	}},
	cellModels = {{
{cell_models}
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_decoration", filterCategories = {{ "passenger" }}, order = {base_order + i} }},
			}},
		}},
		description = {{
			name = _("JPST_FORECOURT_{name.upper()}_{w}x{h}_NAME"),
			description = _("JPST_FORECOURT_{name.upper()}_DESC"),
			icon = "::/stations/street/modular_street_station/entrance.tga",
			previewIcon = "::/stations/street/modular_street_station/entrance_preview@2x.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "{forecourt_slot_type(w, h)}",
		metadata = {{
			catchmentPassenger = {{ radius = 100 }},
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@forecourt.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@forecourt.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


DECK_SIZES = [(1, 1), (2, 1), (2, 2)]
DECK_CELL_PRICE = 30000
# models per cell on the deck floor (z = 0 is the deck surface), walkways 8 m wide through the cell centre
DECK_CELL_MODELS = [
    (STREETS + "street_light_eu_c.mdl", -10, 3.5, 0),
    (STREETS + "street_light_eu_c.mdl", 3.5, -10, 90),
    (BENCH, -3.2, 12, 90),
]


def deck_slot_type(w, h):
    return "jpst_deck" if (w, h) == (1, 1) else f"jpst_deck_{w}x{h}"


def gen_decks():
    cell_models = "\n".join(
        f'\t\t{{ id = "{m}", x = {x}, y = {y}, rotZ = {r} }},' for m, x, y, r in DECK_CELL_MODELS)
    for i, (w, h) in enumerate(DECK_SIZES):
        price = DECK_CELL_PRICE * w * h
        write(f"jpst_deck_concrete_{w}x{h}", HEADER + f'''-- generated by tools/gen_modules.py: concrete pedestrian deck, {w} x {h} cells ({w * 40} x {h * 40} m)
local config = {{
	walkWidth = 8,
	stairs = "outer",
	cellModels = {{
{cell_models}
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_decoration", filterCategories = {{ "passenger" }}, order = {30 + i} }},
			}},
		}},
		description = {{
			name = _("JPST_DECK_CONCRETE_{w}x{h}_NAME"),
			description = _("JPST_DECK_CONCRETE_DESC"),
			icon = "::/stations/street/modular_street_station/entrance.tga",
			previewIcon = "::/stations/street/modular_street_station/entrance_preview@2x.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "{deck_slot_type(w, h)}",
		metadata = {{
			catchmentPassenger = {{ radius = 100 }},
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@deck.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@deck.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


ROTARY_SIZES = [(1, 1), (2, 1)]
ROTARY_CELL_PRICE = 20000
SHELTER = "::/assets/stations/street/shelter_era_c_"
# per bus stop, relative to (stop centre x, kerb y), +y into the sidewalk; buses stop heading -x
ROTARY_STOP_MODELS = [(SHELTER + "l_1.mdl", -2.9, 1.0, 0)] + [
    (SHELTER + "rep_1.mdl", x, 1.0, 0) for x in (-2.9, -1.45, 0, 1.45)] + [
    (SHELTER + "r_1.mdl", 2.9, 1.0, 0),
    ("::/assets/stations/street/bus_stop_sign_era_c_1.mdl", -6, 0.6, 0),
    (STREETS + "street_light_eu_c.mdl", 7, 0.8, 0),
]


def rotary_models(w, h):
    # trees on the island, relative to the module centre (island centre y = 0.5 for h = 1)
    xs = [0] if w == 1 else [-15, 0, 15]
    return [(TREE, x, 0.5, 0) for x in xs]


def gen_rotaries():
    stop_models = "\n".join(
        f'\t\t{{ id = "{m}", x = {x}, y = {y}, rotZ = {r} }},' for m, x, y, r in ROTARY_STOP_MODELS)
    for i, (w, h) in enumerate(ROTARY_SIZES):
        price = ROTARY_CELL_PRICE * w * h
        models = "\n".join(f'\t\t{{ id = "{m}", x = {x}, y = {y}, rotZ = {r} }},' for m, x, y, r in rotary_models(w, h))
        write(f"jpst_busrotary_basic_{w}x{h}", HEADER + f'''-- generated by tools/gen_modules.py: bus rotary, {w} x {h} cells ({w * 40} x {h * 40} m), {w} bus stop(s)
local config = {{
	stopModels = {{
{stop_models}
	}},
	models = {{
{models}
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_decoration", filterCategories = {{ "passenger" }}, order = {40 + i} }},
			}},
		}},
		description = {{
			name = _("JPST_BUSROTARY_BASIC_{w}x{h}_NAME"),
			description = _("JPST_BUSROTARY_BASIC_DESC"),
			icon = "::/stations/street/modular_street_station/passenger_platform.tga",
			previewIcon = "::/stations/street/modular_street_station/passenger_platform_preview.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "{forecourt_slot_type(w, h)}",
		metadata = {{
			catchmentPassenger = {{ radius = 100 }},
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@busrotary.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@busrotary.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


def gen_busbays():
    stop_models = "\n".join(
        f'\t\t{{ id = "{m}", x = {x}, y = {y}, rotZ = {r} }},' for m, x, y, r in ROTARY_STOP_MODELS)
    for i, (w, h) in enumerate(ROTARY_SIZES):
        price = ROTARY_CELL_PRICE * w * h // 2
        write(f"jpst_busbay_basic_{w}x{h}", HEADER + f'''-- generated by tools/gen_modules.py: parallel bus bay, {w} x {h} cells, {w} bus stop(s)
local config = {{
	stopModels = {{
{stop_models}
	}},
}}

function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_decoration", filterCategories = {{ "passenger" }}, order = {50 + i} }},
			}},
		}},
		description = {{
			name = _("JPST_BUSBAY_BASIC_{w}x{h}_NAME"),
			description = _("JPST_BUSBAY_BASIC_DESC"),
			icon = "::/stations/street/modular_street_station/passenger_platform.tga",
			previewIcon = "::/stations/street/modular_street_station/passenger_platform_preview.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "{forecourt_slot_type(w, h)}",
		metadata = {{
			jpst_bus_bay = true,
			catchmentPassenger = {{ radius = 100 }},
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@busbay.updateFn",
			params = config,
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@busbay.getModelsFn",
			params = config,
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


def gen_concourse():
    write("jpst_concourse", HEADER + f'''function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_building", filterCategories = {{ "passenger" }}, order = 20 }},
			}},
		}},
		description = {{
			name = _("JPST_CONCOURSE_NAME"),
			description = _("JPST_CONCOURSE_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {{
				cost = {{ 150000, -1 }},
				maintenanceCost = {{ 15000, -1 }},
			}},
		}},
		type = "jpst_concourse",
		metadata = {{
			jpst_concourse = true,
			moreCapacity = {{ passenger = 50 }},
			emissionConfig = {{ noise = 1, pollution = 2 }},
			catchmentPassenger = {{ radius = 200 }},
			comfortFactor = 0.1,
			price = 150000,
			maintenanceCost = 15000,
		}},
		updateScript = {{
			fileName = "{SCRIPT}@concourse.updateFn",
			params = {{}},
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@concourse.getModelsFn",
			params = {{}},
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


ASSET_RAIL = "::/assets/stations/rail/"
TICKETS = "::/assets/stations/street/tickets_era_c_1.mdl"
# Japanese rigid-frame viaduct (ラーメン高架橋) from the vanilla concrete pier piece c_pillar_small_rep_m
# (x +-1.056, y 0..3, z 0..4). It only has its two +-X faces, so each box is two pieces crossed at 90 deg.
UNDER_PILLAR = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl"
# column 1 x 1 m centred on its foot, 7.6 m up to the deck bottom (ELEVATED_Z 10 - deck 2.4)
UNDER_COLUMNS = f'''{{
				models = {{
					{{ id = "{UNDER_PILLAR}", transf = {{ 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 7.6 / 4, 0, 0, -0.5, 0, 1 }} }},
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 7.6 / 4, 0, 0.5, 0, 0, 1 }} }},
				}},
				ys = {{ -15, -5, 5, 15 }}, minGap = 6,
			}}'''
# beam 1 m wide, 1 m deep under the deck, X 0..1 (stretched across the block)
UNDER_BEAMS = f'''{{
				models = {{
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 }} }},
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 }} }},
				}},
			}}'''
# shop unit: unit cube X 0..1, Y 0..1, Z 0..1 (two crossed pieces), scaled by the update script.
# Gaps at y = 0 +-8 keep the cross lane and the street exits free.
UNDER_SHOPS = f'''{{
				models = {{
					{{ id = "{UNDER_PILLAR}", transf = {{ 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0.5, 0, 0, 1 }} }},
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 1, 0.5, 0, 1 }} }},
				}},
				depth = 2.5, height = 3.5,
				ranges = {{ {{ -19.5, -8.5 }}, {{ 8.5, 19.5 }} }},
			}}'''
UNDER_SKINS = {
    "viaduct": dict(columns=UNDER_COLUMNS, beams=UNDER_BEAMS, exitModels=[], price=40000, order=20),
    "pillars": dict(
        columns=UNDER_COLUMNS,
        beams=UNDER_BEAMS,
        order=21,
        exitModels=[
            (TICKETS, 3.5, 2.5, -90), (TICKETS, 3.5, 3.6, -90), (TICKETS, -3.5, 2.5, 90), (TICKETS, -3.5, 3.6, 90),
            (ASSET_RAIL + "era_c_trashcan.mdl", 5.5, 1.0, 0),
            (ASSET_RAIL + "era_c_double_chair.mdl", -10, 1.5, 90), (ASSET_RAIL + "era_c_double_chair.mdl", 10, 1.5, 90),
        ],
        price=80000,
    ),
    "closed": dict(columns=UNDER_COLUMNS, beams=UNDER_BEAMS, exitModels=[], exits=False, price=40000, order=23),
    "shops": dict(
        columns=UNDER_COLUMNS,
        beams=UNDER_BEAMS,
        shops=UNDER_SHOPS,
        order=22,
        exitModels=[
            (TICKETS, 3.5, 2.5, -90), (TICKETS, 3.5, 3.6, -90), (TICKETS, -3.5, 2.5, 90), (TICKETS, -3.5, 3.6, 90),
        ],
        price=120000,
    ),
}


def gen_underviaduct():
    for skin, d in UNDER_SKINS.items():
        models = "\n".join(f'\t\t\t\t{{ id = "{i}", x = {x}, y = {y}, rotZ = {r} }},' for i, x, y, r in d["exitModels"])
        key = skin.upper()
        price = d["price"]
        shops_line = ("\n\t\t\t\texits = false," if d.get("exits") is False else "") + (
            f"\n\t\t\t\tshops = {d['shops']}," if "shops" in d else "")
        params = f'''{{
				columns = {d["columns"]},
				beams = {d["beams"]},
				exitModels = {{
{models}
				}},
				hallModels = {{}},{shops_line}
			}}'''
        write(f"jpst_underviaduct_{skin}", HEADER + f'''function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_building", filterCategories = {{ "passenger" }}, order = {d["order"]} }},
			}},
		}},
		description = {{
			name = _("JPST_UNDERVIADUCT_{key}_NAME"),
			description = _("JPST_UNDERVIADUCT_{key}_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "jpst_underviaduct",
		metadata = {{
			jpst_underviaduct = true,
			moreCapacity = {{ passenger = 50 }},
			emissionConfig = {{ noise = 1, pollution = 1 }},
			catchmentPassenger = {{ radius = 200 }},
			comfortFactor = 0.1,
			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@underviaduct.updateFn",
			params = {params},
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@underviaduct.getModelsFn",
			params = {params},
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


ROOF_ERAS = [
    # vanilla model era, price
    ("a", 20000),
    ("b", 25000),
    ("c", 30000),
]


ROOF_ARMS = f'''{{
				z = 7.0,
				section = {{ 0.3, 0.5 }},
				strut = {{ width = 0.3, z0 = 5.3 }},
				ys = {{ -20, 0, 20 }},
				models = {{
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 }} }},
					{{ id = "{UNDER_PILLAR}", transf = {{ 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 }} }},
				}},
			}}'''

# (name suffix, vanilla era, price, extra params, menu order)
ROOF_COVER = """{
				z = 9.0,
				ys = { -10, 10 },
				column = 0.5,
			}"""

ROOF_SKINS = [
    ("era_a", "a", 20000, "", 150),
    ("era_b", "b", 25000, "", 151),
    ("era_c", "c", 30000, "", 152),
    ("era_c_arm", "c", 40000, f"arms = {ROOF_ARMS},", 153),
    ("era_c_cover", "c", 60000, f"cover = {ROOF_COVER},", 154),
]


def gen_roofs():
    for name, era, price, extra, order in ROOF_SKINS:
        base = f"::/stations/rail/era_{era}/"
        params = f'''{{
				roofModel = "{base}perron_5_roof.mdl",
				endModel = "{base}perron_5_roof_end.mdl",
				{extra}
			}}'''
        key = name.upper() if extra else era.upper()
        cover_meta = "\t\t\tjpst_roof_cover = true,\n" if "cover" in extra else ""
        desc = "COVER_" if "cover" in extra else ("ARM_" if extra else "")
        write(f"jpst_roof_{name}", HEADER + f'''function data()
	return {{
		availability = {{ yearFrom = 0, yearTo = 0 }},
		menuCategory = {{
			categories = {{
				{{ category = "modules_platforms", filterCategories = {{ "passenger" }}, order = {order} }},
			}},
		}},
		description = {{
			name = _("JPST_ROOF_{key}_NAME"),
			description = _("JPST_ROOF_{desc}DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_roof_era_{era}.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_roof_era_{era}_preview@2x.tga",
			attributes = {{
				cost = {{ {price}, -1 }},
				maintenanceCost = {{ {price // 10}, -1 }},
			}},
		}},
		type = "jpst_roof",
		metadata = {{
			jpst_roof = true,
{cover_meta}			price = {price},
			maintenanceCost = {price // 10},
		}},
		updateScript = {{
			fileName = "{SCRIPT}@roof.updateFn",
			params = {params},
		}},
		getModelsScript = {{
			fileName = "{SCRIPT}@roof.getModelsFn",
			params = {params},
		}},
		builderAudioRes = "{AUDIO}",
	}}
end
''')


if __name__ == "__main__":
    gen_nopole_track_types()
    gen_viaduct_bridge()
    gen_tracks()
    gen_platforms()
    gen_stairs()
    gen_roofs()
    gen_building()
    gen_brick_buildings()
    gen_concourse()
    gen_underviaduct()
    gen_forecourts()
    gen_decks()
    gen_rotaries()
    gen_busbays()
    print("generated into", OUT)
