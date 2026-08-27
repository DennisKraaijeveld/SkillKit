//! Discover, track, and update Agent Skills (`SKILL.md` folders) on disk.

mod config;
mod frontmatter;
mod lockfile;
mod mcp_integration;
mod model;
mod paths;
mod placement;
mod projects;
mod runtime_tools;
mod scan;
mod source;
mod update;
mod watch;

pub use config::{AppConfig, CURRENT_ONBOARDING_VERSION, config_path};
pub use frontmatter::{ParsedSkillMd, join_skill_md, parse_skill_md, split_frontmatter};
pub use lockfile::{LockIndex, LockScope, SkillLockEntry, SkillLockFile, load_all_locks};
pub use mcp_integration::{
    McpClient, McpClientStatus, McpIntegrationStatus, configure_mcp_client, disconnect_mcp_client,
    install_mcp_server, mcp_integration_status,
};
pub use model::{
    AgentLink, PackageUpdateNotice, ScanResult, Scope, Skill, SkillId, SkillSource, UpdateDiffLine,
    UpdateFileChange, UpdateFileDiff, VersionChange, VersionStatus, apply_checked_versions,
    filter_skills, global_package_banner, global_package_notices, preserve_version_state,
    selection_after_scan, short_ref, version_changes, version_check_errors,
};
pub use paths::{
    AGENT_DIR_NAMES, AgentHarness, HarnessDetectionSummary, HarnessSkillDir, PROJECT_CONTAINERS,
    agent_from_path, detect_agent_harness_summary, detect_agent_harnesses, global_skill_dirs,
    is_project_container, project_container_names, skip_dir_name, well_known_global_skill_dirs,
};
pub use placement::link_skill_to_project;
pub use projects::{ProjectCandidate, discover_projects};
pub use runtime_tools::{
    RuntimeContext, RuntimeOverrides, RuntimeStatus, RuntimeTool, RuntimeToolState,
    RuntimeToolStatus, RuntimeTools, ToolFailure, ToolRequest,
};
pub use scan::{
    create_skill, create_skill_in_folders, read_skill_file, scan, scan_with_home,
    scan_with_home_and_runtime, scan_with_home_including_global_equivalents, scan_with_runtime,
    validate_skill_frontmatter, write_skill_file,
};
pub use source::{
    CheckProgress, attach_sources, attach_sources_with_runtime, check_updates,
    check_updates_with_runtime, detect_git, detect_git_with_runtime, preview_update_file,
};
pub use update::{
    UpdateOutcome, UpdateProgress, install_skill, install_skill_with_runtime, install_source,
    normalize_install_spec, update_all, update_all_with_runtime, update_skill,
    update_skill_with_runtime,
};
pub use watch::{SkillWatchWaiter, SkillWatcher, event_is_relevant, path_is_relevant};
