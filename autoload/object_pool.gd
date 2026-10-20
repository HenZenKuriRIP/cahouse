extends Node
## Generic node pool. Nodes stay parented; release() deactivates them.
var _free: Dictionary = {}
var active_counts: Dictionary = {}
var created_total: int = 0

func reset() -> void:
	_free.clear()
	active_counts.clear()

func acquire(key: String, factory: Callable) -> Node:
	var arr: Array = _free.get(key, [])
	var n: Node
	while arr.size() > 0 and n == null:
		var c: Node = arr.pop_back()
		if is_instance_valid(c):
			n = c
	if n == null:
		n = factory.call()
		created_total += 1
	active_counts[key] = int(active_counts.get(key, 0)) + 1
	return n

func release(key: String, n: Node) -> void:
	if not _free.has(key):
		_free[key] = []
	_free[key].append(n)
	active_counts[key] = maxi(0, int(active_counts.get(key, 0)) - 1)

func active(key: String) -> int:
	return int(active_counts.get(key, 0))
