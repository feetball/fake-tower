extends RefCounted
## Water on the windshield: how fast the airflow carries it (CockpitWindshield.flow_speed,
## the distance the shaders integrate) and that the glass accumulates that distance as
## the aircraft speeds up and slows down. The drawing itself is shader code
## (shaders/rain_water.gdshaderinc) and is checked by rendering.

const T := preload("res://tests/lib/t.gd")


func test_flow_speed_is_dynamic_pressure(t) -> void:
	t.eq(CockpitWindshield.flow_speed(0.0), 0.0, "parked: no flow")
	t.eq(CockpitWindshield.flow_speed(20.0), 0.0, "taxi speed: drops hold on")
	var prev := 0.0
	var ias := 40.0
	while ias <= 320.0:
		var v := CockpitWindshield.flow_speed(ias)
		t.check(v > prev, "flow speed rises with airspeed at %d kt" % int(ias))
		prev = v
		ias += 20.0
	var approach := CockpitWindshield.flow_speed(140.0)
	t.check(approach > 0.35 and approach < 0.55, "about 0.45 m/s of glass at approach speed, got %f" % approach)
	# Dynamic pressure: 250 kt is (250/140)^2 = 3.19 times the pressure of 140 kt, less the pinning.
	t.near(CockpitWindshield.flow_speed(250.0) / approach, 3.33, 0.1, "250 kt vs 140 kt")
	t.done()


func test_glass_accumulates_the_distance_the_air_carries_water(t) -> void:
	var ws := CockpitWindshield.new()
	ws._ready()
	t.eq(ws.water_travel, 0.0, "starts dry")
	ws.set_conditions(0.6, 140.0)
	ws.update_view(Basis.IDENTITY, 2.0)
	var two_s := 2.0 * CockpitWindshield.flow_speed(140.0)
	t.near(ws.water_travel, two_s, 1e-6, "2 s at approach speed")
	ws.set_conditions(0.6, 280.0)
	ws.update_view(Basis.IDENTITY, 1.0)
	t.near(ws.water_travel, two_s + CockpitWindshield.flow_speed(280.0), 1e-6, "speeding up carries it faster")
	var before := ws.water_travel
	ws.set_conditions(0.6, 0.0)
	ws.update_view(Basis.IDENTITY, 30.0)
	t.eq(ws.water_travel, before, "parked: the drops stay where they are")
	ws.free()
	t.done()
