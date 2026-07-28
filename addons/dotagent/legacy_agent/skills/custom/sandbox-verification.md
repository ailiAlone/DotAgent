# triggers: sandbox, verification, regression, cleanup, test_files

# Sandbox & Verification Skill

用于完整工具验证、回归测试、沙箱项目维护。

## 用途
- 验证 DotAgent 所有 58 个工具是否可用
- 在隔离的 test_files/ 目录中做安全测试
- 跑完后用 cleanup_backups 清理过期备份

## 测试流程
1. 只读类（get_* / list_* / read_* / peek_scene / search_in_scripts）→ 不修改任何文件
2. 写类（create_* / add_node / set_node_property）→ 在 test_files/ 子目录
3. 修改类（update_script / replace_in_file / replace_in_scripts）→ 同样在 test_files/
4. 危险类（run_current_scene + stop_running_scene 配对 / delete_file）→ 测试后立即恢复或清理
5. 收尾：export_session 导出对话 → cleanup_backups 清理

## 重要约束
- **绝不调用 reload_project** — 它会清除工具注册表
- run_current_scene 启动后必须配对 stop_running_scene
- 写测试在 test_files/ 下，不污染主项目
- 备份文件 .dotagent_backups/ 保留 10 个最新的（cleanup_backups 规则）
