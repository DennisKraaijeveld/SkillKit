use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use sha1::{Digest, Sha1};
use similar::{ChangeTag, TextDiff};

use crate::lockfile::LockIndex;
use crate::model::{
    Skill, SkillSource, UpdateDiffLine, UpdateFileChange, UpdateFileDiff, VersionStatus, short_ref,
};
use crate::runtime_tools::{RuntimeOverrides, RuntimeTool, RuntimeTools, ToolFailure, ToolRequest};

const GIT_REMOTE_CHECK_TIMEOUT: Duration = Duration::from_secs(20);

pub struct CheckProgress {
    pub done: usize,
    pub total: usize,
    pub name: String,
}

pub fn attach_sources(skills: &mut [Skill], locks: &LockIndex) {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    attach_sources_with_runtime(skills, locks, &tools);
}

pub fn attach_sources_with_runtime(skills: &mut [Skill], locks: &LockIndex, tools: &RuntimeTools) {
    for skill in skills.iter_mut() {
        if let Some((lock_scope, entry)) =
            locks.lookup_scoped(&skill.name, skill.scope, skill.project_root.as_deref())
        {
            skill.source = entry.to_source(lock_scope.clone());
            skill.version = VersionStatus::Unknown;
            continue;
        }
        if let Some(git) = detect_git_with_runtime(&skill.canonical_dir, tools) {
            skill.source = git;
            skill.version = VersionStatus::Unknown;
        } else {
            skill.source = SkillSource::Local;
            skill.version = VersionStatus::Untracked;
        }
    }
}

pub fn detect_git(path: &Path) -> Option<SkillSource> {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    detect_git_with_runtime(path, &tools)
}

pub fn detect_git_with_runtime(path: &Path, tools: &RuntimeTools) -> Option<SkillSource> {
    let repo = find_git_root(path)?;
    let remote = git_stdout(&repo, &["remote", "get-url", "origin"], tools)?;
    let branch = git_stdout(&repo, &["rev-parse", "--abbrev-ref", "HEAD"], tools);
    Some(SkillSource::Git {
        repo_root: repo,
        remote,
        branch,
    })
}

pub fn find_git_root(mut path: &Path) -> Option<PathBuf> {
    loop {
        if path.join(".git").exists() {
            return Some(path.to_path_buf());
        }
        path = path.parent()?;
    }
}

pub fn check_updates(skills: &mut [Skill], mut on_progress: impl FnMut(CheckProgress) -> bool) {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    check_updates_with_runtime(skills, &tools, &mut on_progress);
}

pub fn check_updates_with_runtime(
    skills: &mut [Skill],
    tools: &RuntimeTools,
    mut on_progress: impl FnMut(CheckProgress) -> bool,
) {
    check_updates_with_agent_and_base(
        skills,
        github_agent(),
        "https://api.github.com",
        tools,
        &mut on_progress,
    );
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct GithubRepoKey {
    owner: String,
    repo: String,
    ref_name: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
struct GithubCommit {
    sha: String,
}

#[derive(Debug, serde::Deserialize)]
struct GithubTree {
    sha: String,
    #[serde(default)]
    truncated: bool,
    tree: Vec<GithubTreeEntry>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct GithubTreeEntry {
    path: String,
    #[serde(rename = "type")]
    kind: String,
    sha: String,
}

fn check_updates_with_agent_and_base(
    skills: &mut [Skill],
    agent: &ureq::Agent,
    api_base: &str,
    tools: &RuntimeTools,
    mut on_progress: impl FnMut(CheckProgress) -> bool,
) {
    let mut github_groups: BTreeMap<GithubRepoKey, Vec<usize>> = BTreeMap::new();
    let mut git_groups: BTreeMap<PathBuf, Vec<usize>> = BTreeMap::new();

    for (index, skill) in skills.iter_mut().enumerate() {
        skill.version_error = None;
        skill.update_files.clear();
        skill.local_modified = false;
        match &skill.source {
            SkillSource::SkillsCli {
                source,
                git_ref,
                source_type,
                ..
            } if source_type == "github" || source.contains('/') => {
                match parse_owner_repo(source) {
                    Ok((owner, repo)) => {
                        github_groups
                            .entry(GithubRepoKey {
                                owner,
                                repo,
                                ref_name: git_ref.clone(),
                            })
                            .or_default()
                            .push(index);
                    }
                    Err(error) => set_check_error(skill, error.to_string()),
                }
            }
            SkillSource::Git { repo_root, .. } => {
                git_groups.entry(repo_root.clone()).or_default().push(index);
            }
            SkillSource::SkillsCli { .. } | SkillSource::Local => {
                skill.version = VersionStatus::Untracked;
            }
        }
    }

    let total = github_groups.len() + git_groups.len();
    let mut done = 0;
    let mut github_fatal: Option<String> = None;

    for (repo, indices) in github_groups {
        if let Some(message) = github_fatal.clone() {
            for index in indices {
                set_check_error(&mut skills[index], message.clone());
            }
            continue;
        }
        if !on_progress(CheckProgress {
            done,
            total,
            name: format!("{}/{}", repo.owner, repo.repo),
        }) {
            reset_unchecked(skills);
            return;
        }
        done += 1;
        for index in &indices {
            skills[*index].version = VersionStatus::Checking;
        }
        match github_repo_tree(agent, api_base, &repo) {
            Ok((tree, commit_sha)) => {
                for index in indices {
                    let upstream_version =
                        semantic_upstream_version(agent, &repo, &commit_sha, &skills[index]);
                    apply_github_tree(&mut skills[index], &tree, upstream_version, &commit_sha);
                }
            }
            Err(error) => {
                let message = format_check_error(&error);
                for index in indices {
                    set_check_error(&mut skills[index], message.clone());
                }
                if is_fatal_github_error(&message) {
                    github_fatal = Some(message);
                }
            }
        }
    }

    for (repo_root, indices) in git_groups {
        let name = repo_root
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| repo_root.display().to_string());
        let active_done = done;
        if !on_progress(CheckProgress {
            done,
            total,
            name: name.clone(),
        }) {
            reset_unchecked(skills);
            return;
        }
        done += 1;
        for index in &indices {
            skills[*index].version = VersionStatus::Checking;
        }
        let state = check_git_repo(&repo_root, tools, || {
            on_progress(CheckProgress {
                done: active_done,
                total,
                name: name.clone(),
            })
        });
        match state {
            Ok(state) => {
                for index in indices {
                    let skill = &mut skills[index];
                    if skill.installed_version.is_none() {
                        skill.installed_version = state.installed_version.clone();
                    }
                    skill.latest_version = Some(state.latest_version.clone());
                    skill.latest_ref = Some(state.latest_ref.clone());
                    skill.version = state.version;
                }
            }
            Err(GitCheckError::Cancelled) => {
                reset_unchecked(skills);
                return;
            }
            Err(GitCheckError::Failed(message)) => {
                for index in indices {
                    set_check_error(&mut skills[index], message.clone());
                }
            }
        }
    }
}

fn github_repo_tree(
    agent: &ureq::Agent,
    api_base: &str,
    repo: &GithubRepoKey,
) -> anyhow::Result<(GithubTree, String)> {
    let api_base = api_base.trim_end_matches('/');
    let commit_sha = match repo.ref_name.as_deref() {
        Some(ref_name) => {
            let encoded_ref = percent_encode_path_segment(ref_name);
            let url = format!(
                "{api_base}/repos/{}/{}/commits/{encoded_ref}",
                repo.owner, repo.repo
            );
            let mut response = github_get_with_agent(agent, &url, "application/vnd.github+json")?;
            response.body_mut().read_json::<GithubCommit>()?.sha
        }
        None => {
            let url = format!(
                "{api_base}/repos/{}/{}/commits?per_page=1",
                repo.owner, repo.repo
            );
            let mut response = github_get_with_agent(agent, &url, "application/vnd.github+json")?;
            response
                .body_mut()
                .read_json::<Vec<GithubCommit>>()?
                .into_iter()
                .next()
                .ok_or_else(|| anyhow::anyhow!("GitHub repository has no commits"))?
                .sha
        }
    };
    let encoded_ref = percent_encode_path_segment(&commit_sha);
    let url = format!(
        "{api_base}/repos/{}/{}/git/trees/{encoded_ref}?recursive=1",
        repo.owner, repo.repo
    );
    let mut response = github_get_with_agent(agent, &url, "application/vnd.github+json")?;
    let tree = response.body_mut().read_json::<GithubTree>()?;
    if tree.truncated {
        anyhow::bail!(
            "GitHub tree for {}/{} is too large to check safely",
            repo.owner,
            repo.repo
        );
    }
    Ok((tree, commit_sha))
}

fn semantic_upstream_version(
    agent: &ureq::Agent,
    repo: &GithubRepoKey,
    resolved_ref: &str,
    skill: &Skill,
) -> Option<String> {
    let installed = skill.installed_version.as_deref()?;
    if installed.len() >= 7 && installed.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let SkillSource::SkillsCli { skill_path, .. } = &skill.source else {
        return None;
    };
    let path = skill_path.as_deref().filter(|path| !path.is_empty())?;
    let path = if path.ends_with("SKILL.md") {
        path.to_string()
    } else {
        format!("{}/SKILL.md", path.trim_end_matches('/'))
    };
    let encoded_path = path
        .split('/')
        .map(percent_encode_path_segment)
        .collect::<Vec<_>>()
        .join("/");
    let url = format!(
        "https://raw.githubusercontent.com/{}/{}/{}/{encoded_path}",
        repo.owner,
        repo.repo,
        percent_encode_path_segment(resolved_ref)
    );
    let mut response = github_get_with_agent(agent, &url, "text/plain").ok()?;
    let text = response.body_mut().read_to_string().ok()?;
    crate::frontmatter::parse_skill_md(&text).version
}

fn apply_github_tree(
    skill: &mut Skill,
    tree: &GithubTree,
    upstream_version: Option<String>,
    commit_sha: &str,
) {
    let SkillSource::SkillsCli {
        skill_path,
        folder_hash,
        ..
    } = &skill.source
    else {
        return;
    };
    let skill_path = skill_path.clone();
    let folder_hash = folder_hash.clone();
    let folder = skill_folder_path(skill_path.as_deref());
    let latest = if folder.is_empty() {
        Some(tree.sha.as_str())
    } else {
        tree.tree
            .iter()
            .find(|entry| entry.kind == "tree" && entry.path == folder)
            .map(|entry| entry.sha.as_str())
    };
    let Some(latest) = latest else {
        set_check_error(
            skill,
            "GitHub repository no longer contains this skill".into(),
        );
        return;
    };
    let latest = latest.to_string();
    skill.latest_ref = Some(commit_sha.to_string());
    skill.version = if folder_hash.as_deref() == Some(latest.as_str()) {
        skill.latest_version = skill.installed_version.clone();
        VersionStatus::UpToDate
    } else if folder_hash.is_none() {
        VersionStatus::Unknown
    } else {
        skill.latest_version = upstream_version;
        skill.update_files = update_file_changes(&skill.canonical_dir, &folder, tree);
        skill.local_modified = folder_hash.as_deref().is_some_and(|installed| {
            git_tree_hash(&skill.canonical_dir)
                .map(|local| local != installed)
                .unwrap_or(true)
        });
        VersionStatus::UpdateAvailable
    };
}

fn update_file_changes(skill_dir: &Path, folder: &str, tree: &GithubTree) -> Vec<UpdateFileChange> {
    let local = local_blob_hashes(skill_dir).unwrap_or_default();
    let prefix = if folder.is_empty() {
        String::new()
    } else {
        format!("{folder}/")
    };
    let upstream: BTreeMap<String, String> = tree
        .tree
        .iter()
        .filter(|entry| entry.kind == "blob")
        .filter_map(|entry| {
            entry
                .path
                .strip_prefix(&prefix)
                .filter(|path| !path.is_empty() && !path.contains("/../"))
                .map(|path| (path.to_string(), entry.sha.clone()))
        })
        .collect();

    let mut changes = Vec::new();
    for (path, sha) in &upstream {
        match local.get(path) {
            None => changes.push(UpdateFileChange {
                path: path.clone(),
                kind: "added".into(),
            }),
            Some(local_sha) if local_sha != sha => changes.push(UpdateFileChange {
                path: path.clone(),
                kind: "modified".into(),
            }),
            Some(_) => {}
        }
    }
    for path in local.keys() {
        if !upstream.contains_key(path) {
            changes.push(UpdateFileChange {
                path: path.clone(),
                kind: "removed".into(),
            });
        }
    }
    changes.sort_by(|left, right| left.path.cmp(&right.path));
    changes
}

pub fn preview_update_file(skill: &Skill, path: &str) -> anyhow::Result<UpdateFileDiff> {
    preview_update_file_with_agent_and_base(
        skill,
        path,
        github_agent(),
        "https://raw.githubusercontent.com",
    )
}

fn preview_update_file_with_agent_and_base(
    skill: &Skill,
    path: &str,
    agent: &ureq::Agent,
    raw_base: &str,
) -> anyhow::Result<UpdateFileDiff> {
    let relative = Path::new(path);
    if relative.is_absolute()
        || relative
            .components()
            .any(|component| !matches!(component, std::path::Component::Normal(_)))
    {
        anyhow::bail!("invalid update path");
    }
    let change = skill
        .update_files
        .iter()
        .find(|change| change.path == path)
        .ok_or_else(|| anyhow::anyhow!("file is not part of this update"))?;

    let local = read_text_preview(&skill.canonical_dir.join(relative))?.unwrap_or_default();
    let upstream = if change.kind == "removed" {
        String::new()
    } else {
        let SkillSource::SkillsCli {
            source, skill_path, ..
        } = &skill.source
        else {
            anyhow::bail!("line preview is available for GitHub-installed skills");
        };
        let commit = skill
            .latest_ref
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("check for updates again to load this diff"))?;
        let (owner, repo) = parse_owner_repo(source)?;
        let folder = skill_folder_path(skill_path.as_deref());
        let remote_path = if folder.is_empty() {
            path.to_string()
        } else {
            format!("{folder}/{path}")
        };
        let encoded_path = remote_path
            .split('/')
            .map(percent_encode_path_segment)
            .collect::<Vec<_>>()
            .join("/");
        let url = format!(
            "{}/{owner}/{repo}/{}/{encoded_path}",
            raw_base.trim_end_matches('/'),
            percent_encode_path_segment(commit)
        );
        let mut response = github_get_with_agent(agent, &url, "text/plain")?;
        let text = response
            .body_mut()
            .with_config()
            .limit(1_048_576)
            .read_to_string()?;
        validate_text_preview(text.as_bytes())?;
        text
    };

    Ok(build_update_file_diff(path, &local, &upstream))
}

fn read_text_preview(path: &Path) -> anyhow::Result<Option<String>> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    validate_text_preview(&bytes)?;
    Ok(Some(String::from_utf8(bytes)?))
}

fn validate_text_preview(bytes: &[u8]) -> anyhow::Result<()> {
    const MAX_PREVIEW_BYTES: usize = 1_048_576;
    if bytes.len() > MAX_PREVIEW_BYTES {
        anyhow::bail!("file is too large to preview");
    }
    if bytes.contains(&0) {
        anyhow::bail!("binary files cannot be previewed");
    }
    Ok(())
}

fn build_update_file_diff(path: &str, old: &str, new: &str) -> UpdateFileDiff {
    let diff = TextDiff::from_lines(old, new);
    let mut lines = Vec::new();
    for group in diff.grouped_ops(3) {
        lines.push(UpdateDiffLine {
            kind: "hunk".into(),
            old_line: None,
            new_line: None,
            text: similar::udiff::UnifiedHunkHeader::new(&group).to_string(),
        });
        for operation in &group {
            lines.extend(diff.iter_changes(operation).map(|change| {
                UpdateDiffLine {
                    kind: match change.tag() {
                        ChangeTag::Equal => "context",
                        ChangeTag::Delete => "removed",
                        ChangeTag::Insert => "added",
                    }
                    .into(),
                    old_line: change.old_index().map(|index| index as u32 + 1),
                    new_line: change.new_index().map(|index| index as u32 + 1),
                    text: change.value().trim_end_matches(['\r', '\n']).to_string(),
                }
            }));
        }
    }
    UpdateFileDiff {
        path: path.to_string(),
        lines,
    }
}

fn local_blob_hashes(root: &Path) -> anyhow::Result<BTreeMap<String, String>> {
    let mut hashes = BTreeMap::new();
    collect_blob_hashes(root, root, &mut hashes)?;
    Ok(hashes)
}

fn collect_blob_hashes(
    root: &Path,
    directory: &Path,
    hashes: &mut BTreeMap<String, String>,
) -> anyhow::Result<()> {
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        if entry.file_name() == ".git" {
            continue;
        }
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_dir() {
            collect_blob_hashes(root, &path, hashes)?;
            continue;
        }
        let bytes = if metadata.file_type().is_symlink() {
            fs::read_link(&path)?
                .to_string_lossy()
                .into_owned()
                .into_bytes()
        } else if metadata.file_type().is_file() {
            fs::read(&path)?
        } else {
            continue;
        };
        let relative = path
            .strip_prefix(root)?
            .to_string_lossy()
            .replace('\\', "/");
        hashes.insert(relative, git_object_hash("blob", &bytes));
    }
    Ok(())
}

fn git_tree_hash(directory: &Path) -> anyhow::Result<String> {
    Ok(hex_string(&git_tree_hash_bytes(directory)?))
}

fn git_tree_hash_bytes(directory: &Path) -> anyhow::Result<[u8; 20]> {
    let mut entries = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let name = entry.file_name();
        if name == ".git" {
            continue;
        }
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        let (mode, oid, directory_entry) = if metadata.file_type().is_dir() {
            ("40000", git_tree_hash_bytes(&path)?, true)
        } else if metadata.file_type().is_symlink() {
            let bytes = fs::read_link(&path)?
                .to_string_lossy()
                .into_owned()
                .into_bytes();
            ("120000", git_object_hash_bytes("blob", &bytes), false)
        } else if metadata.file_type().is_file() {
            let bytes = fs::read(&path)?;
            (
                file_mode(&metadata),
                git_object_hash_bytes("blob", &bytes),
                false,
            )
        } else {
            continue;
        };
        let mut sort_key = name.as_encoded_bytes().to_vec();
        if directory_entry {
            sort_key.push(b'/');
        }
        entries.push((sort_key, mode, name.as_encoded_bytes().to_vec(), oid));
    }
    entries.sort_by(|left, right| left.0.cmp(&right.0));

    let mut body = Vec::new();
    for (_, mode, name, oid) in entries {
        body.extend_from_slice(mode.as_bytes());
        body.push(b' ');
        body.extend_from_slice(&name);
        body.push(0);
        body.extend_from_slice(&oid);
    }
    Ok(git_object_hash_bytes("tree", &body))
}

#[cfg(unix)]
fn file_mode(metadata: &fs::Metadata) -> &'static str {
    use std::os::unix::fs::PermissionsExt;
    if metadata.permissions().mode() & 0o111 != 0 {
        "100755"
    } else {
        "100644"
    }
}

#[cfg(not(unix))]
fn file_mode(_: &fs::Metadata) -> &'static str {
    "100644"
}

fn git_object_hash(kind: &str, body: &[u8]) -> String {
    hex_string(&git_object_hash_bytes(kind, body))
}

fn git_object_hash_bytes(kind: &str, body: &[u8]) -> [u8; 20] {
    let mut hasher = Sha1::new();
    hasher.update(format!("{kind} {}\0", body.len()).as_bytes());
    hasher.update(body);
    hasher.finalize().into()
}

fn hex_string(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn skill_folder_path(skill_path: Option<&str>) -> String {
    skill_path
        .map(|path| {
            if path.ends_with("SKILL.md") {
                Path::new(path)
                    .parent()
                    .map(|parent| parent.to_string_lossy().into_owned())
                    .unwrap_or_default()
            } else {
                path.trim_end_matches('/').to_string()
            }
        })
        .unwrap_or_default()
}

fn percent_encode_path_segment(value: &str) -> String {
    value
        .bytes()
        .flat_map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                vec![byte as char]
            }
            _ => format!("%{byte:02X}").chars().collect(),
        })
        .collect()
}

fn set_check_error(skill: &mut Skill, message: String) {
    skill.version = VersionStatus::Error;
    skill.version_error = Some(message);
}

fn reset_unchecked(skills: &mut [Skill]) {
    for skill in skills {
        if skill.version == VersionStatus::Checking {
            skill.version = VersionStatus::Unknown;
            skill.version_error = None;
        }
    }
}

pub(crate) fn format_check_error(err: &anyhow::Error) -> String {
    if let Some(http) = err.downcast_ref::<GithubHttpError>() {
        return github_http_error_message(http);
    }
    if let Some(code) = ureq_status_code(err) {
        return github_http_status_message(code);
    }
    err.to_string()
}

#[derive(Debug)]
struct GithubHttpError {
    status: u16,
    remaining: Option<u32>,
    reset_at: Option<u64>,
    retry_after: Option<u64>,
}

impl std::fmt::Display for GithubHttpError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "GitHub HTTP {}", self.status)
    }
}

impl std::error::Error for GithubHttpError {}

fn github_http_error_message(error: &GithubHttpError) -> String {
    if matches!(error.status, 403 | 429) && error.remaining == Some(0) {
        let retry = error.retry_after.or_else(|| {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
            error.reset_at.map(|reset| reset.saturating_sub(now))
        });
        let retry = retry
            .map(|seconds| format!(" Retry in about {} min.", seconds.div_ceil(60).max(1)))
            .unwrap_or_default();
        return format!(
            "GitHub HTTP {}: rate limit reached (0 requests remaining).{retry}",
            error.status
        );
    }
    github_http_status_message(error.status)
}

fn ureq_status_code(err: &anyhow::Error) -> Option<u16> {
    for cause in err.chain() {
        if let Some(ureq::Error::StatusCode(code)) = cause.downcast_ref::<ureq::Error>() {
            return Some(*code);
        }
    }
    None
}

fn github_http_status_message(code: u16) -> String {
    match code {
        401 => "GitHub HTTP 401: anonymous access was rejected.".into(),
        403 => "GitHub HTTP 403: rate limit or access forbidden.".into(),
        404 => "GitHub HTTP 404: repository or skill path not found.".into(),
        429 => "GitHub HTTP 429: rate limit. Wait and retry.".into(),
        n => format!("GitHub HTTP {n}."),
    }
}

fn is_fatal_github_error(msg: &str) -> bool {
    msg.contains("HTTP 401") || msg.contains("HTTP 403") || msg.contains("HTTP 429")
}

pub fn parse_owner_repo(source: &str) -> anyhow::Result<(String, String)> {
    let s = source
        .trim()
        .trim_end_matches(".git")
        .replace("git@github.com:", "https://github.com/");
    let s = s.trim_start_matches("https://github.com/");
    let s = s.trim_start_matches("http://github.com/");
    let mut parts = s.split('/');
    let owner = parts
        .next()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow::anyhow!("bad source {source}"))?;
    let repo = parts
        .next()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow::anyhow!("bad source {source}"))?;
    Ok((owner.to_string(), repo.to_string()))
}

fn github_agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .https_only(true)
            .http_status_as_error(false)
            .max_redirects(5)
            .timeout_global(Some(Duration::from_secs(20)))
            .build()
            .into()
    })
}

fn github_get_with_agent(
    agent: &ureq::Agent,
    url: &str,
    accept: &str,
) -> anyhow::Result<ureq::http::Response<ureq::Body>> {
    let mut retried = false;
    loop {
        let request = agent
            .get(url)
            .header("User-Agent", "skillkit")
            .header("Accept", accept);
        let response = match request.call() {
            Err(error) if !retried && retryable_github_error(&error) => {
                retried = true;
                continue;
            }
            Err(error) => return Err(error.into()),
            Ok(response) => response,
        };
        if response.status().is_success() {
            return Ok(response);
        }
        let header = |name: &str| -> Option<u64> {
            response
                .headers()
                .get(name)
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.parse().ok())
        };
        return Err(GithubHttpError {
            status: response.status().as_u16(),
            remaining: header("x-ratelimit-remaining").and_then(|value| value.try_into().ok()),
            reset_at: header("x-ratelimit-reset"),
            retry_after: header("retry-after"),
        }
        .into());
    }
}

fn retryable_github_error(error: &ureq::Error) -> bool {
    matches!(
        error,
        ureq::Error::Io(_)
            | ureq::Error::Timeout(_)
            | ureq::Error::HostNotFound
            | ureq::Error::ConnectionFailed
    )
}

struct GitRepoVersion {
    installed_version: Option<String>,
    latest_version: String,
    latest_ref: String,
    version: VersionStatus,
}

enum GitCheckError {
    Cancelled,
    Failed(String),
}

fn check_git_repo(
    repo: &Path,
    tools: &RuntimeTools,
    should_continue: impl FnMut() -> bool,
) -> Result<GitRepoVersion, GitCheckError> {
    let (remote, branch_ref) = git_tracking_branch(repo, tools)
        .ok_or_else(|| GitCheckError::Failed("Git repository has no upstream branch.".into()))?;
    let latest_ref = git_remote_tip(repo, &remote, &branch_ref, tools, should_continue)?;
    let head = git_stdout(repo, &["rev-parse", "HEAD"], tools)
        .ok_or_else(|| GitCheckError::Failed("Git could not read the current revision.".into()))?;
    let remote_is_local = git_revision_exists(repo, &latest_ref, tools);
    let version = if latest_ref == head
        || (remote_is_local && git_is_ancestor(repo, &latest_ref, "HEAD", tools))
    {
        VersionStatus::UpToDate
    } else {
        VersionStatus::UpdateAvailable
    };
    let latest_version = if remote_is_local {
        git_describe(repo, &latest_ref, tools).unwrap_or_else(|| short_ref(&latest_ref))
    } else {
        short_ref(&latest_ref)
    };
    Ok(GitRepoVersion {
        installed_version: git_describe(repo, "HEAD", tools),
        latest_version,
        latest_ref,
        version,
    })
}

fn git_tracking_branch(repo: &Path, tools: &RuntimeTools) -> Option<(String, String)> {
    let upstream = git_stdout(
        repo,
        &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
        tools,
    )
    .or_else(|| {
        git_stdout(
            repo,
            &[
                "symbolic-ref",
                "--quiet",
                "--short",
                "refs/remotes/origin/HEAD",
            ],
            tools,
        )
    })?;
    let (remote, branch) = upstream.split_once('/')?;
    if remote.is_empty() || branch.is_empty() {
        return None;
    }
    Some((remote.to_string(), format!("refs/heads/{branch}")))
}

fn git_remote_tip(
    repo: &Path,
    remote: &str,
    branch_ref: &str,
    tools: &RuntimeTools,
    should_continue: impl FnMut() -> bool,
) -> Result<String, GitCheckError> {
    let mut request = git_request(repo, &["ls-remote", "--exit-code", remote, branch_ref]);
    for (key, value) in [
        ("GIT_TERMINAL_PROMPT", "0"),
        ("GCM_INTERACTIVE", "Never"),
        ("SSH_ASKPASS_REQUIRE", "never"),
    ] {
        request
            .env
            .insert(OsString::from(key), OsString::from(value));
    }
    let output = tools
        .execute_interruptible(
            RuntimeTool::Git,
            request,
            GIT_REMOTE_CHECK_TIMEOUT,
            should_continue,
        )
        .map_err(|error| match error {
            ToolFailure::Cancelled(_) => GitCheckError::Cancelled,
            other => GitCheckError::Failed(other.to_string()),
        })?;
    if !output.status.success() {
        return Err(GitCheckError::Failed(
            "Git could not read the remote branch.".into(),
        ));
    }
    output
        .stdout
        .split(|byte| byte.is_ascii_whitespace())
        .find(|part| is_git_oid(part))
        .map(|part| String::from_utf8_lossy(part).into_owned())
        .ok_or_else(|| GitCheckError::Failed("Git returned an invalid remote revision.".into()))
}

fn is_git_oid(value: &[u8]) -> bool {
    matches!(value.len(), 40 | 64) && value.iter().all(u8::is_ascii_hexdigit)
}

fn git_revision_exists(repo: &Path, revision: &str, tools: &RuntimeTools) -> bool {
    let revision = format!("{revision}^{{commit}}");
    tools
        .execute(
            RuntimeTool::Git,
            git_request(repo, &["cat-file", "-e", &revision]),
        )
        .is_ok_and(|output| output.status.success())
}

fn git_is_ancestor(repo: &Path, ancestor: &str, descendant: &str, tools: &RuntimeTools) -> bool {
    tools
        .execute(
            RuntimeTool::Git,
            git_request(repo, &["merge-base", "--is-ancestor", ancestor, descendant]),
        )
        .is_ok_and(|output| output.status.success())
}

fn git_describe(repo: &Path, spec: &str, tools: &RuntimeTools) -> Option<String> {
    git_stdout(
        repo,
        &["describe", "--tags", "--always", "--abbrev=7", spec],
        tools,
    )
    .or_else(|| git_stdout(repo, &["rev-parse", "--short=7", spec], tools))
    .map(|s| short_ref(&s))
}

fn git_stdout(repo: &Path, args: &[&str], tools: &RuntimeTools) -> Option<String> {
    let output = tools
        .execute(RuntimeTool::Git, git_request(repo, args))
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn git_request(repo: &Path, args: &[&str]) -> ToolRequest {
    ToolRequest {
        args: args.iter().map(OsString::from).collect(),
        cwd: Some(repo.to_path_buf()),
        ..ToolRequest::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::os::unix::fs::PermissionsExt;
    use std::thread;
    use std::time::{Duration, Instant};

    fn test_agent() -> ureq::Agent {
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .max_redirects(2)
            .timeout_global(Some(Duration::from_secs(2)))
            .build()
            .into()
    }

    fn read_request(stream: &mut TcpStream) -> String {
        let mut request = Vec::new();
        let mut buffer = [0; 1024];
        while !request.windows(4).any(|window| window == b"\r\n\r\n") {
            let count = stream.read(&mut buffer).unwrap();
            if count == 0 {
                break;
            }
            request.extend_from_slice(&buffer[..count]);
        }
        String::from_utf8(request).unwrap()
    }

    fn server_url(listener: &TcpListener) -> String {
        format!("http://{}/resource", listener.local_addr().unwrap())
    }

    fn github_cli_skill(id: &str, name: &str) -> crate::model::Skill {
        use crate::lockfile::LockScope;
        let mut skill = crate::model::test_skill(
            id,
            name,
            crate::model::Scope::Global,
            VersionStatus::Unknown,
        );
        skill.source = SkillSource::SkillsCli {
            source: "owner/repo".into(),
            source_url: Some("https://github.com/owner/repo".into()),
            source_type: "github".into(),
            skill_path: None,
            folder_hash: Some("abc".into()),
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        skill
    }

    #[test]
    fn check_updates_batches_github_skills_by_repository() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let mut skills: Vec<_> = (0..61)
            .map(|index| {
                let name = format!("skill-{index}");
                let mut skill = github_cli_skill(&format!("id-{index}"), &name);
                let SkillSource::SkillsCli {
                    skill_path,
                    folder_hash,
                    ..
                } = &mut skill.source
                else {
                    unreachable!()
                };
                *skill_path = Some(format!("skills/{name}/SKILL.md"));
                *folder_hash = Some(format!("tree-{index}"));
                skill
            })
            .collect();
        let tree = serde_json::json!({
            "sha": "root",
            "truncated": false,
            "tree": (0..61).flat_map(|index| {
                let name = format!("skill-{index}");
                [
                    serde_json::json!({
                        "path": format!("skills/{name}"),
                        "mode": "040000",
                        "type": "tree",
                        "sha": format!("tree-{index}")
                    }),
                    serde_json::json!({
                        "path": format!("skills/{name}/SKILL.md"),
                        "mode": "100644",
                        "type": "blob",
                        "sha": format!("blob-{index}")
                    }),
                ]
            }).collect::<Vec<_>>()
        });
        let server = thread::spawn(move || {
            let responses = [serde_json::json!([{ "sha": "commit-sha" }]), tree];
            let mut requests = Vec::new();
            for body in responses {
                let (mut stream, _) = listener.accept().unwrap();
                requests.push(read_request(&mut stream));
                let body = serde_json::to_vec(&body).unwrap();
                write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                )
                .unwrap();
                stream.write_all(&body).unwrap();
            }
            requests
        });

        let tools = RuntimeTools::current(RuntimeOverrides::default());
        check_updates_with_agent_and_base(&mut skills, &test_agent(), &base, &tools, |_| true);

        let requests = server.join().unwrap();
        assert_eq!(requests.len(), 2);
        assert!(requests[0].contains("GET /repos/owner/repo/commits?per_page=1 "));
        assert!(requests[1].contains("GET /repos/owner/repo/git/trees/commit-sha?recursive=1 "));
        assert!(
            skills
                .iter()
                .all(|skill| skill.version == VersionStatus::UpToDate)
        );
    }

    #[test]
    fn git_tree_hash_matches_git_object_format() {
        let directory = tempfile::tempdir().unwrap();
        assert_eq!(
            git_tree_hash(directory.path()).unwrap(),
            "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        );
    }

    #[test]
    fn update_preview_lists_files_and_detects_local_changes() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(directory.path().join("SKILL.md"), "old\n").unwrap();
        let installed = git_tree_hash(directory.path()).unwrap();
        let mut skill = github_cli_skill("id", "demo");
        skill.canonical_dir = directory.path().to_path_buf();
        skill.source = SkillSource::SkillsCli {
            source: "owner/repo".into(),
            source_url: None,
            source_type: "github".into(),
            skill_path: Some("skills/demo/SKILL.md".into()),
            folder_hash: Some(installed),
            git_ref: None,
            lock_scope: crate::lockfile::LockScope::Global,
        };
        let tree = GithubTree {
            sha: "root".into(),
            truncated: false,
            tree: vec![
                GithubTreeEntry {
                    path: "skills/demo".into(),
                    kind: "tree".into(),
                    sha: "new-tree".into(),
                },
                GithubTreeEntry {
                    path: "skills/demo/SKILL.md".into(),
                    kind: "blob".into(),
                    sha: git_object_hash("blob", b"new\n"),
                },
                GithubTreeEntry {
                    path: "skills/demo/reference.md".into(),
                    kind: "blob".into(),
                    sha: git_object_hash("blob", b"reference\n"),
                },
            ],
        };

        apply_github_tree(&mut skill, &tree, None, "commit-sha");

        assert_eq!(skill.version, VersionStatus::UpdateAvailable);
        assert!(!skill.local_modified);
        assert_eq!(
            skill.update_files,
            vec![
                UpdateFileChange {
                    path: "SKILL.md".into(),
                    kind: "modified".into(),
                },
                UpdateFileChange {
                    path: "reference.md".into(),
                    kind: "added".into(),
                },
            ]
        );

        fs::write(directory.path().join("SKILL.md"), "locally edited\n").unwrap();
        apply_github_tree(&mut skill, &tree, None, "commit-sha");
        assert!(skill.local_modified);
    }

    #[test]
    fn update_file_preview_returns_a_line_diff_for_the_selected_file() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(directory.path().join("SKILL.md"), "one\nold\nthree\n").unwrap();
        let mut skill = github_cli_skill("id", "demo");
        skill.canonical_dir = directory.path().to_path_buf();
        skill.latest_ref = Some("commit-sha".into());
        skill.update_files = vec![UpdateFileChange {
            path: "SKILL.md".into(),
            kind: "modified".into(),
        }];
        skill.source = SkillSource::SkillsCli {
            source: "owner/repo".into(),
            source_url: None,
            source_type: "github".into(),
            skill_path: Some("skills/demo/SKILL.md".into()),
            folder_hash: Some("old-tree".into()),
            git_ref: None,
            lock_scope: crate::lockfile::LockScope::Global,
        };

        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let request = read_request(&mut stream);
            let body = b"one\nnew\nthree\n";
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            )
            .unwrap();
            stream.write_all(body).unwrap();
            request
        });

        let preview =
            preview_update_file_with_agent_and_base(&skill, "SKILL.md", &test_agent(), &base)
                .unwrap();

        assert_eq!(preview.path, "SKILL.md");
        assert!(preview.lines.iter().any(|line| {
            line.kind == "removed" && line.old_line == Some(2) && line.text == "old"
        }));
        assert!(preview.lines.iter().any(|line| {
            line.kind == "added" && line.new_line == Some(2) && line.text == "new"
        }));
        assert!(
            server
                .join()
                .unwrap()
                .contains("GET /owner/repo/commit-sha/skills/demo/SKILL.md ")
        );
    }

    #[test]
    fn update_file_preview_rejects_paths_outside_the_checked_update() {
        let skill = github_cli_skill("id", "demo");
        let error = preview_update_file_with_agent_and_base(
            &skill,
            "../secret",
            &test_agent(),
            "http://127.0.0.1",
        )
        .unwrap_err();
        assert!(error.to_string().contains("invalid update path"));
    }

    #[test]
    fn parses_github_shorthand() {
        let (o, r) = parse_owner_repo("vercel-labs/agent-skills").unwrap();
        assert_eq!(o, "vercel-labs");
        assert_eq!(r, "agent-skills");
        let (o, r) = parse_owner_repo("https://github.com/acme/skills.git").unwrap();
        assert_eq!((o, r), ("acme".into(), "skills".into()));
        let (o, r) = parse_owner_repo("git@github.com:acme/skills.git").unwrap();
        assert_eq!((o, r), ("acme".into(), "skills".into()));
    }

    #[test]
    fn github_get_sends_required_headers_and_reads_json() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = server_url(&listener);
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let request = read_request(&mut stream);
            stream
                .write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 13\r\nConnection: close\r\n\r\n{\"sha\":\"abc\"}",
                )
                .unwrap();
            request
        });

        let mut response =
            github_get_with_agent(&test_agent(), &url, "application/vnd.github.object+json")
                .unwrap();
        let json: serde_json::Value = response.body_mut().read_json().unwrap();
        assert_eq!(json["sha"], "abc");

        let request = server.join().unwrap().to_ascii_lowercase();
        assert!(request.contains("user-agent: skillkit\r\n"));
        assert!(request.contains("accept: application/vnd.github.object+json\r\n"));
        assert!(!request.contains("authorization:"));
    }

    #[test]
    fn github_get_surfaces_http_status_errors_without_retrying() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = server_url(&listener);
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let _ = read_request(&mut stream);
            let reset = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
                + 120;
            write!(
                stream,
                "HTTP/1.1 403 Forbidden\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: {reset}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
        });

        let error = github_get_with_agent(&test_agent(), &url, "text/plain").unwrap_err();
        let message = format_check_error(&error);
        assert!(message.contains("0 requests remaining"), "{message}");
        assert!(message.contains("Retry in about 2 min"), "{message}");
        server.join().unwrap();
    }

    #[test]
    fn github_get_retries_one_dropped_connection() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = server_url(&listener);
        let server = thread::spawn(move || {
            for attempt in 0..2 {
                let (mut stream, _) = listener.accept().unwrap();
                let _ = read_request(&mut stream);
                if attempt == 1 {
                    stream
                        .write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
                        )
                        .unwrap();
                }
            }
        });

        let mut response = github_get_with_agent(&test_agent(), &url, "text/plain").unwrap();
        assert_eq!(response.body_mut().read_to_string().unwrap(), "ok");
        server.join().unwrap();
    }

    #[test]
    fn attach_lockfile_then_check_local_and_non_github() {
        use crate::lockfile::{LockIndex, LockScope, SkillLockEntry};
        use crate::model::Scope;

        let mut locked = crate::model::test_skill(
            "id",
            "frontend-design",
            Scope::Global,
            VersionStatus::Unknown,
        );
        let mut index = LockIndex::default();
        index.entries.push((
            "frontend-design".into(),
            LockScope::Global,
            SkillLockEntry {
                source: Some("vercel-labs/agent-skills".into()),
                source_type: Some("github".into()),
                source_url: Some("https://github.com/vercel-labs/agent-skills".into()),
                skill_path: Some("skills/frontend-design/SKILL.md".into()),
                skill_folder_hash: Some("abc".into()),
                computed_hash: None,
                ref_name: None,
                git_ref: None,
            },
        ));
        attach_sources(std::slice::from_mut(&mut locked), &index);
        assert!(matches!(locked.source, SkillSource::SkillsCli { .. }));

        let mut local =
            crate::model::test_skill("local", "notes", Scope::Custom, VersionStatus::Unknown);
        attach_sources(std::slice::from_mut(&mut local), &LockIndex::default());
        assert!(matches!(local.source, SkillSource::Local));
        check_updates(std::slice::from_mut(&mut local), |_| true);
        assert_eq!(local.version, VersionStatus::Untracked);
        assert!(local.version_error.is_none());

        let mut npm = crate::model::test_skill("n", "pkg", Scope::Global, VersionStatus::Unknown);
        npm.source = SkillSource::SkillsCli {
            source: "some-registry-pkg".into(),
            source_url: None,
            source_type: "npm".into(),
            skill_path: None,
            folder_hash: None,
            git_ref: None,
            lock_scope: LockScope::Global,
        };
        check_updates(std::slice::from_mut(&mut npm), |_| true);
        assert_eq!(npm.version, VersionStatus::Untracked);
    }

    #[test]
    fn attach_sources_does_not_apply_global_lock_to_project_skill() {
        use crate::lockfile::{LockIndex, LockScope, SkillLockEntry};
        use crate::model::Scope;

        let mut project = crate::model::test_skill(
            "p",
            "frontend-design",
            Scope::Project,
            VersionStatus::Unknown,
        );
        project.project_root = Some(PathBuf::from("/proj"));
        let mut index = LockIndex::default();
        index.entries.push((
            "frontend-design".into(),
            LockScope::Global,
            SkillLockEntry {
                source: Some("vercel-labs/agent-skills".into()),
                source_type: Some("github".into()),
                skill_path: Some("skills/frontend-design/SKILL.md".into()),
                ..SkillLockEntry::default()
            },
        ));
        attach_sources(std::slice::from_mut(&mut project), &index);
        assert!(
            matches!(project.source, SkillSource::Local),
            "project skill must not inherit the global npx lock"
        );
    }

    #[test]
    fn detect_git_from_nested_skill_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path();
        let git_ok = std::process::Command::new("git")
            .args(["init"])
            .current_dir(repo)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !git_ok {
            return;
        }
        let _ = std::process::Command::new("git")
            .args([
                "remote",
                "add",
                "origin",
                "https://github.com/acme/skills.git",
            ])
            .current_dir(repo)
            .status();
        let nested = repo.join("skills/foo");
        std::fs::create_dir_all(&nested).unwrap();
        match detect_git(&nested) {
            Some(SkillSource::Git {
                remote, repo_root, ..
            }) => {
                assert!(remote.contains("acme/skills"));
                assert_eq!(repo_root, repo);
            }
            other => panic!("expected git source, got {other:?}"),
        }
    }

    #[test]
    fn format_check_error_explains_github_http_status() {
        let err = anyhow::Error::from(ureq::Error::StatusCode(403));
        let msg = format_check_error(&err);
        assert!(msg.contains("403"), "{msg}");
        assert!(msg.to_lowercase().contains("rate limit"), "{msg}");
        assert!(is_fatal_github_error(&msg), "{msg}");

        let not_found = format_check_error(&anyhow::Error::from(ureq::Error::StatusCode(404)));
        assert!(not_found.contains("404"), "{not_found}");
        assert!(!is_fatal_github_error(&not_found), "{not_found}");

        let other = format_check_error(&anyhow::anyhow!("no upstream"));
        assert_eq!(other, "no upstream");
    }

    #[test]
    fn check_updates_skips_progress_for_local_skills() {
        let mut local = crate::model::test_skill(
            "local",
            "notes",
            crate::model::Scope::Custom,
            VersionStatus::Unknown,
        );
        let mut calls = 0;
        check_updates(std::slice::from_mut(&mut local), |_| {
            calls += 1;
            true
        });
        assert_eq!(calls, 0);
        assert_eq!(local.version, VersionStatus::Untracked);
    }

    #[test]
    fn check_updates_stops_when_callback_returns_false() {
        let mut skills = vec![
            github_cli_skill("a", "alpha"),
            github_cli_skill("b", "beta"),
        ];
        check_updates(&mut skills, |_| false);
        assert!(skills.iter().all(|s| s.version == VersionStatus::Unknown));
        assert!(skills.iter().all(|s| s.version_error.is_none()));
    }

    #[test]
    fn git_update_check_reads_remote_tip_without_fetching_the_repository() {
        let temp = tempfile::tempdir().unwrap();
        let git = temp.path().join("git");
        fs::write(
            &git,
            r#"#!/bin/sh
printf '%s\n' "$*" >> "$0.log"
case "$1" in
  --version) echo "git version 2.50.0" ;;
  fetch) /bin/sleep 2 ;;
  describe)
    case "$*" in
      *HEAD) echo "local-version" ;;
      *) echo "remote-version" ;;
    esac
    ;;
  rev-list) echo "1" ;;
  rev-parse)
    case "$*" in
      *--abbrev-ref*--symbolic-full-name*) echo "origin/main" ;;
      *HEAD) echo "1111111111111111111111111111111111111111" ;;
    esac
    ;;
  ls-remote) printf '2222222222222222222222222222222222222222\trefs/heads/main\n' ;;
  cat-file|merge-base) exit 1 ;;
esac
"#,
        )
        .unwrap();
        fs::set_permissions(&git, fs::Permissions::from_mode(0o755)).unwrap();
        let tools = RuntimeTools::discover(
            crate::runtime_tools::RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: Some(git.clone()),
                npx: Some(temp.path().join("missing-npx")),
            },
        );
        let repo = temp.path().join("repo");
        fs::create_dir(&repo).unwrap();
        let mut skill = crate::model::test_skill(
            "git-skill",
            "project-skill",
            crate::model::Scope::Project,
            VersionStatus::Unknown,
        );
        skill.source = SkillSource::Git {
            repo_root: repo,
            remote: "git@github.com:acme/project.git".into(),
            branch: Some("main".into()),
        };

        let started = Instant::now();
        check_updates_with_runtime(std::slice::from_mut(&mut skill), &tools, |_| true);
        let elapsed = started.elapsed();
        let log = fs::read_to_string(format!("{}.log", git.display())).unwrap();

        assert!(
            elapsed < Duration::from_secs(1),
            "remote check took {elapsed:?}"
        );
        assert!(!log.lines().any(|line| line.starts_with("fetch ")), "{log}");
        assert!(
            log.lines()
                .any(|line| line == "ls-remote --exit-code origin refs/heads/main"),
            "{log}"
        );
        assert_eq!(skill.version, VersionStatus::UpdateAvailable);
        assert_eq!(
            skill.latest_ref.as_deref(),
            Some("2222222222222222222222222222222222222222")
        );
    }

    #[test]
    fn git_update_check_cancels_an_active_remote_lookup() {
        let temp = tempfile::tempdir().unwrap();
        let git = temp.path().join("git");
        fs::write(
            &git,
            r#"#!/bin/sh
case "$1" in
  --version) echo "git version 2.50.0" ;;
  rev-parse) echo "origin/main" ;;
  ls-remote) exec /bin/sleep 5 ;;
esac
"#,
        )
        .unwrap();
        fs::set_permissions(&git, fs::Permissions::from_mode(0o755)).unwrap();
        let tools = RuntimeTools::discover(
            crate::runtime_tools::RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: Some(git),
                npx: Some(temp.path().join("missing-npx")),
            },
        );
        let repo = temp.path().join("repo");
        fs::create_dir(&repo).unwrap();
        let mut skill = crate::model::test_skill(
            "git-skill",
            "project-skill",
            crate::model::Scope::Project,
            VersionStatus::Unknown,
        );
        skill.source = SkillSource::Git {
            repo_root: repo,
            remote: "git@github.com:acme/project.git".into(),
            branch: Some("main".into()),
        };
        let mut progress_calls = 0;

        let started = Instant::now();
        check_updates_with_runtime(std::slice::from_mut(&mut skill), &tools, |_| {
            progress_calls += 1;
            progress_calls == 1
        });

        assert!(started.elapsed() < Duration::from_secs(1));
        assert!(progress_calls >= 2);
        assert_eq!(skill.version, VersionStatus::Unknown);
        assert!(skill.version_error.is_none());
    }
}
