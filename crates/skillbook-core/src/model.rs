use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};

/// Stable identity: canonical skill directory.
pub type SkillId = String;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Scope {
    Global,
    Project,
    Custom,
}

impl Scope {
    pub fn label(self) -> &'static str {
        match self {
            Scope::Global => "Global",
            Scope::Project => "Project",
            Scope::Custom => "Custom",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct AgentLink {
    pub agent: String,
    pub path: PathBuf,
    pub scope: Scope,
    pub root: Option<PathBuf>,
    pub is_symlink: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkillSource {
    SkillsCli {
        source: String,
        source_url: Option<String>,
        source_type: String,
        skill_path: Option<String>,
        folder_hash: Option<String>,
        git_ref: Option<String>,
        lock_scope: crate::lockfile::LockScope,
    },
    Git {
        repo_root: PathBuf,
        remote: String,
        branch: Option<String>,
    },
    Local,
}

impl SkillSource {
    pub fn label(&self) -> String {
        match self {
            SkillSource::SkillsCli { source, .. } => source.clone(),
            SkillSource::Git { remote, .. } => remote.clone(),
            SkillSource::Local => "local".into(),
        }
    }

    pub fn can_update(&self) -> bool {
        !matches!(self, SkillSource::Local)
    }

    /// GitHub or git remotes that a version check should actually hit.
    pub fn needs_remote_check(&self) -> bool {
        match self {
            SkillSource::Git { .. } => true,
            SkillSource::SkillsCli {
                source,
                source_type,
                ..
            } => source_type == "github" || source.contains('/'),
            SkillSource::Local => false,
        }
    }

    /// Installed via `npx skills add` (tracked in `.skill-lock.json` / `skills-lock.json`).
    pub fn is_npx_skills(&self) -> bool {
        matches!(self, SkillSource::SkillsCli { .. })
    }

    pub fn kind_label(&self) -> &'static str {
        match self {
            SkillSource::SkillsCli { .. } => "npx skills",
            SkillSource::Git { .. } => "git",
            SkillSource::Local => "local",
        }
    }

    pub fn collection_id(&self) -> String {
        match self {
            SkillSource::SkillsCli { source, .. } => format!("skills-cli:{source}"),
            SkillSource::Git { repo_root, .. } => format!("git:{}", repo_root.display()),
            SkillSource::Local => "local".into(),
        }
    }

    pub fn collection_label(&self) -> String {
        match self {
            SkillSource::SkillsCli { source, .. } => source.clone(),
            SkillSource::Git { remote, .. } => {
                github_repo_label(remote).unwrap_or_else(|| remote.clone())
            }
            SkillSource::Local => "Local skills".into(),
        }
    }

    pub fn source_category(&self) -> Option<String> {
        let SkillSource::SkillsCli {
            skill_path: Some(path),
            ..
        } = self
        else {
            return None;
        };
        let mut parts: Vec<&str> = path
            .split(['/', '\\'])
            .filter(|part| !part.is_empty())
            .collect();
        if parts.last().is_some_and(|part| *part == "SKILL.md") {
            parts.pop();
        }
        parts.pop();
        if parts.first().is_some_and(|part| *part == "skills") {
            parts.remove(0);
        }
        (!parts.is_empty()).then(|| parts.join(" / "))
    }

    /// Pack identity, e.g. `vercel-labs/agent-skills`.
    pub fn package_name(&self) -> Option<&str> {
        match self {
            SkillSource::SkillsCli { source, .. } => Some(source.as_str()),
            _ => None,
        }
    }

    pub fn github_url(&self) -> Option<String> {
        match self {
            SkillSource::SkillsCli {
                source_url, source, ..
            } => {
                if let Some(url) = source_url
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    return Some(url.to_string());
                }
                crate::source::parse_owner_repo(source)
                    .ok()
                    .map(|(owner, repo)| format!("https://github.com/{owner}/{repo}"))
            }
            SkillSource::Git { remote, .. } => {
                let remote = remote.trim();
                if remote.contains("github.com") {
                    let https = remote
                        .replace("git@github.com:", "https://github.com/")
                        .trim_end_matches(".git")
                        .to_string();
                    Some(https)
                } else {
                    None
                }
            }
            SkillSource::Local => None,
        }
    }

    pub fn npx_install_command(&self, skill_name: &str) -> Option<String> {
        let SkillSource::SkillsCli {
            source,
            source_url,
            source_type,
            skill_path,
            git_ref,
            lock_scope,
            ..
        } = self
        else {
            return None;
        };
        let project = matches!(lock_scope, crate::lockfile::LockScope::Project { .. });
        let install = crate::update::install_source(
            source,
            source_url.as_deref(),
            source_type,
            skill_path.as_deref(),
            git_ref.as_deref(),
            project,
        )?;
        let mut cmd = format!("npx skills add {install} --skill {skill_name}");
        if !project {
            cmd.push_str(" -g");
        }
        Some(cmd)
    }
}

fn github_repo_label(remote: &str) -> Option<String> {
    let normalized = remote
        .trim()
        .trim_end_matches(".git")
        .replace("git@github.com:", "https://github.com/");
    normalized
        .strip_prefix("https://github.com/")
        .or_else(|| normalized.strip_prefix("http://github.com/"))
        .map(str::to_string)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VersionStatus {
    Unknown,
    Checking,
    UpToDate,
    UpdateAvailable,
    Untracked,
    Error,
}

impl VersionStatus {
    pub fn label(self) -> &'static str {
        match self {
            VersionStatus::Unknown => "unknown",
            VersionStatus::Checking => "checking",
            VersionStatus::UpToDate => "up to date",
            VersionStatus::UpdateAvailable => "update available",
            VersionStatus::Untracked => "local",
            VersionStatus::Error => "error",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Skill {
    pub id: SkillId,
    pub name: String,
    pub description: String,
    pub skill_md: PathBuf,
    pub canonical_dir: PathBuf,
    pub agents: Vec<AgentLink>,
    pub scope: Scope,
    pub project_root: Option<PathBuf>,
    pub source: SkillSource,
    pub version: VersionStatus,
    pub latest_ref: Option<String>,
    /// Installed version label (`1.2.3`, a git tag, or a short hash).
    pub installed_version: Option<String>,
    /// Upstream version label after a fetch.
    pub latest_version: Option<String>,
    /// Why the last version check failed, when `version` is `Error`.
    pub version_error: Option<String>,
    pub update_files: Vec<UpdateFileChange>,
    pub local_modified: bool,
    pub content_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateFileChange {
    pub path: String,
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VersionChange {
    pub skill_id: SkillId,
    pub name: String,
    pub from: Option<String>,
    pub to: Option<String>,
    pub source: String,
    pub local_modified: bool,
    pub files: Vec<UpdateFileChange>,
}

impl VersionChange {
    pub fn summary(&self) -> String {
        match (&self.from, &self.to) {
            (Some(from), Some(to)) => format!("{from} → {to}"),
            _ => "Unversioned update".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateFileDiff {
    pub path: String,
    pub lines: Vec<UpdateDiffLine>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateDiffLine {
    pub kind: String,
    pub old_line: Option<u32>,
    pub new_line: Option<u32>,
    pub text: String,
}

impl Skill {
    pub fn duplicate_key(&self) -> String {
        let name = duplicate_component(&self.name);
        match &self.source {
            SkillSource::SkillsCli {
                source, skill_path, ..
            } => format!(
                "skills-cli:{}:{}",
                duplicate_component(source),
                skill_path
                    .as_deref()
                    .map(duplicate_component)
                    .unwrap_or(name)
            ),
            SkillSource::Git { remote, .. } => {
                format!("git:{}:{name}", duplicate_component(remote))
            }
            SkillSource::Local => {
                format!("content:{name}:{}", self.content_fingerprint)
            }
        }
    }

    pub fn duplicate_reason(&self) -> &'static str {
        match self.source {
            SkillSource::SkillsCli { .. } => "Same skills.sh source",
            SkillSource::Git { .. } => "Same Git source",
            SkillSource::Local => "Identical skill contents",
        }
    }

    pub fn matches_query(&self, query: &str) -> bool {
        if query.is_empty() {
            return true;
        }
        let q = query.to_lowercase();
        self.name.to_lowercase().contains(&q)
            || self.description.to_lowercase().contains(&q)
            || self
                .agents
                .iter()
                .any(|a| a.agent.to_lowercase().contains(&q))
            || self.source.label().to_lowercase().contains(&q)
            || self.display_path().to_lowercase().contains(&q)
            || self
                .canonical_dir
                .to_string_lossy()
                .to_lowercase()
                .contains(&q)
            || (self.source.is_npx_skills() && (q == "npx" || q == "skills"))
    }

    pub fn agent_names(&self) -> Vec<String> {
        let mut names: Vec<_> = self.agents.iter().map(|a| a.agent.clone()).collect();
        names.sort();
        names.dedup();
        names
    }

    pub fn display_path(&self) -> String {
        shorten_home(&self.canonical_dir)
    }

    pub fn version_change(&self) -> Option<VersionChange> {
        if self.version != VersionStatus::UpdateAvailable {
            return None;
        }
        Some(VersionChange {
            skill_id: self.id.clone(),
            name: self.name.clone(),
            from: release_version(self.installed_version.as_deref()),
            to: release_version(self.latest_version.as_deref()),
            source: self.source.collection_label(),
            local_modified: self.local_modified,
            files: self.update_files.clone(),
        })
    }
}

fn duplicate_component(value: &str) -> String {
    value.trim().trim_end_matches('/').to_ascii_lowercase()
}

fn release_version(value: Option<&str>) -> Option<String> {
    let value = value.map(str::trim).filter(|value| !value.is_empty())?;
    if value.len() >= 7 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    Some(value.to_string())
}

pub fn version_changes(skills: &[Skill]) -> Vec<VersionChange> {
    skills.iter().filter_map(Skill::version_change).collect()
}

/// Global `npx skills -g` packs that have at least one pending update.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageUpdateNotice {
    pub source: String,
    pub count: usize,
    pub names: Vec<String>,
}

pub fn global_package_notices(skills: &[Skill]) -> Vec<PackageUpdateNotice> {
    let mut by_source: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for skill in skills {
        if skill.scope != Scope::Global {
            continue;
        }
        if skill.version != VersionStatus::UpdateAvailable {
            continue;
        }
        let Some(source) = skill.source.package_name() else {
            continue;
        };
        by_source
            .entry(source.to_string())
            .or_default()
            .push(skill.name.clone());
    }
    by_source
        .into_iter()
        .map(|(source, mut names)| {
            names.sort();
            names.dedup();
            PackageUpdateNotice {
                count: names.len(),
                source,
                names,
            }
        })
        .collect()
}

/// Short titlebar/banner copy for global `npx skills` pack updates.
pub fn global_package_banner(notices: &[PackageUpdateNotice]) -> Option<String> {
    if notices.is_empty() {
        return None;
    }
    let n: usize = notices.iter().map(|notice| notice.count).sum();
    let packs: Vec<&str> = notices
        .iter()
        .map(|notice| notice.source.as_str())
        .collect();
    let noun = if n == 1 {
        "global update"
    } else {
        "global updates"
    };
    Some(format!("npx skills · {n} {noun} · {}", packs.join(", ")))
}

/// Keep version-check results across a disk rescan so the sidebar does not jump.
pub fn preserve_version_state(previous: &[Skill], next: &mut [Skill]) {
    let previous_by_id: HashMap<&str, &Skill> = previous
        .iter()
        .map(|skill| (skill.id.as_str(), skill))
        .collect();
    for skill in next {
        let Some(prev) = previous_by_id.get(skill.id.as_str()).copied() else {
            continue;
        };
        if prev.canonical_dir != skill.canonical_dir {
            continue;
        }
        skill.version = prev.version;
        skill.latest_ref = prev.latest_ref.clone();
        if skill.installed_version.is_none() {
            skill.installed_version = prev.installed_version.clone();
        }
        skill.latest_version = prev.latest_version.clone();
        skill.version_error = prev.version_error.clone();
        skill.update_files = prev.update_files.clone();
        skill.local_modified = prev.local_modified;
    }
}

/// One banner line after a version check, if any skills failed.
pub fn version_check_errors(skills: &[Skill]) -> Vec<String> {
    let failed: Vec<&Skill> = skills
        .iter()
        .filter(|skill| skill.version == VersionStatus::Error)
        .collect();
    if failed.is_empty() {
        return Vec::new();
    }
    let first_skill = failed[0];
    let first = first_skill
        .version_error
        .as_deref()
        .unwrap_or("Version check failed");
    let n = failed.len();
    if n == 1 {
        vec![format!("Couldn’t check {}: {first}", first_skill.name)]
    } else {
        vec![format!(
            "{n} skills couldn’t be checked. {}: {first}",
            first_skill.name
        )]
    }
}

/// Copy version-check fields onto the live session list by id.
///
/// A scan that finished during `check_updates` keeps its membership; we must
/// not replace `live` with the clone the check started from.
pub fn apply_checked_versions(checked: &[Skill], live: &mut [Skill]) {
    preserve_version_state(checked, live);
}

/// Short git/GitHub object id, leave semver and tags alone.
pub fn short_ref(value: &str) -> String {
    let value = value.trim();
    if value.len() >= 12 && value.chars().all(|c| c.is_ascii_hexdigit()) {
        value.chars().take(7).collect()
    } else {
        value.to_string()
    }
}

pub fn shorten_home(path: &Path) -> String {
    if let Some(home) = dirs::home_dir()
        && let Ok(rest) = path.strip_prefix(&home)
    {
        return format!("~/{}", rest.display());
    }
    path.display().to_string()
}

#[derive(Debug, Clone, Default)]
pub struct ScanResult {
    pub skills: Vec<Skill>,
    pub errors: Vec<String>,
    pub watched_dirs: Vec<PathBuf>,
}

impl ScanResult {
    pub fn sort_skills(&mut self) {
        self.skills.sort_by(|a, b| {
            scope_ord(a.scope)
                .cmp(&scope_ord(b.scope))
                .then(a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
    }
}

/// Sidebar filter: text query plus the optional "outdated only" switch.
pub fn filter_skills<'a>(skills: &'a [Skill], query: &str, outdated_only: bool) -> Vec<&'a Skill> {
    skills
        .iter()
        .filter(|s| s.matches_query(query))
        .filter(|s| !outdated_only || s.version == VersionStatus::UpdateAvailable)
        .collect()
}

/// Keep the current skill after a rescan when it still exists; otherwise the first row.
pub fn selection_after_scan(keep: Option<&str>, skills: &[Skill]) -> Option<String> {
    if let Some(id) = keep
        && skills.iter().any(|s| s.id == id)
    {
        return Some(id.to_string());
    }
    skills.first().map(|s| s.id.clone())
}

fn scope_ord(scope: Scope) -> u8 {
    match scope {
        Scope::Global => 0,
        Scope::Project => 1,
        Scope::Custom => 2,
    }
}

#[cfg(test)]
pub(crate) fn test_skill(id: &str, name: &str, scope: Scope, version: VersionStatus) -> Skill {
    Skill {
        id: id.into(),
        name: name.into(),
        description: format!("{name} does things"),
        skill_md: PathBuf::from(format!("/{id}/SKILL.md")),
        canonical_dir: PathBuf::from(format!("/{id}")),
        agents: vec![AgentLink {
            agent: "cursor".into(),
            path: PathBuf::from(format!("/{id}")),
            scope,
            root: None,
            is_symlink: false,
        }],
        scope,
        project_root: None,
        source: SkillSource::Local,
        version,
        latest_ref: None,
        installed_version: None,
        latest_version: None,
        version_error: None,
        update_files: Vec::new(),
        local_modified: false,
        content_fingerprint: format!("test-{id}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_matches_name_description_agent_and_source() {
        let mut skill = test_skill(
            "a",
            "frontend-design",
            Scope::Global,
            VersionStatus::UpToDate,
        );
        skill.description = "Make UIs shine".into();
        assert!(skill.matches_query(""));
        assert!(skill.matches_query("FRONT"));
        assert!(skill.matches_query("shine"));
        assert!(skill.matches_query("cursor"));
        assert!(skill.matches_query("local"));
        assert!(skill.matches_query("/a"));
        assert!(!skill.matches_query("python"));
    }

    #[test]
    fn filter_outdated_and_query_compose() {
        let skills = vec![
            test_skill("a", "alpha", Scope::Global, VersionStatus::UpToDate),
            test_skill("b", "beta", Scope::Project, VersionStatus::UpdateAvailable),
            test_skill("c", "gamma", Scope::Custom, VersionStatus::UpdateAvailable),
        ];
        assert_eq!(filter_skills(&skills, "", false).len(), 3);
        assert_eq!(filter_skills(&skills, "ta", false).len(), 1);
        let outdated = filter_skills(&skills, "", true);
        assert_eq!(outdated.len(), 2);
        assert!(
            outdated
                .iter()
                .all(|s| s.version == VersionStatus::UpdateAvailable)
        );
        assert_eq!(filter_skills(&skills, "gamma", true).len(), 1);
        assert!(filter_skills(&skills, "alpha", true).is_empty());
    }

    #[test]
    fn selection_survives_rescan_or_falls_back() {
        let skills = vec![
            test_skill("a", "alpha", Scope::Global, VersionStatus::Unknown),
            test_skill("b", "beta", Scope::Global, VersionStatus::Unknown),
        ];
        assert_eq!(
            selection_after_scan(Some("b"), &skills).as_deref(),
            Some("b")
        );
        assert_eq!(
            selection_after_scan(Some("gone"), &skills).as_deref(),
            Some("a")
        );
        assert_eq!(selection_after_scan(None, &skills).as_deref(), Some("a"));
        assert_eq!(selection_after_scan(Some("a"), &[]), None);
    }

    #[test]
    fn sort_skills_orders_scope_then_name() {
        let mut result = ScanResult {
            skills: vec![
                test_skill("c", "zeta", Scope::Global, VersionStatus::Unknown),
                test_skill("a", "alpha", Scope::Custom, VersionStatus::Unknown),
                test_skill("b", "Beta", Scope::Project, VersionStatus::Unknown),
            ],
            ..ScanResult::default()
        };
        result.sort_skills();
        let names: Vec<_> = result.skills.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["zeta", "Beta", "alpha"]);
    }

    #[test]
    fn local_source_cannot_update_git_can() {
        assert!(!SkillSource::Local.can_update());
        assert!(
            SkillSource::Git {
                repo_root: PathBuf::from("/tmp"),
                remote: "https://github.com/a/b".into(),
                branch: None,
            }
            .can_update()
        );
    }

    #[test]
    fn short_ref_trims_hashes_keeps_semver() {
        assert_eq!(short_ref("1.2.3"), "1.2.3");
        assert_eq!(short_ref("abcdef0123456789"), "abcdef0");
        assert_eq!(short_ref("v2.0.0"), "v2.0.0");
    }

    #[test]
    fn version_change_only_when_update_available() {
        let mut skill = test_skill("a", "alpha", Scope::Global, VersionStatus::UpToDate);
        skill.installed_version = Some("1.2.3".into());
        skill.latest_version = Some("1.2.5".into());
        assert!(skill.version_change().is_none());
        skill.version = VersionStatus::UpdateAvailable;
        let bump = skill.version_change().unwrap();
        assert_eq!(bump.summary(), "1.2.3 → 1.2.5");
    }

    #[test]
    fn version_change_keeps_commit_hashes_out_of_the_display_copy() {
        let mut skill = test_skill("a", "alpha", Scope::Global, VersionStatus::UpdateAvailable);
        skill.installed_version = Some("c56eac3".into());
        skill.latest_version = Some("adf2335".into());
        skill.local_modified = true;
        skill.update_files.push(UpdateFileChange {
            path: "SKILL.md".into(),
            kind: "modified".into(),
        });

        let change = skill.version_change().unwrap();

        assert_eq!(change.summary(), "Unversioned update");
        assert_eq!(change.from, None);
        assert_eq!(change.to, None);
        assert!(change.local_modified);
        assert_eq!(change.files.len(), 1);
    }

    #[test]
    fn github_url_from_skills_cli_and_git() {
        use crate::lockfile::LockScope;
        let mut skill = test_skill("a", "alpha", Scope::Global, VersionStatus::Unknown);
        skill.source = SkillSource::SkillsCli {
            source: "vercel-labs/agent-skills".into(),
            source_url: Some("https://github.com/vercel-labs/agent-skills".into()),
            source_type: "github".into(),
            skill_path: None,
            folder_hash: None,
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        assert_eq!(
            skill.source.github_url().as_deref(),
            Some("https://github.com/vercel-labs/agent-skills")
        );
        assert!(
            skill
                .source
                .npx_install_command("alpha")
                .unwrap()
                .contains("npx skills add")
        );
        skill.source = SkillSource::Git {
            repo_root: PathBuf::from("/tmp"),
            remote: "git@github.com:acme/skills.git".into(),
            branch: None,
        };
        assert_eq!(
            skill.source.github_url().as_deref(),
            Some("https://github.com/acme/skills")
        );
    }

    #[test]
    fn collection_metadata_preserves_pack_and_category() {
        use crate::lockfile::LockScope;
        let source = SkillSource::SkillsCli {
            source: "mattpocock/skills".into(),
            source_url: None,
            source_type: "github".into(),
            skill_path: Some("skills/engineering/code-review/SKILL.md".into()),
            folder_hash: None,
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        assert_eq!(source.collection_id(), "skills-cli:mattpocock/skills");
        assert_eq!(source.collection_label(), "mattpocock/skills");
        assert_eq!(source.source_category().as_deref(), Some("engineering"));

        let git = SkillSource::Git {
            repo_root: PathBuf::from("/repo"),
            remote: "git@github.com:acme/agent-skills.git".into(),
            branch: Some("main".into()),
        };
        assert_eq!(git.collection_label(), "acme/agent-skills");
        assert_eq!(git.source_category(), None);
    }

    #[test]
    fn duplicate_identity_prefers_upstream_source_over_location() {
        use crate::lockfile::LockScope;
        let mut first = test_skill("a", "Review", Scope::Global, VersionStatus::Unknown);
        first.source = SkillSource::SkillsCli {
            source: "Owner/Repo".into(),
            source_url: None,
            source_type: "github".into(),
            skill_path: Some("skills/review/SKILL.md".into()),
            folder_hash: None,
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        let mut second = first.clone();
        second.id = "b".into();
        second.canonical_dir = PathBuf::from("/elsewhere/review");

        assert_eq!(first.duplicate_key(), second.duplicate_key());
        assert_eq!(first.duplicate_reason(), "Same skills.sh source");
    }

    #[test]
    fn local_duplicate_identity_requires_matching_name_and_contents() {
        let mut first = test_skill("a", "Review", Scope::Global, VersionStatus::Unknown);
        first.content_fingerprint = "same-content".into();
        let mut second = test_skill("b", "review", Scope::Project, VersionStatus::Unknown);
        second.content_fingerprint = "same-content".into();
        let mut different = second.clone();
        different.content_fingerprint = "different-content".into();

        assert_eq!(first.duplicate_key(), second.duplicate_key());
        assert_ne!(first.duplicate_key(), different.duplicate_key());
        assert_eq!(first.duplicate_reason(), "Identical skill contents");
    }

    #[test]
    fn preserve_version_state_keeps_check_results() {
        let mut prev = test_skill("a", "alpha", Scope::Global, VersionStatus::UpdateAvailable);
        prev.installed_version = Some("1.0.0".into());
        prev.latest_version = Some("1.1.0".into());
        let mut next = vec![test_skill(
            "a",
            "alpha",
            Scope::Global,
            VersionStatus::Unknown,
        )];
        prev.version_error = Some("GitHub HTTP 403".into());
        preserve_version_state(std::slice::from_ref(&prev), &mut next);
        assert_eq!(next[0].version, VersionStatus::UpdateAvailable);
        assert_eq!(next[0].installed_version.as_deref(), Some("1.0.0"));
        assert_eq!(next[0].latest_version.as_deref(), Some("1.1.0"));
        assert_eq!(next[0].version_error.as_deref(), Some("GitHub HTTP 403"));
    }

    #[test]
    fn version_check_errors_summarizes_duplicate_failures() {
        let mut a = test_skill("a", "alpha", Scope::Global, VersionStatus::Error);
        a.version_error = Some("GitHub HTTP 403: rate limit or forbidden.".into());
        let mut b = test_skill("b", "beta", Scope::Global, VersionStatus::Error);
        b.version_error = Some("GitHub HTTP 403: rate limit or forbidden.".into());
        let ok = test_skill("c", "gamma", Scope::Global, VersionStatus::UpToDate);
        let errors = version_check_errors(&[a, b, ok]);
        assert_eq!(errors.len(), 1);
        assert!(
            errors[0].starts_with("2 skills couldn’t be checked."),
            "{}",
            errors[0]
        );
        assert!(errors[0].contains("403"), "{}", errors[0]);
    }

    #[test]
    fn apply_checked_versions_keeps_skills_added_during_check() {
        let mut checked = test_skill("a", "alpha", Scope::Global, VersionStatus::UpdateAvailable);
        checked.latest_version = Some("2.0.0".into());
        let extra = test_skill("b", "beta", Scope::Global, VersionStatus::Unknown);
        let mut live = vec![
            test_skill("a", "alpha", Scope::Global, VersionStatus::Unknown),
            extra,
        ];
        apply_checked_versions(std::slice::from_ref(&checked), &mut live);
        assert_eq!(live.len(), 2);
        assert_eq!(live[0].version, VersionStatus::UpdateAvailable);
        assert_eq!(live[0].latest_version.as_deref(), Some("2.0.0"));
        assert_eq!(live[1].name, "beta");
        assert_eq!(live[1].version, VersionStatus::Unknown);
    }

    #[test]
    fn npx_skills_query_and_global_package_notices() {
        use crate::lockfile::LockScope;
        let mut skill = test_skill(
            "a",
            "frontend-design",
            Scope::Global,
            VersionStatus::UpdateAvailable,
        );
        skill.source = SkillSource::SkillsCli {
            source: "vercel-labs/agent-skills".into(),
            source_url: Some("https://github.com/vercel-labs/agent-skills".into()),
            source_type: "github".into(),
            skill_path: Some("skills/frontend-design/SKILL.md".into()),
            folder_hash: Some("abc".into()),
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        assert!(skill.source.is_npx_skills());
        assert!(skill.matches_query("npx"));
        assert!(skill.matches_query("skills"));
        let mut other = test_skill("b", "notes", Scope::Global, VersionStatus::UpdateAvailable);
        other.source = SkillSource::Local;
        let notices = global_package_notices(&[skill, other]);
        assert_eq!(notices.len(), 1);
        assert_eq!(notices[0].source, "vercel-labs/agent-skills");
        assert_eq!(notices[0].count, 1);
        assert_eq!(notices[0].names, ["frontend-design"]);
        assert_eq!(
            global_package_banner(&notices).as_deref(),
            Some("npx skills · 1 global update · vercel-labs/agent-skills")
        );
    }

    #[test]
    fn project_npx_skills_are_not_global_package_notices() {
        use crate::lockfile::LockScope;
        let mut skill = test_skill(
            "a",
            "frontend-design",
            Scope::Project,
            VersionStatus::UpdateAvailable,
        );
        skill.source = SkillSource::SkillsCli {
            source: "vercel-labs/agent-skills".into(),
            source_url: Some("https://github.com/vercel-labs/agent-skills".into()),
            source_type: "github".into(),
            skill_path: Some("skills/frontend-design/SKILL.md".into()),
            folder_hash: Some("abc".into()),
            git_ref: None,
            lock_scope: LockScope::Project {
                root: PathBuf::from("/proj"),
            },
        };
        assert!(global_package_notices(&[skill]).is_empty());
    }
}
