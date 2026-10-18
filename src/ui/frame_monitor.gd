class_name FrameMonitor
extends CanvasLayer
## Finds out why a game stutters. F3 shows a panel of live numbers; every frame that takes much longer
## than it should (a "stall") is written, with the numbers at that moment, to user://stutter.log (the
## panel shows the path). Run with --stutter to log from the start without the panel.
##
## What the numbers tell apart:
##   frame    wall-clock time between frames: what the player sees. Stutter is spikes in this.
##   script   time the game's own code took (_process and _physics_process): CPU in GDScript.
##   render   CPU time Godot spent preparing and submitting the drawing.
##   gpu      time the graphics card took to draw the frame (if the driver reports it).
##   objects, nodes, orphans, memory: a jump in these just before a stall means allocation or
##            loading (a chunk of scenery being built, say). Godot does not garbage-collect GDScript:
##            things are freed the moment nothing uses them, so a "GC pause" would show up as a spike
##            in script time with memory falling, not rising.
## If frame is high while script, render and gpu are all low, the time is going to the display: v-sync
## or the window system pacing frames (a refresh rate that doesn't divide the frame time evenly looks
## exactly like stutter).

const STALL_MS := 24.0  # a frame this long is logged (a 60 Hz frame is 16.7)
const LOG_PATH := "user://stutter.log"

var _label := Label.new()
var _last_usec := 0
var _recent: Array[float] = []  # frame times over the last few seconds
var _refresh := 0.0
var _logging := false
var log_all := false  # log every frame, not just the stalls (--stutter=all)
var _file: FileAccess
var _prev_objects := 0
var _prev_mem := 0.0
var _stalls := 0
var _last_stall := ""
var _frames := 0
var _vp: RID


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("e8f5d0"))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	add_child(_label)
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_last_usec = Time.get_ticks_usec()


## Starts writing stalls to the log file.
func start_logging() -> void:
	if _logging:
		return
	_logging = true
	Perf.trace = true
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file != null:
		_file.store_line("# frames over %.0f ms. window %s, scale %.1f, renderer %s, %s, v-sync %s" % [STALL_MS, get_window().size, get_window().content_scale_factor, RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), DisplayServer.window_get_vsync_mode()])
		_file.store_line("# time_s frame_ms script_ms physics_ms render_cpu_ms gpu_ms draw_calls nodes objects d_objects mem_mb d_mem_mb | slowest parts of the game code this frame (ms)")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_label.visible = not _label.visible
		if _label.visible:
			start_logging()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frames += 1
	if _frames < 30:  # the first frames are start-up
		return
	_recent.append(frame_ms)
	while _recent.size() > 240:
		_recent.pop_front()
	var script_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var parts := Perf.take_frame() if Perf.trace else {}
	if frame_ms > STALL_MS or log_all:
		_stalls += 1 if frame_ms > STALL_MS else 0
		_last_stall = "%.0f ms: script %.1f render %.1f gpu %.1f objects %+d mem %+.1f MB" % [frame_ms, script_ms, render_cpu, gpu, objects - _prev_objects, mem - _prev_mem]
		_last_stall += "  [" + _top_parts(parts) + "]"
		if _logging and _file != null:
			_file.store_line("%.2f %.1f %.1f %.1f %.1f %.1f %d %d %d %+d %.1f %+.2f | %s" % [Time.get_ticks_msec() / 1000.0, frame_ms, script_ms, physics_ms, render_cpu, gpu,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), objects, objects - _prev_objects, mem, mem - _prev_mem, _top_parts(parts)])
			_file.flush()
	_prev_objects = objects
	_prev_mem = mem
	_refresh -= delta
	if _label.visible and _refresh <= 0.0:
		_refresh = 0.25
		var sorted := _recent.duplicate()
		sorted.sort()
		var avg := 0.0
		for v in sorted:
			avg += v
		avg /= sorted.size()
		var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
		_label.text = "%d fps  frame avg %.1f  99%% %.1f  worst %.1f ms\nscript %.1f  physics %.1f  render cpu %.1f  gpu %.1f ms\nobjects %d  nodes %d  orphans %d  memory %.0f MB  draws %d\nstalls (over %.0f ms) %d%s\nlog: %s" % [
			Engine.get_frames_per_second(), avg, p99, sorted[-1], script_ms, physics_ms, render_cpu, gpu, objects, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), mem, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), STALL_MS, _stalls,
			("\nlast: " + _last_stall) if _last_stall != "" else "", ProjectSettings.globalize_path(LOG_PATH)]


## "name 3.2, name 1.1": the parts of the game code that took longest this frame.
func _top_parts(parts: Dictionary) -> String:
	var names := parts.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return parts[a] > parts[b])
	var out: Array[String] = []
	for k in names.slice(0, 3):
		out.append("%s %.1f" % [String(k).replace(" ", "_"), parts[k] / 1000.0])
	return ", ".join(out)
