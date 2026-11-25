extends RefCounted
## Typed, read-only view of a `world` Dictionary (World.DATA) for the simulation.
## Every world key the sim reads is looked up here and nowhere else.

const WorldDef := preload("res://core/world.gd")
const Self := preload("res://core/sim/sim_world.gd")

var field_elev := 0.0
var course_deg := 0.0
var glide_deg := 0.0
var tch := 0.0
var range_nm := 0.0
var runway_heading := 0.0
var runway_length_nm := 0.0
var sep_lateral_nm := 0.0
var sep_vertical_ft := 0.0
var terr_x := PackedFloat64Array()
var terr_y := PackedFloat64Array()
var terr_r := PackedFloat64Array()
var terr_elev := PackedFloat64Array()
var msa_from := PackedFloat64Array()
var msa_to := PackedFloat64Array()
var msa_alt := PackedFloat64Array()
var fix_names := PackedStringArray()
var fix_x := PackedFloat64Array()
var fix_y := PackedFloat64Array()
var name := ""
var runway_name := ""
var transition_alt := 0


static func from_dict(d: Dictionary) -> Self:
	var w := new()
	var ils: Dictionary = d["ils"]
	var rwy: Dictionary = d["runway"]
	var sep: Dictionary = d["separation"]
	w.name = String(d["name"])
	w.field_elev = float(d["field_elev_ft"])
	w.course_deg = float(ils["course_deg"])
	w.glide_deg = float(ils["glide_deg"])
	w.tch = float(ils["tch_ft"])
	w.range_nm = float(ils["range_nm"])
	w.runway_name = String(rwy["name"])
	w.runway_heading = float(rwy["heading_deg"])
	w.runway_length_nm = float(rwy["length_nm"])
	w.sep_lateral_nm = float(sep["lateral_nm"])
	w.sep_vertical_ft = float(sep["vertical_ft"])
	w.transition_alt = int(d["transition_alt_ft"])
	for t: Dictionary in d["terrain"]:
		w.terr_x.append(float(t["x"]))
		w.terr_y.append(float(t["y"]))
		w.terr_r.append(float(t["radius_nm"]))
		w.terr_elev.append(float(t["elev_ft"]))
	for s: Dictionary in d["msa"]:
		w.msa_from.append(float(s["from_deg"]))
		w.msa_to.append(float(s["to_deg"]))
		w.msa_alt.append(float(s["alt_ft"]))
	for f: Dictionary in d["fixes"]:
		w.fix_names.append(String(f["name"]))
		w.fix_x.append(float(f["x"]))
		w.fix_y.append(float(f["y"]))
	return w


static func default_world() -> Self:
	return from_dict(WorldDef.DATA)


## Index of a named fix, or -1.
func fix_index(fix_name: String) -> int:
	return fix_names.find(fix_name)
