extends SceneTree
func _init():
    var modules := [
        "res://addons/dotagent/tools/scene_tools.gd",
        "res://addons/dotagent/tools/node_query_tools.gd",
        "res://addons/dotagent/tools/script_tools.gd",
        "res://addons/dotagent/tools/script_file_tools.gd",
        "res://addons/dotagent/tools/project_tools.gd",
        "res://addons/dotagent/tools/file_tools.gd",
        "res://addons/dotagent/tools/screenshot_tools.gd",
        "res://addons/dotagent/tools/exec_tools.gd",
        "res://addons/dotagent/tools/perception_tools.gd",
        "res://addons/dotagent/tools/configuration_tools.gd",
        "res://addons/dotagent/tools/composite_tools.gd",
    ]
    var total := 0
    for path in modules:
        var res = load(path)
        if res == null:
            print("FAIL: %s" % path)
            continue
        var obj = res.new()
        if obj == null:
            print("FAIL: %s (instantiate)" % path)
            continue
        var defs = obj.get_tool_definitions()
        var count: int = defs.size()
        total += count
        var name: String = path.get_file().get_basename()
        print("  %s: %d tools" % [name, count])
        obj = null
    print("\nTOTAL: %d tools" % total)
    quit(0)
