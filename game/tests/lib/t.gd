extends RefCounted
## Minimal assertion helper for the headless test runner.

var failures: Array[String] = []
var completed := false


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual: Variant, expected: Variant, msg: String) -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		failures.append("%s: expected %s (%s), got %s (%s)" % [msg, var_to_str(expected), type_string(typeof(expected)), var_to_str(actual), type_string(typeof(actual))])
	elif actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func near(actual: float, expected: float, tol: float, msg: String) -> void:
	if not (absf(actual - expected) <= tol):
		failures.append("%s: expected %s ± %s, got %s" % [msg, expected, tol, actual])


## vitest toBeCloseTo(expected, digits): |a - e| < 10^-digits / 2.
func close_to(actual: float, expected: float, digits: int, msg: String) -> void:
	var tol := pow(10.0, -digits) / 2.0
	if not (absf(actual - expected) < tol):
		failures.append("%s: expected ≈%f (digits %d), got %f" % [msg, expected, digits, actual])


## Every test ends with this, so a test aborted by a script error is reported as failed.
func done() -> void:
	completed = true


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
