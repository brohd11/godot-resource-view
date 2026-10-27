extends SceneTree

const Suite = preload("res://addons/_lib/resource_view/_export_ignore/test/node_tree_test.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var report: Dictionary = await Suite.run_tests()
	for line in report.get("output", []):
		print(line)
	quit(0 if report.get("completed", false) and report.get("result", 1) == 0 else 1)
