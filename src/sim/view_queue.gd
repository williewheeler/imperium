class_name ViewQueue
extends RefCounted
## One player's view queue: where the step puts what the player may see, and where the player's client takes it from. It holds only
## the *latest* ViewFrame, so a reader that is slow (an AI that looks once a second) skips what it missed instead of falling
## behind, and the host builds no more than is read. A frame that was not read when the next arrives is folded into it
## (see ViewFrame.absorb), so nothing that happened is lost.
##
## How often the step puts a view here is the client's choice: every `every` ticks (a person's screen wants each tick; 0 for
## none), or when it asks (`want`: the step builds one at its end).

var player: int  # -1 for a spectator, who sees everything
var every := 1
var paths := false  # does the client want the routes of its own units too?
var filter: ViewFilter  # what the player may see: the one place the fog is applied
var _frame: ViewFrame
var _asked := false
var _next := 0


## Puts a frame on the queue, in place of one that has not been taken.
func put(frame: ViewFrame) -> void:
	if _frame != null:
		frame.absorb(_frame)
	_frame = frame


## The latest frame, or null if there is nothing new since the last call.
func take() -> ViewFrame:
	var frame := _frame
	_frame = null
	return frame


## Asks for a view to be built at the end of the step that is running (or the next one).
func want() -> void:
	_asked = true


func due(tick: int) -> bool:
	return _asked or (every > 0 and tick >= _next)


func published(tick: int) -> void:
	_asked = false
	_next = tick + every
