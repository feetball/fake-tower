extends RefCounted
## Controller phraseology card (from src/client/text.ts), filled in with the
## selected callsign and the current ATIS letter and QNH.


static func groups(cs: String, qnh: String, letter: String) -> Array[Dictionary]:
	var info := _phonetic(letter)
	return [
		{"title": "First contact", "lines": [
			"%s, Fallow Approach, radar contact, information %s is current, QNH %s." % [cs, info, qnh],
			"%s, descend and maintain 6000, QNH %s, expect ILS approach runway 27." % [cs, qnh],
		]},
		{"title": "Vectors", "lines": [
			"%s, turn left heading 180, descend and maintain 4000, QNH %s." % [cs, qnh],
			"%s, fly heading 300, vectors ILS runway 27." % cs,
			"%s, reduce speed 180 knots." % cs,
		]},
		{"title": "Approach clearance", "lines": [
			"%s, turn left heading 300, maintain 3000 until established, cleared ILS approach runway 27." % cs,
			"%s, cleared ILS approach runway 27." % cs,
			"%s, runway 27, cleared to land." % cs,
		]},
		{"title": "Holding", "lines": [
			"%s, hold at HOLDR as published, maintain 6000, expect further clearance in 10 minutes." % cs,
		]},
		{"title": "Safety", "lines": [
			"%s, go around, climb straight ahead to 3000." % cs,
			"%s, low altitude alert, check your altitude immediately, QNH %s." % [cs, qnh],
			"%s, traffic alert, turn right immediately heading 360, climb and maintain 6000." % cs,
		]},
		{"title": "Pilot calls", "lines": [
			"%s, minimum fuel." % cs,
			"MAYDAY MAYDAY MAYDAY, %s, fuel, 3 minutes remaining." % cs,
			"Unable, %s — that is below the MSA." % cs,
		]},
	]


static func _phonetic(letter: String) -> String:
	const NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett",
		"Kilo", "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
		"Victor", "Whiskey", "X-ray", "Yankee", "Zulu"]
	var i := letter.to_upper().unicode_at(0) - 65 if letter != "" else -1
	return NAMES[i] if i >= 0 and i < NAMES.size() else letter
