extends SceneTree
## Generates the application icon procedurally: a dark radar scope with a
## phosphor sweep, a few targets, and a control tower silhouette with its
## beacon glowing in the haze. Opaque square (iOS rejects alpha; Android and
## macOS apply their own masks).
## Usage: godot --headless --path game -s tools/make_icon.gd [-- --out=res://icon.png --size=1024]

const BG_TOP := Color(0.035, 0.045, 0.06)
const BG_BOTTOM := Color(0.008, 0.01, 0.014)
const PHOSPHOR := Color(0.36, 1.0, 0.62)
const BEACON := Color(1.0, 0.42, 0.2)


func _init() -> void:
	var out := "res://icon.png"
	var n := 1024
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--size="):
			n = int(a.trim_prefix("--size="))
	var img := render(n)
	var err := img.save_png(out)
	print("icon: %s (%dx%d) -> %s" % [out, n, n, error_string(err)])
	quit(0 if err == OK else 1)


static func render(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var px := 1.0 / float(n) # one pixel in unit coordinates (anti-aliasing width)
	var centre := Vector2(0.5, 0.46)
	var radius := 0.36
	var sweep := deg_to_rad(-38.0) # sweep line angle (0 = east, counter-clockwise up)
	var blips: Array[Vector3] = [ # (angle deg, range 0..1, brightness)
		Vector3(-24.0, 0.64, 1.0), Vector3(8.0, 0.42, 0.75), Vector3(68.0, 0.76, 0.45),
		Vector3(138.0, 0.5, 0.3), Vector3(228.0, 0.82, 0.2)]
	for y in n:
		for x in n:
			var p := Vector2((float(x) + 0.5) / n, (float(y) + 0.5) / n)
			var c := BG_TOP.lerp(BG_BOTTOM, p.y)
			var d := p - centre
			var r := d.length()
			var ang := atan2(-d.y, d.x)
			# Scope face: slightly lifted disc with a vignette.
			var inside := 1.0 - smoothstep(radius - px, radius + px, r)
			c = c.lerp(Color(0.012, 0.03, 0.026), inside * (0.85 - 0.4 * r / radius))
			# Range rings and bezel.
			for k in [0.33, 0.66]:
				var ring := 1.0 - smoothstep(0.0, px * 1.6, absf(r - radius * k))
				c += PHOSPHOR * ring * 0.12 * inside
			var bezel := 1.0 - smoothstep(px * 1.5, px * 4.0, absf(r - radius))
			c += Color(0.5, 0.62, 0.6) * bezel * 0.35
			# Sweep: bright leading edge, exponential afterglow trailing behind it.
			var behind := fposmod(ang - sweep, TAU) # 0 at the line, grows clockwise behind it
			var trail := exp(-behind * 2.6) * inside
			var dl := absf(wrapf(ang - sweep, -PI, PI)) * r
			var edge := (1.0 - smoothstep(px, px * 3.0, dl)) * inside
			c += PHOSPHOR * (trail * 0.38 + edge * 0.6) * smoothstep(0.0, 0.05, r)
			# Targets: brighter the sooner the sweep passed them.
			for b in blips:
				var bp := centre + Vector2(cos(deg_to_rad(b.x)), -sin(deg_to_rad(b.x))) * radius * b.y
				var age := fposmod(deg_to_rad(b.x) - sweep, TAU)
				var g := exp(-age * 0.9) * b.z
				var bd := p.distance_to(bp)
				c += PHOSPHOR * (exp(-pow(bd / 0.011, 2.0)) * 1.1 + exp(-pow(bd / 0.03, 2.0)) * 0.25) * g
			# Tower silhouette rising from the bottom edge in front of the scope.
			var t := _tower(p)
			c = c.lerp(Color(0.006, 0.007, 0.009), t)
			# Cab windows: faint green console glow.
			var cab := _box(p, Vector2(0.5, 0.735), Vector2(0.065, 0.018), px)
			var mullion := smoothstep(0.1, 0.2, absf(fposmod((p.x - 0.5) / 0.024, 1.0) - 0.5))
			c += Color(0.1, 0.3, 0.24) * cab * mullion * 0.55
			# Beacon on the mast with a soft fog halo.
			var bd2 := p.distance_to(Vector2(0.5, 0.622))
			c += BEACON * (exp(-pow(bd2 / 0.008, 2.0)) * 1.4 + exp(-pow(bd2 / 0.06, 2.0)) * 0.35)
			# Dither against banding in the dark gradients.
			var dither := (fmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)) / 255.0
			img.set_pixel(x, y, Color(_tm(c.r) + dither, _tm(c.g) + dither, _tm(c.b) + dither))
	return img


## Coverage (0..1) of the tower: shaft, flared cab, roof and antenna mast.
static func _tower(p: Vector2) -> float:
	var px := 1.0 / 1024.0
	var shaft_w := lerpf(0.036, 0.05, smoothstep(0.76, 1.0, p.y))
	var cov := _box(p, Vector2(0.5, 0.88), Vector2(shaft_w, 0.13), px)
	cov = maxf(cov, _box(p, Vector2(0.5, 0.74), Vector2(0.078, 0.032), px)) # cab
	cov = maxf(cov, _box(p, Vector2(0.5, 0.7), Vector2(0.088, 0.008), px)) # roof
	cov = maxf(cov, _box(p, Vector2(0.5, 0.775), Vector2(0.06, 0.006), px)) # cab floor
	cov = maxf(cov, _box(p, Vector2(0.5, 0.66), Vector2(0.004, 0.04), px)) # mast
	return cov


static func _box(p: Vector2, c: Vector2, half: Vector2, px: float) -> float:
	var q := (p - c).abs() - half
	var d := maxf(q.x, q.y)
	return 1.0 - smoothstep(-px, px, d)


## Gentle filmic shoulder so the bright sweep and beacon do not clip harshly.
static func _tm(v: float) -> float:
	v = maxf(v, 0.0)
	return clampf(pow(v / (1.0 + v * 0.6), 1.0 / 1.05), 0.0, 1.0)
