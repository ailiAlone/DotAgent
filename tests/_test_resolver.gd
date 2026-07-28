extends SceneTree
func _init():
    var resolver = load("res://addons/dotagent/llm/model_capability_resolver.gd")
    if resolver == null:
        print("FAIL: Cannot load resolver")
        quit(1)
        return
    var r = resolver.new()
    if r == null:
        print("FAIL: Cannot instantiate")
        quit(1)
        return

    # Test 1: Exact match
    var gpt4o = r.resolve("gpt-4o", "OpenAI")
    print("1. gpt-4o: ctx=%d, concurrent=%d, vision=%s, source=%s" % [
        gpt4o.context_window, gpt4o.max_concurrent, str(gpt4o.vision), gpt4o._source])

    # Test 2: Wildcard match (dated variant)
    var gpt4o_dated = r.resolve("gpt-4o-2024-11-20", "OpenAI")
    print("2. gpt-4o-2024-11-20: ctx=%d, concurrent=%d, source=%s, matched=%s" % [
        gpt4o_dated.context_window, gpt4o_dated.max_concurrent,
        gpt4o_dated._source, gpt4o_dated.get("_matched_base", "")])

    # Test 3: Claude
    var claude = r.resolve("claude-sonnet-4-20250514", "Anthropic")
    print("3. claude-sonnet-4: ctx=%d, concurrent=%d, cache=%s" % [
        claude.context_window, claude.max_concurrent,
        str(claude.get("supports_cache_control", false))])

    # Test 4: MiniMax-M3
    var mm = r.resolve("MiniMax-M3", "MiniMax")
    print("4. MiniMax-M3: ctx=%d, concurrent=%d" % [mm.context_window, mm.max_concurrent])

    # Test 5: Unknown model → default
    var unknown = r.resolve("some-random-model", "Custom")
    print("5. unknown: ctx=%d, concurrent=%d, source=%s" % [
        unknown.context_window, unknown.max_concurrent, unknown._source])

    # Test 6: Ollama
    var ollama = r.resolve("llama3:70b", "Ollama")
    print("6. ollama:llama3:70b: ctx=%d, concurrent=%d, source=%s" % [
        ollama.context_window, ollama.max_concurrent, ollama._source])

    # Test 7: Adaptive probe
    r.record_request_result("custom-model", "Custom", 200, 1500.0)
    r.record_request_result("custom-model", "Custom", 200, 1200.0)
    for i in range(8):
        r.record_request_result("custom-model", "Custom", 200, 1000.0)
    var probed = r.resolve("custom-model", "Custom")
    print("7. probed: concurrent=%d, source=%s" % [probed.max_concurrent, probed._source])

    # Test 8: Banyan tier recommendation
    var models := ["gpt-4o", "gpt-4o-mini", "gpt-4.1-nano"]
    var rec = r.recommend_cortex_tier("OpenAI", models)
    print("8. banyan tiers: root=%s, branch=%s, worker=%s" % [rec.root, rec.branch, rec.worker])

    # Test 9: Count all known models
    var all_ids = r.get_all_known_model_ids()
    print("9. total known models: %d" % all_ids.size())

    print("\nAll tests completed.")
    quit(0)
