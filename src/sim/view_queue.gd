class_name ViewQueue
extends RefCounted
## One player's view queue: where the step puts what the player may see, and where the player's client takes it from. A frame is a set of changes to
## what the client already knows (see ViewFrame), so the client takes every frame that was put on, in order. If it falls too far behind (more than
## MAX_UNREAD frames unread) they are let go, and the next frame is a snapshot of everything it may know, from which it starts again.
##
## How often the step puts a view here is the client's choice: every `every` ticks (a person's screen wants each tick; 0 for
## none), or when it asks (`want`: the step builds one at its end).

const MAX_UNREAD := 600  # twenty seconds of a person's frames

var player: int  # -1 for a spectator, who sees everything
var every := 1
var paths := false  # does the client want the routes of its own units too?
var filter: ViewFilter  # what the player may see: the one place the fog is applied
var _frames: Array[ViewFrame] = []
var _asked := false
var _next := 0


## Puts a frame on the queue. Returns false if the client was too far behind: the unread frames were let go, and this one with them.
func put(frame: ViewFrame) -> bool:
	if _frames.size() >= MAX_UNREAD:
		_frames.clear()
		return false
	_frames.append(frame)
	return true


## Every frame put on since the last call, oldest first.
func take() -> Array[ViewFrame]:
	var out := _frames
	_frames = []
	return out


## Asks for a view to be built at the end of the step that is running (or the next one).
func want() -> void:
	_asked = true


## Is a view to be built now? One asked for is always; one a client takes every so many ticks only if `periodic` (a client
## that draws once a frame needs the view of the last tick of the frame, not of each).
func due(tick: int, periodic := true) -> bool:
	return _asked or (periodic and every > 0 and tick >= _next)


func published(tick: int) -> void:
	_asked = false
	_next = tick + every
