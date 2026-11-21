class_name PhaseMachine
extends RefCounted
## A small phase / state machine for round-based games (intro -> prep -> wave
## -> clear -> prep ..., defeat). Phases are StringNames; `allow()` declares
## the legal transitions (none declared = anything goes). Timed phases end on
## their own: enter(phase, seconds) then advance(delta) returns the phase that
## timed out (once). A separate pause flag (with reasons) freezes timers
## without leaving the phase, so the game can pause in any phase.
##
## Per-phase permissions answer "may the player do X now?" for UIs and rules:
## permit(&"prep", [&"build", &"summon"]); can(&"build").

signal phase_changed(from: StringName, to: StringName)
signal paused_changed(paused: bool)

var phase: StringName = &""
## Seconds spent in the current phase (paused time excluded).
var time_in_phase: float = 0.0
## Remaining seconds for a timed phase; < 0 = not timed.
var remaining: float = -1.0
var _allowed: Dictionary = {}
var _permits: Dictionary = {}
var _pause_reasons: Dictionary = {}
var history: Array[StringName] = []


func _init(initial: StringName = &"") -> void:
	phase = initial


func allow(from: StringName, to_list: Array) -> void:
	var list: Array = _allowed.get(from, [])
	for t: Variant in to_list:
		if not list.has(t):
			list.append(t)
	_allowed[from] = list


func can_enter(to: StringName) -> bool:
	if _allowed.is_empty() or phase == &"":
		return true
	return (_allowed.get(phase, []) as Array).has(to)


## Switch phase (seconds > 0: it times out after that long). Returns false
## (and changes nothing) for an undeclared transition.
func enter(to: StringName, seconds: float = -1.0) -> bool:
	if not can_enter(to):
		push_warning("PhaseMachine: %s -> %s is not allowed" % [phase, to])
		return false
	var from: StringName = phase
	phase = to
	time_in_phase = 0.0
	remaining = seconds
	history.append(to)
	if history.size() > 64:
		history.pop_front()
	phase_changed.emit(from, to)
	return true


func is_phase(p: StringName) -> bool:
	return phase == p


## Advance the clock. Returns the phase that just timed out (&"" if none);
## the caller decides where to go next.
func advance(delta: float) -> StringName:
	if is_paused():
		return &""
	time_in_phase += delta
	if remaining > 0.0:
		remaining -= delta
		if remaining <= 0.0:
			remaining = -1.0
			return phase
	return &""


func permit(p: StringName, actions: Array) -> void:
	_permits[p] = actions.duplicate()


func can(action: StringName) -> bool:
	return (_permits.get(phase, []) as Array).has(action)


func set_paused(reason: StringName, on: bool) -> void:
	var was: bool = is_paused()
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	if was != is_paused():
		paused_changed.emit(is_paused())


func clear_pauses() -> void:
	var was: bool = is_paused()
	_pause_reasons.clear()
	if was:
		paused_changed.emit(false)


func is_paused() -> bool:
	return not _pause_reasons.is_empty()


func is_paused_by(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


func pause_reasons() -> Array:
	return _pause_reasons.keys()


## Serializable state (phase and timers; pauses are situational and not saved).
func to_save() -> Dictionary:
	return {"phase": str(phase), "time_in_phase": time_in_phase, "remaining": remaining}


func load_save(d: Dictionary) -> void:
	phase = StringName(str(d.get("phase", "")))
	time_in_phase = float(d.get("time_in_phase", 0.0))
	remaining = float(d.get("remaining", -1.0))
