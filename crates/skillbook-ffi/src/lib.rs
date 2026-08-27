//! UniFFI session for the SwiftUI app. Domain types stay in `skillbook-core`.

uniffi::setup_scaffolding!("skillbook");

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use skillbook_core::{
    AppConfig, CURRENT_ONBOARDING_VERSION, RuntimeOverrides, RuntimeTool, RuntimeToolState,
    RuntimeTools, Scope, Skill, SkillSource, SkillWatcher, VersionStatus, apply_checked_versions,
    check_updates_with_runtime, config_path, configure_mcp_client, create_skill,
    create_skill_in_folders, detect_agent_harness_summary, disconnect_mcp_client,
    discover_projects, global_package_banner, global_package_notices, install_mcp_server,
    install_skill_with_runtime, join_skill_md, link_skill_to_project, mcp_integration_status,
    parse_skill_md, preserve_version_state, preview_update_file as build_update_file_preview,
    read_skill_file, scan_with_home_and_runtime, scan_with_runtime, update_all_with_runtime,
    update_skill_with_runtime, validate_skill_frontmatter, version_changes, version_check_errors,
    well_known_global_skill_dirs, write_skill_file,
};

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SkillbookError {
    #[error("{message}")]
    Message { message: String },
}

impl SkillbookError {
    fn msg(message: impl ToString) -> Self {
        Self::Message {
            message: message.to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiScope {
    Global,
    Project,
    Custom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiVersion {
    Unknown,
    Checking,
    UpToDate,
    UpdateAvailable,
    Untracked,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiRuntimeTool {
    Git,
    Npx,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiRuntimeToolState {
    Available,
    Missing,
    Invalid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiMcpClient {
    Codex,
    ClaudeCode,
    Cursor,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiMcpClientStatus {
    pub client: FfiMcpClient,
    pub detected: bool,
    pub configured: bool,
    pub needs_repair: bool,
    pub conflict: bool,
    pub config_path: String,
    pub issue: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiMcpIntegrationStatus {
    pub bundled_available: bool,
    pub installed: bool,
    pub update_available: bool,
    pub installed_path: String,
    pub clients: Vec<FfiMcpClientStatus>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiRuntimeToolStatus {
    pub tool: FfiRuntimeTool,
    pub state: FfiRuntimeToolState,
    pub path: Option<String>,
    pub version: Option<String>,
    pub issue: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiRuntimeStatus {
    pub git: FfiRuntimeToolStatus,
    pub npx: FfiRuntimeToolStatus,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSkillPlacement {
    pub agent: String,
    pub path: String,
    pub scope: FfiScope,
    pub root: Option<String>,
    pub is_symlink: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSkillRow {
    pub id: String,
    pub name: String,
    pub description: String,
    pub scope: FfiScope,
    pub agents: Vec<String>,
    pub path: String,
    pub npx: bool,
    pub source_label: String,
    pub source_kind: String,
    pub collection_id: String,
    pub collection_label: String,
    pub source_category: Option<String>,
    pub placements: Vec<FfiSkillPlacement>,
    pub duplicate_key: String,
    pub duplicate_reason: String,
    pub version: FfiVersion,
    pub bump_from: Option<String>,
    pub bump_to: Option<String>,
    pub folder: String,
    pub skill_md: String,
    pub github_url: Option<String>,
    pub npx_install: Option<String>,
    pub version_error: Option<String>,
    pub modified_at_unix_seconds: Option<u64>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiUpdateFileChange {
    pub path: String,
    pub kind: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiVersionChange {
    pub skill_id: String,
    pub name: String,
    pub from: Option<String>,
    pub to: Option<String>,
    pub source: String,
    pub requires_npx: bool,
    pub local_modified: bool,
    pub files: Vec<FfiUpdateFileChange>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiUpdateFileDiff {
    pub path: String,
    pub lines: Vec<FfiUpdateDiffLine>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiUpdateDiffLine {
    pub kind: String,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
    pub text: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiUpdateOutcome {
    pub skill_id: String,
    pub name: String,
    pub ok: bool,
    pub message: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiParsedSkill {
    pub yaml: String,
    pub body: String,
    pub name: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiConfig {
    pub onboarding_version: u32,
    pub config_error: Option<String>,
    pub project_roots: Vec<String>,
    pub custom_roots: Vec<String>,
    pub appearance: String,
    pub git_path: Option<String>,
    pub npx_path: Option<String>,
    pub global_dirs: Vec<FfiGlobalDir>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiProjectCandidate {
    pub name: String,
    pub path: String,
    pub work_root: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiHarnessSkillDir {
    pub path: String,
    pub exists: bool,
    pub skill_count: u32,
    pub unique_skill_count: u32,
    pub source_skill_count: u32,
    pub linked_skill_count: u32,
    pub broken_link_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiAgentHarness {
    pub agent: String,
    pub detected: bool,
    pub skill_dirs: Vec<FfiHarnessSkillDir>,
    pub unique_skill_count: u32,
    pub source_skill_count: u32,
    pub linked_skill_count: u32,
    pub placement_count: u32,
    pub broken_link_count: u32,
    pub detected_via_app: bool,
    pub detected_via_config: bool,
    pub detected_via_skill_directory: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiHarnessDetectionSummary {
    pub harnesses: Vec<FfiAgentHarness>,
    pub unique_skill_count: u32,
    pub placement_count: u32,
    pub linked_placement_count: u32,
    pub broken_link_count: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiGlobalDir {
    pub agent: String,
    pub path: String,
    pub exists: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiProgress {
    pub done: u32,
    pub total: u32,
    pub name: String,
    pub phase: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSnapshot {
    pub skills: Vec<FfiSkillRow>,
    pub errors: Vec<String>,
    pub status_hint: String,
    pub npx_banner: Option<String>,
    pub version_changes: Vec<FfiVersionChange>,
    pub scanning: bool,
}

struct Inner {
    home: Option<PathBuf>,
    config: AppConfig,
    config_error: Option<String>,
    config_path: Option<PathBuf>,
    skills: Vec<Skill>,
}

impl Inner {
    fn load() -> Self {
        let (config, config_error) = match AppConfig::load() {
            Ok(config) => (config, None),
            Err(error) => {
                let path = config_path()
                    .map(|path| path.display().to_string())
                    .unwrap_or_else(|_| "SkillKit configuration".into());
                (
                    AppConfig::default(),
                    Some(format!("Unable to read {path}: {error}")),
                )
            }
        };
        Self {
            home: None,
            config,
            config_error,
            config_path: None,
            skills: Vec::new(),
        }
    }

    fn save_config(&self) -> Result<(), SkillbookError> {
        self.save_config_value(&self.config)
    }

    fn save_config_value(&self, config: &AppConfig) -> Result<(), SkillbookError> {
        if let Some(error) = &self.config_error {
            return Err(SkillbookError::msg(format!(
                "{error}. Fix the configuration file and restart SkillKit before saving setup."
            )));
        }
        let result = match self.config_path.as_deref() {
            Some(path) => config.save_to(path),
            None => config.save(),
        };
        result.map_err(SkillbookError::msg)
    }

    fn snapshot(&self, status_hint: String) -> FfiSnapshot {
        snapshot_from(&self.skills, &[], status_hint)
    }
}

#[derive(uniffi::Object)]
pub struct Session {
    inner: Mutex<Inner>,
    runtime: Mutex<RuntimeTools>,
    watcher: Mutex<Option<SkillWatcher>>,
    progress: Mutex<FfiProgress>,
    cancel: AtomicBool,
}

#[uniffi::export]
impl Session {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        let inner = Inner::load();
        let runtime = RuntimeTools::current(runtime_overrides(&inner.config));
        Arc::new(Self {
            inner: Mutex::new(inner),
            runtime: Mutex::new(runtime),
            watcher: Mutex::new(None),
            progress: Mutex::new(idle_progress()),
            cancel: AtomicBool::new(false),
        })
    }

    pub fn snapshot(&self) -> FfiSnapshot {
        let inner = self.lock();
        inner.snapshot(status_hint(&inner.skills))
    }

    pub fn config(&self) -> FfiConfig {
        let inner = self.lock();
        let home = inner
            .home
            .clone()
            .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/"));
        config_view(&inner.config, &home, inner.config_error.clone())
    }

    pub fn projects(&self) -> Vec<FfiProjectCandidate> {
        let (config, inferred_roots) = {
            let inner = self.lock();
            let mut inferred_roots: Vec<PathBuf> = inner
                .skills
                .iter()
                .filter_map(|skill| skill.project_root.clone())
                .collect();
            inferred_roots.extend(inner.skills.iter().flat_map(|skill| {
                skill
                    .agents
                    .iter()
                    .filter(|placement| placement.scope == Scope::Project)
                    .filter_map(|placement| placement.root.clone())
            }));
            (inner.config.clone(), inferred_roots)
        };

        discover_projects(&config, &inferred_roots)
            .into_iter()
            .map(|project| FfiProjectCandidate {
                name: project.name,
                path: project.path.display().to_string(),
                work_root: project.work_root.display().to_string(),
            })
            .collect()
    }

    pub fn detect_harnesses(&self) -> FfiHarnessDetectionSummary {
        let home = self
            .lock()
            .home
            .clone()
            .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/"));
        let summary = detect_agent_harness_summary(&home);
        let harnesses = summary
            .harnesses
            .into_iter()
            .map(|harness| FfiAgentHarness {
                agent: harness.agent,
                detected: harness.detected,
                unique_skill_count: harness.unique_skill_count.try_into().unwrap_or(u32::MAX),
                source_skill_count: harness.source_skill_count.try_into().unwrap_or(u32::MAX),
                linked_skill_count: harness.linked_skill_count.try_into().unwrap_or(u32::MAX),
                placement_count: harness.placement_count.try_into().unwrap_or(u32::MAX),
                broken_link_count: harness.broken_link_count.try_into().unwrap_or(u32::MAX),
                detected_via_app: harness.detected_via_app,
                detected_via_config: harness.detected_via_config,
                detected_via_skill_directory: harness.detected_via_skill_directory,
                skill_dirs: harness
                    .skill_dirs
                    .into_iter()
                    .map(|directory| FfiHarnessSkillDir {
                        path: directory.path.display().to_string(),
                        exists: directory.exists,
                        skill_count: directory.skill_count.try_into().unwrap_or(u32::MAX),
                        unique_skill_count: directory
                            .unique_skill_count
                            .try_into()
                            .unwrap_or(u32::MAX),
                        source_skill_count: directory
                            .source_skill_count
                            .try_into()
                            .unwrap_or(u32::MAX),
                        linked_skill_count: directory
                            .linked_skill_count
                            .try_into()
                            .unwrap_or(u32::MAX),
                        broken_link_count: directory
                            .broken_link_count
                            .try_into()
                            .unwrap_or(u32::MAX),
                    })
                    .collect(),
            })
            .collect();
        FfiHarnessDetectionSummary {
            harnesses,
            unique_skill_count: summary.unique_skill_count.try_into().unwrap_or(u32::MAX),
            placement_count: summary.placement_count.try_into().unwrap_or(u32::MAX),
            linked_placement_count: summary
                .linked_placement_count
                .try_into()
                .unwrap_or(u32::MAX),
            broken_link_count: summary.broken_link_count.try_into().unwrap_or(u32::MAX),
        }
    }

    pub fn runtime_status(&self) -> FfiRuntimeStatus {
        runtime_status_view(self.lock_runtime().status())
    }

    pub fn refresh_runtime(&self) -> FfiRuntimeStatus {
        let config = self.lock().config.clone();
        let mut runtime = self.lock_runtime();
        *runtime = RuntimeTools::current(runtime_overrides(&config));
        runtime_status_view(runtime.status())
    }

    pub fn set_runtime_tool(
        &self,
        tool: FfiRuntimeTool,
        path: Option<String>,
    ) -> Result<FfiRuntimeStatus, SkillbookError> {
        let path = path
            .as_deref()
            .map(str::trim)
            .filter(|path| !path.is_empty())
            .map(PathBuf::from);
        let config = {
            let mut inner = self.lock();
            match tool {
                FfiRuntimeTool::Git => inner.config.git_path = path,
                FfiRuntimeTool::Npx => inner.config.npx_path = path,
            }
            inner.save_config()?;
            inner.config.clone()
        };
        let mut runtime = self.lock_runtime();
        *runtime = RuntimeTools::current(runtime_overrides(&config));
        Ok(runtime_status_view(runtime.status()))
    }

    pub fn mcp_integration_status(&self, bundled_path: String) -> FfiMcpIntegrationStatus {
        let home = self.session_home();
        mcp_status_view(&mcp_integration_status(
            &home,
            path_if_present(&bundled_path),
        ))
    }

    pub fn install_mcp_server(
        &self,
        bundled_path: String,
    ) -> Result<FfiMcpIntegrationStatus, SkillbookError> {
        let home = self.session_home();
        let bundled = required_path(&bundled_path, "Bundled MCP helper")?;
        install_mcp_server(&home, bundled)
            .map(|status| mcp_status_view(&status))
            .map_err(SkillbookError::msg)
    }

    pub fn configure_mcp_client(
        &self,
        client: FfiMcpClient,
        bundled_path: String,
    ) -> Result<FfiMcpIntegrationStatus, SkillbookError> {
        let home = self.session_home();
        let bundled = required_path(&bundled_path, "Bundled MCP helper")?;
        configure_mcp_client(mcp_client(client), &home, bundled)
            .map(|status| mcp_status_view(&status))
            .map_err(SkillbookError::msg)
    }

    pub fn disconnect_mcp_client(
        &self,
        client: FfiMcpClient,
        bundled_path: String,
    ) -> Result<FfiMcpIntegrationStatus, SkillbookError> {
        let home = self.session_home();
        disconnect_mcp_client(mcp_client(client), &home, path_if_present(&bundled_path))
            .map(|status| mcp_status_view(&status))
            .map_err(SkillbookError::msg)
    }

    pub fn scan(&self, silent: bool) -> FfiSnapshot {
        let (config_home, config) = {
            let inner = self.lock();
            (inner.home.clone(), inner.config.clone())
        };
        let runtime = self.lock_runtime();
        let mut result = match &config_home {
            Some(home) => scan_with_home_and_runtime(&config, home, &runtime),
            None => scan_with_runtime(&config, &runtime),
        };
        drop(runtime);
        let watched_dirs = result.watched_dirs;
        self.refresh_watcher(watched_dirs);
        let mut inner = self.lock();
        if silent {
            // Prefer live session versions so a check that finished during the
            // walk is not overwritten by the clone taken at scan start.
            preserve_version_state(&inner.skills, &mut result.skills);
        }
        inner.skills = result.skills;
        let hint = if silent {
            status_hint(&inner.skills)
        } else {
            format!("{} skills", inner.skills.len())
        };
        let mut snap = inner.snapshot(hint);
        snap.errors = result.errors;
        snap
    }

    pub fn check_updates(&self) -> FfiSnapshot {
        self.cancel.store(false, Ordering::SeqCst);
        let mut checked = self.lock().skills.clone();
        let total = checked
            .iter()
            .filter(|s| s.source.needs_remote_check())
            .count() as u32;
        self.set_progress(0, total, "", "check");
        let runtime = self.lock_runtime();
        check_updates_with_runtime(&mut checked, &runtime, |p| {
            self.set_progress(p.done as u32, p.total as u32, &p.name, "check");
            !self.cancel.load(Ordering::SeqCst)
        });
        drop(runtime);
        self.set_progress(0, 0, "", "idle");
        let mut inner = self.lock();
        apply_checked_versions(&checked, &mut inner.skills);
        let mut snap = inner.snapshot(status_hint(&inner.skills));
        snap.errors = version_check_errors(&inner.skills);
        snap
    }

    pub fn read_skill(&self, id: String) -> Result<FfiParsedSkill, SkillbookError> {
        let path = {
            let inner = self.lock();
            inner
                .skills
                .iter()
                .find(|s| s.id == id)
                .map(|s| s.skill_md.clone())
                .ok_or_else(|| SkillbookError::msg("skill not found"))?
        };
        let text = read_skill_file(&path).map_err(SkillbookError::msg)?;
        let parsed = parse_skill_md(&text);
        Ok(FfiParsedSkill {
            yaml: parsed.frontmatter.unwrap_or_default(),
            body: parsed.body,
            name: parsed.name,
            description: parsed.description,
        })
    }

    pub fn preview_update_file(
        &self,
        id: String,
        path: String,
    ) -> Result<FfiUpdateFileDiff, SkillbookError> {
        let skill = self
            .lock()
            .skills
            .iter()
            .find(|skill| skill.id == id)
            .cloned()
            .ok_or_else(|| SkillbookError::msg("skill not found"))?;
        let preview = build_update_file_preview(&skill, &path).map_err(SkillbookError::msg)?;
        Ok(FfiUpdateFileDiff {
            path: preview.path,
            lines: preview
                .lines
                .into_iter()
                .map(|line| FfiUpdateDiffLine {
                    kind: line.kind,
                    old_line: line.old_line,
                    new_line: line.new_line,
                    text: line.text,
                })
                .collect(),
        })
    }

    pub fn save_skill(
        &self,
        id: String,
        yaml: Option<String>,
        body: String,
    ) -> Result<(), SkillbookError> {
        let path = {
            let inner = self.lock();
            inner
                .skills
                .iter()
                .find(|s| s.id == id)
                .map(|s| s.skill_md.clone())
                .ok_or_else(|| SkillbookError::msg("skill not found"))?
        };
        let yaml = yaml
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                SkillbookError::msg("SKILL.md needs YAML frontmatter with name and description")
            })?;
        validate_skill_frontmatter(yaml).map_err(SkillbookError::msg)?;
        let text = join_skill_md(Some(yaml), &body);
        write_skill_file(&path, &text).map_err(SkillbookError::msg)?;
        self.ignore_watcher_for(Duration::from_millis(800));
        Ok(())
    }

    pub fn update_skill(&self, id: String) -> Result<FfiUpdateOutcome, SkillbookError> {
        let skill = {
            let inner = self.lock();
            inner
                .skills
                .iter()
                .find(|s| s.id == id)
                .cloned()
                .ok_or_else(|| SkillbookError::msg("skill not found"))?
        };
        self.ignore_watcher_for(Duration::from_secs(2));
        let out = update_skill_with_runtime(&skill, &self.lock_runtime());
        if out.ok {
            mark_updated(&mut self.lock().skills, std::slice::from_ref(&out.skill_id));
        }
        self.ignore_watcher_for(Duration::from_secs(2));
        Ok(FfiUpdateOutcome {
            skill_id: out.skill_id,
            name: out.name,
            ok: out.ok,
            message: out.message,
        })
    }

    pub fn preview_updates(&self) -> FfiSnapshot {
        self.check_updates()
    }

    pub fn apply_updates(&self, ids: Vec<String>) -> Vec<FfiUpdateOutcome> {
        let requested: HashSet<&str> = ids.iter().map(String::as_str).collect();
        let skills: Vec<Skill> = {
            let inner = self.lock();
            inner
                .skills
                .iter()
                .filter(|skill| requested.contains(skill.id.as_str()))
                .cloned()
                .collect()
        };
        self.ignore_watcher_for(Duration::from_secs(2));
        self.cancel.store(false, Ordering::SeqCst);
        let total = skills.len() as u32;
        self.set_progress(0, total, "", "update");
        let runtime = self.lock_runtime();
        let outcomes = update_all_with_runtime(&skills, &runtime, |p| {
            self.set_progress(p.done as u32, p.total as u32, &p.name, "update");
            !self.cancel.load(Ordering::SeqCst)
        });
        drop(runtime);
        let updated_ids: Vec<String> = outcomes
            .iter()
            .filter(|outcome| outcome.ok)
            .map(|outcome| outcome.skill_id.clone())
            .collect();
        {
            let mut inner = self.lock();
            mark_updated(&mut inner.skills, &updated_ids);
        }
        self.ignore_watcher_for(Duration::from_secs(2));
        let out = outcomes
            .into_iter()
            .map(|out| FfiUpdateOutcome {
                skill_id: out.skill_id,
                name: out.name,
                ok: out.ok,
                message: out.message,
            })
            .collect();
        self.set_progress(0, 0, "", "idle");
        out
    }

    pub fn progress(&self) -> FfiProgress {
        self.progress
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    pub fn cancel_job(&self) {
        self.cancel.store(true, Ordering::SeqCst);
    }

    pub fn install_skill(
        &self,
        spec: String,
        skill: Option<String>,
        global: bool,
    ) -> FfiUpdateOutcome {
        self.cancel.store(false, Ordering::SeqCst);
        self.set_progress(0, 1, "npx skills add", "install");
        let cwd = {
            let inner = self.lock();
            if global {
                None
            } else {
                inner.config.project_roots.first().cloned()
            }
        };
        let out = install_skill_with_runtime(
            spec.trim(),
            skill.as_deref(),
            global,
            cwd.as_deref(),
            &self.lock_runtime(),
        );
        self.ignore_watcher_for(Duration::from_secs(2));
        self.set_progress(0, 0, "", "idle");
        FfiUpdateOutcome {
            skill_id: out.skill_id,
            name: out.name,
            ok: out.ok,
            message: out.message,
        }
    }

    pub fn install_skill_in_project(
        &self,
        spec: String,
        skill: Option<String>,
        project_root: String,
    ) -> FfiUpdateOutcome {
        let project_root = PathBuf::from(project_root.trim());
        self.cancel.store(false, Ordering::SeqCst);
        self.set_progress(0, 1, "npx skills add", "install");
        let out = install_skill_with_runtime(
            spec.trim(),
            skill.as_deref(),
            false,
            Some(project_root.as_path()),
            &self.lock_runtime(),
        );
        if out.ok
            && let Err(error) = self.register_project_root(project_root)
        {
            self.set_progress(0, 0, "", "idle");
            return FfiUpdateOutcome {
                skill_id: out.skill_id,
                name: out.name,
                ok: false,
                message: error.to_string(),
            };
        }
        self.set_progress(0, 0, "", "idle");
        FfiUpdateOutcome {
            skill_id: out.skill_id,
            name: out.name,
            ok: out.ok,
            message: out.message,
        }
    }

    pub fn link_skill(
        &self,
        id: String,
        project_root: String,
        agents: Vec<String>,
    ) -> Result<FfiUpdateOutcome, SkillbookError> {
        let skill = {
            let inner = self.lock();
            inner
                .skills
                .iter()
                .find(|skill| skill.id == id)
                .cloned()
                .ok_or_else(|| SkillbookError::msg("skill not found"))?
        };
        let project_root = PathBuf::from(project_root.trim());
        let out = link_skill_to_project(&skill, &project_root, &agents);
        if out.ok {
            self.register_project_root(project_root)?;
        }
        Ok(FfiUpdateOutcome {
            skill_id: out.skill_id,
            name: out.name,
            ok: out.ok,
            message: out.message,
        })
    }

    pub fn create_skill(
        &self,
        folder: String,
        name: String,
        description: String,
    ) -> Result<FfiSnapshot, SkillbookError> {
        create_skill(PathBuf::from(folder.trim()).as_path(), &name, &description)
            .map_err(SkillbookError::msg)?;
        Ok(self.scan(false))
    }

    pub fn create_skill_in_folders(
        &self,
        folders: Vec<String>,
        name: String,
        description: String,
    ) -> Result<FfiSnapshot, SkillbookError> {
        let folders: Vec<PathBuf> = folders
            .into_iter()
            .filter_map(|folder| {
                let folder = folder.trim();
                (!folder.is_empty()).then(|| PathBuf::from(folder))
            })
            .collect();
        create_skill_in_folders(&folders, &name, &description).map_err(SkillbookError::msg)?;
        Ok(self.scan(false))
    }

    pub fn create_skill_in_project(
        &self,
        project_root: String,
        name: String,
        description: String,
    ) -> Result<FfiSnapshot, SkillbookError> {
        let project_root = PathBuf::from(project_root.trim());
        if !project_root.is_dir() {
            return Err(SkillbookError::msg("Project folder does not exist"));
        }
        create_skill(
            project_root.join(".agents/skills").as_path(),
            &name,
            &description,
        )
        .map_err(SkillbookError::msg)?;
        self.register_project_root(project_root)?;
        Ok(self.scan(false))
    }

    pub fn wait_for_watch_change(&self) -> bool {
        let waiter = self.lock_watcher().as_ref().map(SkillWatcher::waiter);
        waiter.is_some_and(|waiter| waiter.wait_changed())
    }

    pub fn interrupt_watch_wait(&self) {
        if let Some(watcher) = self.lock_watcher().as_ref() {
            watcher.interrupt_waiters();
        }
    }

    pub fn ignore_watch(&self, ms: u32) {
        self.ignore_watcher_for(Duration::from_millis(ms as u64));
    }

    pub fn complete_onboarding(
        &self,
        project_roots: Vec<String>,
        custom_roots: Vec<String>,
    ) -> Result<FfiSnapshot, SkillbookError> {
        let project_roots = validated_roots(project_roots, "Work folder")?;
        let custom_roots = validated_roots(custom_roots, "Additional folder")?;
        if let Some(duplicate) = project_roots
            .iter()
            .find(|root| custom_roots.contains(root))
        {
            return Err(SkillbookError::msg(format!(
                "Choose {} as either a work folder or an additional folder, not both",
                duplicate.display()
            )));
        }

        {
            let mut inner = self.lock();
            let mut candidate = inner.config.clone();
            candidate.project_roots = project_roots;
            candidate.custom_roots = custom_roots;
            candidate.onboarding_version = CURRENT_ONBOARDING_VERSION;
            inner.save_config_value(&candidate)?;
            inner.config = candidate;
        }
        Ok(self.scan(false))
    }

    pub fn add_project_root(&self, path: String) -> Result<FfiSnapshot, SkillbookError> {
        self.register_project_root(PathBuf::from(path.trim()))?;
        Ok(self.scan(false))
    }

    pub fn remove_project_root(&self, path: String) -> Result<FfiSnapshot, SkillbookError> {
        {
            let mut inner = self.lock();
            let root = PathBuf::from(path);
            inner
                .config
                .project_roots
                .retain(|candidate| candidate != &root);
            inner.save_config()?;
        }
        Ok(self.scan(false))
    }

    pub fn add_custom_root(&self, path: String) -> Result<FfiSnapshot, SkillbookError> {
        let pb = PathBuf::from(path.trim());
        if !pb.is_dir() {
            return Err(SkillbookError::msg("Folder does not exist"));
        }
        {
            let mut inner = self.lock();
            if !inner.config.custom_roots.iter().any(|p| p == &pb) {
                inner.config.custom_roots.push(pb);
                inner.save_config()?;
            }
        }
        Ok(self.scan(false))
    }

    pub fn remove_custom_root(&self, path: String) -> Result<FfiSnapshot, SkillbookError> {
        {
            let mut inner = self.lock();
            let pb = PathBuf::from(path);
            inner.config.custom_roots.retain(|p| p != &pb);
            inner.save_config()?;
        }
        Ok(self.scan(false))
    }

    pub fn set_appearance(&self, mode: String) -> Result<FfiConfig, SkillbookError> {
        let mut inner = self.lock();
        inner.config.appearance = match mode.as_str() {
            "light" | "dark" => mode,
            _ => "system".into(),
        };
        inner.save_config()?;
        let home = inner
            .home
            .clone()
            .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/"));
        Ok(config_view(
            &inner.config,
            &home,
            inner.config_error.clone(),
        ))
    }
}

impl Session {
    fn session_home(&self) -> PathBuf {
        self.lock()
            .home
            .clone()
            .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/"))
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_runtime(&self) -> std::sync::MutexGuard<'_, RuntimeTools> {
        self.runtime.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn lock_watcher(&self) -> std::sync::MutexGuard<'_, Option<SkillWatcher>> {
        self.watcher
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn ignore_watcher_for(&self, duration: Duration) {
        if let Some(watcher) = self.lock_watcher().as_ref() {
            watcher.ignore_for(duration);
        }
    }

    fn refresh_watcher(&self, mut dirs: Vec<PathBuf>) {
        dirs.sort();
        dirs.dedup();
        let mut watcher = self.lock_watcher();
        let same = watcher
            .as_ref()
            .is_some_and(|current| current.dirs() == dirs.as_slice());
        if !same {
            *watcher = SkillWatcher::new(&dirs).ok();
        }
    }

    fn set_progress(&self, done: u32, total: u32, name: &str, phase: &str) {
        let mut progress = self.progress.lock().unwrap_or_else(|e| e.into_inner());
        *progress = FfiProgress {
            done,
            total,
            name: name.to_string(),
            phase: phase.to_string(),
        };
    }

    fn register_project_root(&self, path: PathBuf) -> Result<(), SkillbookError> {
        if !path.is_dir() {
            return Err(SkillbookError::msg("Project folder does not exist"));
        }
        let mut inner = self.lock();
        let canonical = std::fs::canonicalize(&path).unwrap_or_else(|_| path.clone());
        let covered = inner.config.project_roots.iter().any(|root| {
            let root = std::fs::canonicalize(root).unwrap_or_else(|_| root.clone());
            canonical.starts_with(root)
        });
        if !covered {
            inner.config.project_roots.push(path);
            inner.config.project_roots.sort();
            inner.config.project_roots.dedup();
            inner.save_config()?;
        }
        drop(inner);
        self.ignore_watcher_for(Duration::from_secs(2));
        Ok(())
    }

    #[cfg(test)]
    fn new_with_home(home: PathBuf, config: AppConfig) -> Arc<Self> {
        let config_path = home.join("config.toml");
        let runtime = RuntimeTools::current(runtime_overrides(&config));
        Arc::new(Self {
            inner: Mutex::new(Inner {
                home: Some(home),
                config,
                config_error: None,
                config_path: Some(config_path),
                skills: Vec::new(),
            }),
            runtime: Mutex::new(runtime),
            watcher: Mutex::new(None),
            progress: Mutex::new(idle_progress()),
            cancel: AtomicBool::new(false),
        })
    }
}

fn idle_progress() -> FfiProgress {
    FfiProgress {
        done: 0,
        total: 0,
        name: String::new(),
        phase: "idle".into(),
    }
}

fn snapshot_from(skills: &[Skill], errors: &[String], status_hint: String) -> FfiSnapshot {
    let notices = global_package_notices(skills);
    FfiSnapshot {
        skills: skills.iter().map(skill_row).collect(),
        errors: errors.to_vec(),
        status_hint,
        npx_banner: global_package_banner(&notices),
        version_changes: version_changes(skills)
            .into_iter()
            .map(|c| FfiVersionChange {
                requires_npx: skills.iter().any(|skill| {
                    skill.id == c.skill_id && matches!(skill.source, SkillSource::SkillsCli { .. })
                }),
                skill_id: c.skill_id,
                name: c.name,
                from: c.from,
                to: c.to,
                source: c.source,
                local_modified: c.local_modified,
                files: c
                    .files
                    .into_iter()
                    .map(|file| FfiUpdateFileChange {
                        path: file.path,
                        kind: file.kind,
                    })
                    .collect(),
            })
            .collect(),
        scanning: false,
    }
}

fn status_hint(skills: &[Skill]) -> String {
    let n = skills
        .iter()
        .filter(|s| s.version == VersionStatus::UpdateAvailable)
        .count();
    let npx_n: usize = global_package_notices(skills)
        .iter()
        .map(|notice| notice.count)
        .sum();
    if npx_n > 0 {
        format!("{npx_n} npx updates")
    } else if n > 0 {
        format!("{n} updates available")
    } else {
        format!("{} skills", skills.len())
    }
}

fn mark_updated(skills: &mut [Skill], ids: &[String]) {
    let updated: HashSet<&str> = ids.iter().map(String::as_str).collect();
    for skill in skills {
        if !updated.contains(skill.id.as_str()) {
            continue;
        }
        skill.version = VersionStatus::UpToDate;
        skill.installed_version = skill
            .latest_version
            .clone()
            .or(skill.installed_version.clone());
        skill.latest_version = skill.installed_version.clone();
        skill.update_files.clear();
        skill.local_modified = false;
        skill.version_error = None;
    }
}

fn skill_row(skill: &Skill) -> FfiSkillRow {
    let bump = skill.version_change();
    FfiSkillRow {
        id: skill.id.clone(),
        name: skill.name.clone(),
        description: skill.description.clone(),
        scope: match skill.scope {
            Scope::Global => FfiScope::Global,
            Scope::Project => FfiScope::Project,
            Scope::Custom => FfiScope::Custom,
        },
        agents: skill.agent_names(),
        path: skill.display_path(),
        npx: skill.source.is_npx_skills(),
        source_label: skill.source.label(),
        source_kind: skill.source.kind_label().into(),
        collection_id: skill.source.collection_id(),
        collection_label: skill.source.collection_label(),
        source_category: skill.source.source_category(),
        placements: skill
            .agents
            .iter()
            .map(|link| FfiSkillPlacement {
                agent: link.agent.clone(),
                path: link.path.display().to_string(),
                scope: match link.scope {
                    Scope::Global => FfiScope::Global,
                    Scope::Project => FfiScope::Project,
                    Scope::Custom => FfiScope::Custom,
                },
                root: link.root.as_ref().map(|root| root.display().to_string()),
                is_symlink: link.is_symlink,
            })
            .collect(),
        duplicate_key: skill.duplicate_key(),
        duplicate_reason: skill.duplicate_reason().into(),
        version: match skill.version {
            VersionStatus::Unknown => FfiVersion::Unknown,
            VersionStatus::Checking => FfiVersion::Checking,
            VersionStatus::UpToDate => FfiVersion::UpToDate,
            VersionStatus::UpdateAvailable => FfiVersion::UpdateAvailable,
            VersionStatus::Untracked => FfiVersion::Untracked,
            VersionStatus::Error => FfiVersion::Error,
        },
        bump_from: bump.as_ref().and_then(|c| c.from.clone()),
        bump_to: bump.as_ref().and_then(|c| c.to.clone()),
        folder: skill.canonical_dir.display().to_string(),
        skill_md: skill.skill_md.display().to_string(),
        github_url: skill.source.github_url(),
        npx_install: skill.source.npx_install_command(&skill.name),
        version_error: skill.version_error.clone(),
        modified_at_unix_seconds: std::fs::metadata(&skill.skill_md)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|duration| duration.as_secs()),
    }
}

fn config_view(
    config: &AppConfig,
    home: &std::path::Path,
    config_error: Option<String>,
) -> FfiConfig {
    FfiConfig {
        onboarding_version: config.onboarding_version,
        config_error,
        project_roots: config
            .project_roots
            .iter()
            .map(|path| path.display().to_string())
            .collect(),
        custom_roots: config
            .custom_roots
            .iter()
            .map(|p| p.display().to_string())
            .collect(),
        appearance: config.appearance_mode().into(),
        git_path: config
            .git_path
            .as_ref()
            .map(|path| path.display().to_string()),
        npx_path: config
            .npx_path
            .as_ref()
            .map(|path| path.display().to_string()),
        global_dirs: well_known_global_skill_dirs(home)
            .into_iter()
            .map(|(agent, path, exists)| FfiGlobalDir {
                agent,
                path: path.display().to_string(),
                exists,
            })
            .collect(),
    }
}

fn validated_roots(paths: Vec<String>, label: &str) -> Result<Vec<PathBuf>, SkillbookError> {
    let mut roots = Vec::new();
    for path in paths {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            continue;
        }
        let root = PathBuf::from(trimmed);
        if !root.is_dir() {
            return Err(SkillbookError::msg(format!(
                "{label} does not exist: {}",
                root.display()
            )));
        }
        roots.push(root);
    }
    roots.sort();
    roots.dedup();
    Ok(roots)
}

fn runtime_overrides(config: &AppConfig) -> RuntimeOverrides {
    RuntimeOverrides {
        git: config.git_path.clone(),
        npx: config.npx_path.clone(),
    }
}

fn runtime_status_view(status: &skillbook_core::RuntimeStatus) -> FfiRuntimeStatus {
    FfiRuntimeStatus {
        git: runtime_tool_status_view(&status.git),
        npx: runtime_tool_status_view(&status.npx),
    }
}

fn runtime_tool_status_view(status: &skillbook_core::RuntimeToolStatus) -> FfiRuntimeToolStatus {
    FfiRuntimeToolStatus {
        tool: match status.tool {
            RuntimeTool::Git => FfiRuntimeTool::Git,
            RuntimeTool::Npx => FfiRuntimeTool::Npx,
        },
        state: match status.state {
            RuntimeToolState::Available => FfiRuntimeToolState::Available,
            RuntimeToolState::Missing => FfiRuntimeToolState::Missing,
            RuntimeToolState::Invalid => FfiRuntimeToolState::Invalid,
        },
        path: status.path.as_ref().map(|path| path.display().to_string()),
        version: status.version.clone(),
        issue: status.issue.clone(),
    }
}

fn mcp_client(client: FfiMcpClient) -> skillbook_core::McpClient {
    match client {
        FfiMcpClient::Codex => skillbook_core::McpClient::Codex,
        FfiMcpClient::ClaudeCode => skillbook_core::McpClient::ClaudeCode,
        FfiMcpClient::Cursor => skillbook_core::McpClient::Cursor,
    }
}

fn mcp_status_view(status: &skillbook_core::McpIntegrationStatus) -> FfiMcpIntegrationStatus {
    FfiMcpIntegrationStatus {
        bundled_available: status.bundled_available,
        installed: status.installed,
        update_available: status.update_available,
        installed_path: status.installed_path.display().to_string(),
        clients: status
            .clients
            .iter()
            .map(|client| FfiMcpClientStatus {
                client: match client.client {
                    skillbook_core::McpClient::Codex => FfiMcpClient::Codex,
                    skillbook_core::McpClient::ClaudeCode => FfiMcpClient::ClaudeCode,
                    skillbook_core::McpClient::Cursor => FfiMcpClient::Cursor,
                },
                detected: client.detected,
                configured: client.configured,
                needs_repair: client.needs_repair,
                conflict: client.conflict,
                config_path: client.config_path.display().to_string(),
                issue: client.issue.clone(),
            })
            .collect(),
    }
}

fn path_if_present(raw: &str) -> Option<&Path> {
    let trimmed = raw.trim();
    (!trimmed.is_empty()).then(|| Path::new(trimmed))
}

fn required_path<'a>(raw: &'a str, label: &str) -> Result<&'a Path, SkillbookError> {
    path_if_present(raw).ok_or_else(|| SkillbookError::msg(format!("{label} is unavailable")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use skillbook_core::{AgentLink, SkillSource};
    use std::fs;
    use std::path::Path;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration as StdDuration;
    use tempfile::tempdir;

    fn write_skill(dir: &Path, name: &str, body: &str) {
        fs::create_dir_all(dir).unwrap();
        fs::write(
            dir.join("SKILL.md"),
            format!("---\nname: {name}\ndescription: {name} does things\n---\n\n{body}"),
        )
        .unwrap();
    }

    #[test]
    fn skill_row_maps_npx_and_bump() {
        let mut skill = Skill {
            id: "/a".into(),
            name: "frontend-design".into(),
            description: "Make UIs".into(),
            skill_md: PathBuf::from("/a/SKILL.md"),
            canonical_dir: PathBuf::from("/a"),
            agents: vec![AgentLink {
                agent: "cursor".into(),
                path: PathBuf::from("/a"),
                scope: Scope::Global,
                root: None,
                is_symlink: false,
            }],
            scope: Scope::Global,
            project_root: None,
            source: SkillSource::SkillsCli {
                source: "vercel-labs/agent-skills".into(),
                source_url: None,
                source_type: "github".into(),
                skill_path: Some("skills/design/frontend-design/SKILL.md".into()),
                folder_hash: None,
                git_ref: None,
                lock_scope: skillbook_core::LockScope::Global,
            },
            version: VersionStatus::UpdateAvailable,
            latest_ref: None,
            installed_version: Some("1.2.3".into()),
            latest_version: Some("1.2.5".into()),
            version_error: None,
            update_files: Vec::new(),
            local_modified: false,
            content_fingerprint: "fixture-a".into(),
        };
        let row = skill_row(&skill);
        assert!(row.npx);
        assert_eq!(row.source_kind, "npx skills");
        assert_eq!(row.collection_id, "skills-cli:vercel-labs/agent-skills");
        assert_eq!(row.collection_label, "vercel-labs/agent-skills");
        assert_eq!(row.source_category.as_deref(), Some("design"));
        assert_eq!(row.placements.len(), 1);
        assert_eq!(row.placements[0].scope, FfiScope::Global);
        assert!(row.duplicate_key.starts_with("skills-cli:"));
        assert_eq!(row.duplicate_reason, "Same skills.sh source");
        assert_eq!(row.bump_from.as_deref(), Some("1.2.3"));
        assert_eq!(row.bump_to.as_deref(), Some("1.2.5"));
        assert_eq!(row.folder, "/a");
        assert_eq!(row.skill_md, "/a/SKILL.md");
        assert_eq!(
            row.github_url.as_deref(),
            Some("https://github.com/vercel-labs/agent-skills")
        );
        assert!(
            row.npx_install
                .as_deref()
                .unwrap_or_default()
                .contains("npx skills add")
        );
        let mut updated = skill.clone();
        mark_updated(std::slice::from_mut(&mut updated), &[skill.id.clone()]);
        assert_eq!(updated.version, VersionStatus::UpToDate);
        assert_eq!(updated.installed_version.as_deref(), Some("1.2.5"));
        skill.version = VersionStatus::Error;
        skill.version_error = Some("GitHub HTTP 403: rate limit or forbidden.".into());
        let failed = skill_row(&skill);
        assert_eq!(failed.version, FfiVersion::Error);
        assert_eq!(
            failed.version_error.as_deref(),
            Some("GitHub HTTP 403: rate limit or forbidden.")
        );
        skill.version = VersionStatus::UpToDate;
        skill.version_error = None;
        assert!(skill_row(&skill).bump_from.is_none());
        assert!(skill_row(&skill).version_error.is_none());
    }

    #[test]
    fn scanned_skill_row_reports_file_modification_time() {
        let home = tempdir().unwrap();
        write_skill(
            &home.path().join(".cursor/skills/dated"),
            "dated",
            "# Dated\n",
        );
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());

        let snapshot = session.scan(false);

        let modified = snapshot.skills[0].modified_at_unix_seconds.unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        assert!(modified <= now);
        assert!(now - modified < 10);
    }

    #[test]
    fn session_scans_temp_home_and_reads_skill() {
        let home = tempdir().unwrap();
        let skill_dir = home.path().join(".cursor/skills/demo");
        write_skill(&skill_dir, "demo", "# Hello\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let snap = session.scan(false);
        assert_eq!(snap.skills.len(), 1);
        assert_eq!(snap.skills[0].name, "demo");
        assert_eq!(snap.skills[0].scope, FfiScope::Global);
        let parsed = session.read_skill(snap.skills[0].id.clone()).unwrap();
        assert!(parsed.body.contains("# Hello"));
        assert!(parsed.yaml.contains("name: demo"));
    }

    #[test]
    fn session_waits_for_a_debounced_watch_event() {
        let home = tempdir().unwrap();
        let skill_dir = home.path().join(".cursor/skills/demo");
        write_skill(&skill_dir, "demo", "# Before\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session.scan(false);
        let waiting = Arc::clone(&session);
        let (sent, received) = mpsc::channel();
        thread::spawn(move || {
            sent.send(waiting.wait_for_watch_change()).unwrap();
        });

        thread::sleep(StdDuration::from_millis(50));
        write_skill(&skill_dir, "demo", "# After\n");

        assert!(received.recv_timeout(StdDuration::from_secs(3)).unwrap());
    }

    #[test]
    fn session_interrupts_a_pending_watch_wait() {
        let home = tempdir().unwrap();
        let skill_dir = home.path().join(".cursor/skills/demo");
        write_skill(&skill_dir, "demo", "# Before\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session.scan(false);
        let waiting = Arc::clone(&session);
        let (sent, received) = mpsc::channel();
        thread::spawn(move || {
            sent.send(waiting.wait_for_watch_change()).unwrap();
        });

        thread::sleep(StdDuration::from_millis(50));
        session.interrupt_watch_wait();

        assert!(!received.recv_timeout(StdDuration::from_secs(1)).unwrap());
    }

    #[test]
    fn session_save_roundtrips_frontmatter() {
        let home = tempdir().unwrap();
        let skill_dir = home.path().join(".claude/skills/notes");
        write_skill(&skill_dir, "notes", "# Old\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let snap = session.scan(false);
        let id = snap.skills[0].id.clone();
        session
            .save_skill(
                id.clone(),
                Some("name: notes\ndescription: saved".into()),
                "# New\n".into(),
            )
            .unwrap();
        let parsed = session.read_skill(id).unwrap();
        assert!(parsed.body.contains("# New"));
        assert!(parsed.yaml.contains("description: saved"));
    }

    #[test]
    fn silent_scan_preserves_version_badges() {
        let home = tempdir().unwrap();
        write_skill(&home.path().join(".cursor/skills/keep"), "keep", "# Keep\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session.scan(false);
        {
            let mut inner = session.lock();
            inner.skills[0].version = VersionStatus::UpdateAvailable;
            inner.skills[0].installed_version = Some("1.0.0".into());
            inner.skills[0].latest_version = Some("1.1.0".into());
        }
        let snap = session.scan(true);
        assert_eq!(snap.skills[0].version, FfiVersion::UpdateAvailable);
        assert_eq!(snap.skills[0].bump_from.as_deref(), Some("1.0.0"));
    }

    #[test]
    fn check_writeback_keeps_skills_added_during_check() {
        let home = tempdir().unwrap();
        write_skill(&home.path().join(".cursor/skills/keep"), "keep", "# Keep\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session.scan(false);
        let checked;
        {
            let mut inner = session.lock();
            inner.skills[0].version = VersionStatus::UpdateAvailable;
            inner.skills[0].latest_version = Some("9.0.0".into());
            checked = inner.skills.clone();
            inner.skills[0].version = VersionStatus::Unknown;
            inner.skills.push(Skill {
                id: "/extra".into(),
                name: "extra".into(),
                description: "added during check".into(),
                skill_md: PathBuf::from("/extra/SKILL.md"),
                canonical_dir: PathBuf::from("/extra"),
                agents: vec![],
                scope: Scope::Custom,
                project_root: None,
                source: SkillSource::Local,
                version: VersionStatus::Unknown,
                latest_ref: None,
                installed_version: None,
                latest_version: None,
                version_error: None,
                update_files: Vec::new(),
                local_modified: false,
                content_fingerprint: "fixture-extra".into(),
            });
        }
        {
            let mut inner = session.lock();
            apply_checked_versions(&checked, &mut inner.skills);
            assert_eq!(inner.skills.len(), 2);
            assert_eq!(inner.skills[0].version, VersionStatus::UpdateAvailable);
            assert_eq!(inner.skills[0].latest_version.as_deref(), Some("9.0.0"));
            assert_eq!(inner.skills[1].name, "extra");
        }
    }

    #[test]
    fn save_skill_requires_name_and_description() {
        let home = tempdir().unwrap();
        write_skill(&home.path().join(".cursor/skills/notes"), "notes", "# Hi\n");
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let id = session.scan(false).skills[0].id.clone();
        let err = session
            .save_skill(id.clone(), Some("name: notes".into()), "# Hi\n".into())
            .unwrap_err();
        assert!(err.to_string().contains("description"));
        let err = session.save_skill(id, None, "# Hi\n".into()).unwrap_err();
        assert!(err.to_string().contains("frontmatter"));
    }

    #[test]
    fn create_skill_appears_in_scan() {
        let home = tempdir().unwrap();
        let parent = home.path().join(".cursor/skills");
        fs::create_dir_all(&parent).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let snap = session
            .create_skill(
                parent.display().to_string(),
                "Hello World".into(),
                "Greets the user".into(),
            )
            .unwrap();
        assert_eq!(snap.skills.len(), 1);
        assert_eq!(snap.skills[0].name, "hello-world");
        assert!(snap.skills[0].folder.ends_with("hello-world"));
    }

    #[cfg(unix)]
    #[test]
    fn create_skill_in_folders_returns_one_skill_with_multiple_placements() {
        let home = tempdir().unwrap();
        let agents = home.path().join(".agents/skills");
        let claude = home.path().join(".claude/skills");
        fs::create_dir_all(&agents).unwrap();
        fs::create_dir_all(&claude).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());

        let snap = session
            .create_skill_in_folders(
                vec![agents.display().to_string(), claude.display().to_string()],
                "Shared Notes".into(),
                "Keeps shared notes".into(),
            )
            .unwrap();

        assert_eq!(snap.skills.len(), 1);
        assert_eq!(snap.skills[0].placements.len(), 2);
        assert!(snap.skills[0].agents.contains(&"agents".to_string()));
        assert!(snap.skills[0].agents.contains(&"claude".to_string()));
    }

    #[test]
    fn create_skill_in_project_registers_and_returns_the_skill() {
        let home = tempdir().unwrap();
        let project = home.path().join("work/product");
        fs::create_dir_all(&project).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());

        let snap = session
            .create_skill_in_project(
                project.display().to_string(),
                "Project Notes".into(),
                "Keeps project notes".into(),
            )
            .unwrap();

        assert_eq!(snap.skills.len(), 1);
        assert!(
            snap.skills[0]
                .folder
                .ends_with(".agents/skills/project-notes")
        );
        assert_eq!(
            session.config().project_roots,
            [project.display().to_string()]
        );
    }

    #[test]
    fn project_catalog_discovers_only_immediate_children_of_a_work_folder() {
        let home = tempdir().unwrap();
        let work = home.path().join("work");
        let project = work.join("product");
        fs::create_dir_all(project.join(".git")).unwrap();
        fs::create_dir_all(project.join(".claude/worktrees/task/.git")).unwrap();
        let mut config = AppConfig::default();
        config.project_roots = vec![work];
        let session = Session::new_with_home(home.path().to_path_buf(), config);

        let projects = session.projects();

        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].name, "product");
        assert_eq!(
            projects[0].path,
            project.canonicalize().unwrap().display().to_string()
        );
    }

    #[test]
    fn config_lists_well_known_global_dirs() {
        let home = tempdir().unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let cfg = session.config();
        assert!(
            cfg.global_dirs
                .iter()
                .any(|d| d.agent == "cursor" && !d.exists)
        );
        assert_eq!(session.progress().phase, "idle");
    }

    #[test]
    fn session_installs_and_configures_the_mcp_helper() {
        let home = tempdir().unwrap();
        let bundled = home
            .path()
            .join("SkillKit.app/Contents/Helpers/skillkit-mcp");
        fs::create_dir_all(bundled.parent().unwrap()).unwrap();
        fs::write(&bundled, b"mcp-helper").unwrap();
        fs::create_dir_all(home.path().join(".codex")).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());

        let before = session.mcp_integration_status(bundled.display().to_string());
        assert!(before.bundled_available);
        assert!(!before.installed);
        assert!(before.clients[0].detected);

        let configured = session
            .configure_mcp_client(FfiMcpClient::Codex, bundled.display().to_string())
            .unwrap();
        assert!(configured.installed);
        assert!(configured.clients[0].configured);

        let disconnected = session
            .disconnect_mcp_client(FfiMcpClient::Codex, bundled.display().to_string())
            .unwrap();
        assert!(!disconnected.clients[0].configured);
    }

    #[test]
    fn onboarding_detects_harnesses_and_persists_selected_roots() {
        let home = tempdir().unwrap();
        let project = home.path().join("work/product");
        let additional = home.path().join("team-skills");
        fs::create_dir_all(&project).unwrap();
        write_skill(
            &home.path().join(".cursor/skills/global-demo"),
            "global-demo",
            "# Global\n",
        );
        write_skill(
            &project.join(".agents/skills/project-demo"),
            "project-demo",
            "# Project\n",
        );
        write_skill(
            &additional.join("additional-demo"),
            "additional-demo",
            "# Additional\n",
        );
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());

        let cursor = session
            .detect_harnesses()
            .harnesses
            .into_iter()
            .find(|harness| harness.agent == "cursor")
            .unwrap();
        assert!(cursor.detected);
        assert!(cursor.detected_via_skill_directory);
        assert_eq!(cursor.unique_skill_count, 1);
        assert_eq!(cursor.skill_dirs[0].skill_count, 1);

        let snapshot = session
            .complete_onboarding(
                vec![project.display().to_string()],
                vec![additional.display().to_string()],
            )
            .unwrap();
        assert_eq!(snapshot.skills.len(), 3);
        let config = session.config();
        assert_eq!(config.onboarding_version, CURRENT_ONBOARDING_VERSION);
        assert_eq!(config.project_roots, [project.display().to_string()]);
        assert_eq!(config.custom_roots, [additional.display().to_string()]);

        let persisted =
            AppConfig::from_toml(&fs::read_to_string(home.path().join("config.toml")).unwrap())
                .unwrap();
        assert!(persisted.onboarding_complete());
        assert_eq!(persisted.project_roots, [project]);
        assert_eq!(persisted.custom_roots, [additional]);
    }

    #[test]
    fn invalid_onboarding_roots_do_not_replace_saved_setup() {
        let home = tempdir().unwrap();
        let project = home.path().join("work/product");
        fs::create_dir_all(&project).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session
            .complete_onboarding(vec![project.display().to_string()], vec![])
            .unwrap();
        let saved = fs::read_to_string(home.path().join("config.toml")).unwrap();

        let error = session
            .complete_onboarding(
                vec![],
                vec![home.path().join("missing").display().to_string()],
            )
            .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("Additional folder does not exist")
        );
        assert_eq!(
            session.config().project_roots,
            [project.display().to_string()]
        );
        assert_eq!(
            fs::read_to_string(home.path().join("config.toml")).unwrap(),
            saved
        );
    }

    #[test]
    fn unreadable_existing_config_blocks_onboarding_replacement() {
        let home = tempdir().unwrap();
        let project = home.path().join("work/product");
        fs::create_dir_all(&project).unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        session.lock().config_error = Some("Unable to read existing config".into());

        let error = session
            .complete_onboarding(vec![project.display().to_string()], vec![])
            .unwrap_err();

        assert!(error.to_string().contains("Fix the configuration file"));
        assert_eq!(session.config().onboarding_version, 0);
        assert!(!home.path().join("config.toml").exists());
    }

    #[test]
    fn linking_registers_project_and_returns_the_symlinked_placement() {
        let home = tempdir().unwrap();
        let project = home.path().join("work/project");
        fs::create_dir_all(&project).unwrap();
        write_skill(
            &home.path().join(".agents/skills/shared"),
            "shared",
            "# Shared\n",
        );
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let id = session.scan(false).skills[0].id.clone();

        let outcome = session
            .link_skill(id, project.display().to_string(), vec!["claude".into()])
            .unwrap();
        let snapshot = session.scan(false);

        assert!(outcome.ok, "{}", outcome.message);
        assert_eq!(
            session.config().project_roots,
            [project.display().to_string()]
        );
        let persisted =
            AppConfig::from_toml(&fs::read_to_string(home.path().join("config.toml")).unwrap())
                .unwrap();
        assert_eq!(persisted.project_roots, [project]);
        assert!(
            snapshot.skills[0]
                .placements
                .iter()
                .any(|placement| placement.scope == FfiScope::Project && placement.is_symlink)
        );
    }

    #[test]
    fn linking_below_a_work_folder_does_not_add_a_redundant_root() {
        let home = tempdir().unwrap();
        let work = home.path().join("work");
        let project = work.join("project");
        fs::create_dir_all(&project).unwrap();
        write_skill(
            &home.path().join(".agents/skills/shared"),
            "shared",
            "# Shared\n",
        );
        let mut config = AppConfig::default();
        config.project_roots = vec![work.clone()];
        let session = Session::new_with_home(home.path().to_path_buf(), config);
        let id = session.scan(false).skills[0].id.clone();

        let outcome = session
            .link_skill(id, project.display().to_string(), vec!["agents".into()])
            .unwrap();

        assert!(outcome.ok, "{}", outcome.message);
        assert_eq!(session.config().project_roots, [work.display().to_string()]);
    }

    #[test]
    fn install_skill_rejects_empty_spec() {
        let home = tempdir().unwrap();
        let session = Session::new_with_home(home.path().to_path_buf(), AppConfig::default());
        let out = session.install_skill("".into(), None, true);
        assert!(!out.ok);
    }
}
