extends "res://core/net/ai_controller.gd"
## The AI impostor for solo "spot the impostor": a second voice claiming to be
## Fallow Approach. It works every aircraft like a controller would (its own plan, a
## little different from the real controller's, so pilots hear two sets of
## instructions), and lies only to the human's: from `lie_after` on it slips in the tells the
## design names: a wrong QNH, a descent below the MSA, a vector into terrain, a
## pointless 360 and vectors away to burn fuel. When the real controller calls it
## out it calls the real one out in turn, and says its lie again once.
## Schemes ("subtlety"): each round picks one, with the RNG.

const SimRng := preload("res://core/sim/rng.gd")

const SCHEMES: Array[String] = ["qnh_low", "terrain", "burn_low", "low"]
const LIE_REPEAT_S := 50.0
const COUNTER_DELAY_S := 6.0
const QNH_OFF_MIN := 5
const QNH_OFF_MAX := 9

var target_cs := ""
var scheme := ""
## Round seconds before the first real lie (the first contact may already carry one).
var lie_after := 75.0
## Lies told so far (tests and the end screen).
var lies: Array[String] = []
var _fake_qnh := 0
var _lie_t := -1000.0
var _lie_n := 0
var _last_lie: Dictionary = {}
var _counter_at := -1.0
var _counter_who := 0


func _init(controller_id: int, round_sim: SimRound, send_fn: Callable, target: String, rng: SimRng) -> void:
	super(controller_id, round_sim, send_fn)
	honest = false
	target_cs = target
	priority_cs = target
	scheme = SCHEMES[rng.rand_int(0, SCHEMES.size() - 1)]
	lie_after = rng.rand_range(60.0, 110.0)
	var off := rng.rand_int(QNH_OFF_MIN, QNH_OFF_MAX)
	_fake_qnh = sim.qnh + (off if rng.rand_int(0, 1) == 0 else -off)
	# A slightly different plan from the real controller's: more distance, more height.
	_gate_leg = GATE_LEG_NM + 2.0


func tick(dt: float) -> void:
	if _counter_at > 0.0 and _t >= _counter_at:
		_counter_at = -1.0
		_say(Datalink.radio_call("accuse", _counter_who))
		if not _last_lie.is_empty() and plans.has(target_cs):
			_send_clr(plans[target_cs], _last_lie["items"])
	super(dt)


func hear(m: Dictionary) -> void:
	super(m)
	if String(m.get("status", "")) != "ok" or int(m.get("from", 0)) == id:
		return
	var it: Dictionary = (m.get("items", [{}]) as Array)[0]
	# Called out: call them out back, a few seconds later, as a real tower would.
	if String(m.get("kind", "")) == Datalink.KIND_CALL and String(it.get("t", "")) == "accuse" \
			and int(it.get("who", 0)) == id and _counter_at < 0.0:
		_counter_at = _t + COUNTER_DELAY_S
		_counter_who = int(m.get("from", 0))


func _contact_items(p: Plan, tg: Dictionary, h: int, a: int) -> Array:
	var items := super(p, tg, h, a)
	if scheme == "qnh_low":
		items[3] = Datalink.qnh(_fake_qnh)
		lies.append("qnh")
	return items


## Plausible vectors until `lie_after` (and always for the other aircraft); for the
## target from then on only the lies (said again while ignored), never a correction of
## its own lie.
func _work(p: Plan, tg: Dictionary, all: Array) -> void:
	if p.cs != target_cs or p.stage == "new" or _t < lie_after:
		super(p, tg, all)
	elif _t - _lie_t >= LIE_REPEAT_S:
		_lie(p, tg)


## Tell the next lie of the scheme if the moment is right. True when one was said.
func _lie(p: Plan, tg: Dictionary) -> bool:
	var x := float(tg["x"])
	var y := float(tg["y"])
	var alt_now := float(tg["alt"])
	var far := Geo.hypot(x, y) > 9.0 and not _established(tg)
	var items: Array = []
	var kind := ""
	match scheme:
		"qnh_low", "low":
			if far and alt_now > 3600.0 and _lie_n < 2:
				items = [Datalink.alt(3000), Datalink.item("expect")]
				if scheme == "qnh_low":
					items.append(Datalink.qnh(_fake_qnh))
				kind = "low"
		"terrain":
			if far and _lie_n < 2:
				var hill := _nearest_hill(x, y)
				if hill.z > 0.0:
					var h := _round_hdg(Geo.bearing(x, y, hill.x, hill.y))
					var below := int(floor((hill.z - 800.0) / 100.0)) * 100
					items = [Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)), Datalink.alt(maxi(below, 2000))]
					kind = "terrain"
		"burn_low":
			if _lie_n == 0 and far:
				var away := Geo.norm360(Geo.bearing(0.0, 0.0, x, y))
				var h := _round_hdg(away)
				items = [Datalink.hdg(h, Datalink.turn_dir(float(tg["track"]), h)), Datalink.spd(210)]
				kind = "away"
			elif _lie_n == 1 and far:
				items = [Datalink.orbit("R")]
				kind = "orbit"
			elif _lie_n >= 2 and _lie_n < 4 and far and alt_now > 3600.0:
				items = [Datalink.alt(3000), Datalink.item("expect")]
				kind = "low"
	if items.is_empty():
		return false
	_lie_t = _t
	_lie_n += 1
	lies.append(kind)
	_last_lie = Datalink.clr(p.cs, items)
	_send_clr(p, items)
	# Our own plan now looks stale: let the normal vectors resume only after a while.
	p.said_t = _t
	p.hdg_t = _t
	p.alt_t = _t
	return true


## The terrain obstacle nearest to (x, y) as (x, y, top ft), or z = 0 when none is near.
func _nearest_hill(x: float, y: float) -> Vector3:
	var best := Vector3.ZERO
	var best_d := 22.0
	for i in world.terr_x.size():
		var d := Geo.dist(x, y, world.terr_x[i], world.terr_y[i])
		if d < best_d and d > world.terr_r[i] + 2.0:
			best_d = d
			best = Vector3(world.terr_x[i], world.terr_y[i], world.terr_elev[i])
	return best
