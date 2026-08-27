use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

use crate::lockfile::LockScope;
use crate::model::{Skill, SkillSource};
use crate::runtime_tools::{RuntimeOverrides, RuntimeTool, RuntimeTools, ToolRequest};

#[derive(Debug, Clone)]
pub struct UpdateOutcome {
    pub skill_id: String,
    pub name: String,
    pub ok: bool,
    pub message: String,
}

pub struct UpdateProgress {
    pub done: usize,
    pub total: usize,
    pub name: String,
}

pub fn update_skill(skill: &Skill) -> UpdateOutcome {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    update_skill_with_runtime(skill, &tools)
}

pub fn update_skill_with_runtime(skill: &Skill, tools: &RuntimeTools) -> UpdateOutcome {
    match &skill.source {
        SkillSource::SkillsCli { .. } => run_skills_cli_update(skill, tools),
        SkillSource::Git { repo_root, .. } => git_pull(&skill.id, &skill.name, repo_root, tools),
        SkillSource::Local => UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: false,
            message: "local skill has no upstream".into(),
        },
    }
}

pub fn update_all(
    skills: &[Skill],
    on_progress: impl FnMut(UpdateProgress) -> bool,
) -> Vec<UpdateOutcome> {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    update_all_with_runtime(skills, &tools, on_progress)
}

pub fn update_all_with_runtime(
    skills: &[Skill],
    tools: &RuntimeTools,
    mut on_progress: impl FnMut(UpdateProgress) -> bool,
) -> Vec<UpdateOutcome> {
    let outdated: Vec<&Skill> = skills
        .iter()
        .filter(|s| s.version == crate::model::VersionStatus::UpdateAvailable)
        .collect();

    // Git clones: one pull per repo.
    let mut git_repos: BTreeMap<PathBuf, Vec<&Skill>> = BTreeMap::new();
    let mut cli: Vec<&Skill> = Vec::new();
    for skill in &outdated {
        match &skill.source {
            SkillSource::Git { repo_root, .. } => {
                git_repos.entry(repo_root.clone()).or_default().push(skill);
            }
            SkillSource::SkillsCli { .. } => cli.push(skill),
            SkillSource::Local => {}
        }
    }

    let total = git_repos.len() + cli.len();
    let mut done = 0;
    let mut out = Vec::new();

    for (repo, repo_skills) in git_repos {
        let names = repo_skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>()
            .join(", ");
        if !on_progress(UpdateProgress {
            done,
            total,
            name: names.clone(),
        }) {
            break;
        }
        let shared = git_pull("", &names, &repo, tools);
        for skill in repo_skills {
            out.push(UpdateOutcome {
                skill_id: skill.id.clone(),
                name: skill.name.clone(),
                ok: shared.ok,
                message: shared.message.clone(),
            });
        }
        done += 1;
    }

    for skill in cli {
        if !on_progress(UpdateProgress {
            done,
            total,
            name: skill.name.clone(),
        }) {
            break;
        }
        out.push(update_skill_with_runtime(skill, tools));
        done += 1;
    }

    out
}

pub fn install_skill(
    spec: &str,
    skill: Option<&str>,
    global: bool,
    cwd: Option<&Path>,
) -> UpdateOutcome {
    let tools = RuntimeTools::current(RuntimeOverrides::default());
    install_skill_with_runtime(spec, skill, global, cwd, &tools)
}

pub fn install_skill_with_runtime(
    spec: &str,
    skill: Option<&str>,
    global: bool,
    cwd: Option<&Path>,
    tools: &RuntimeTools,
) -> UpdateOutcome {
    let source = normalize_install_spec(spec);
    if source.is_empty() {
        return UpdateOutcome {
            skill_id: skill.unwrap_or("install").into(),
            name: skill.unwrap_or("install").into(),
            ok: false,
            message: "paste an npx skills source such as owner/repo".into(),
        };
    }
    let mut args = vec![
        "--yes".into(),
        "skills@latest".into(),
        "add".into(),
        source.clone(),
    ];
    if let Some(skill) = skill.map(str::trim).filter(|s| !s.is_empty()) {
        args.push("--skill".into());
        args.push(skill.to_string());
    }
    if global {
        args.push("-g".into());
    }
    args.push("-y".into());
    let request = ToolRequest {
        args: args.into_iter().map(OsString::from).collect(),
        cwd: cwd.map(Path::to_path_buf),
        ..ToolRequest::default()
    };
    match tools.execute(RuntimeTool::Npx, request) {
        Ok(out) if out.status.success() => UpdateOutcome {
            skill_id: skill.unwrap_or(&source).into(),
            name: skill.unwrap_or(&source).into(),
            ok: true,
            message: format!("installed {source}"),
        },
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            let stdout = String::from_utf8_lossy(&out.stdout);
            UpdateOutcome {
                skill_id: skill.unwrap_or(&source).into(),
                name: skill.unwrap_or(&source).into(),
                ok: false,
                message: format!("{}{}", err.trim(), stdout.trim()),
            }
        }
        Err(error) => UpdateOutcome {
            skill_id: skill.unwrap_or(&source).into(),
            name: skill.unwrap_or(&source).into(),
            ok: false,
            message: error.to_string(),
        },
    }
}

pub fn normalize_install_spec(raw: &str) -> String {
    let tokens: Vec<&str> = raw.split_whitespace().collect();
    let mut out: Vec<&str> = Vec::new();
    let mut i = 0;
    while i < tokens.len() {
        let t = tokens[i];
        if matches!(
            t,
            "npx" | "--yes" | "skills" | "skills@latest" | "add" | "-g" | "-y" | "-gy"
        ) {
            i += 1;
            continue;
        }
        if t == "--skill" {
            i += 2;
            continue;
        }
        if t.starts_with('-') {
            i += 1;
            continue;
        }
        out.push(t);
        i += 1;
    }
    out.join(" ")
}

fn git_pull(skill_id: &str, name: &str, repo: &Path, tools: &RuntimeTools) -> UpdateOutcome {
    let output = tools.execute(
        RuntimeTool::Git,
        ToolRequest {
            args: ["pull", "--ff-only"]
                .into_iter()
                .map(OsString::from)
                .collect(),
            cwd: Some(repo.to_path_buf()),
            ..ToolRequest::default()
        },
    );
    match output {
        Ok(out) if out.status.success() => UpdateOutcome {
            skill_id: skill_id.into(),
            name: name.into(),
            ok: true,
            message: String::from_utf8_lossy(&out.stdout).trim().to_string(),
        },
        Ok(out) => UpdateOutcome {
            skill_id: skill_id.into(),
            name: name.into(),
            ok: false,
            message: String::from_utf8_lossy(&out.stderr).trim().to_string(),
        },
        Err(err) => UpdateOutcome {
            skill_id: skill_id.into(),
            name: name.into(),
            ok: false,
            message: err.to_string(),
        },
    }
}

/// Source argument for `npx skills add` during update.
/// Matches `buildUpdateInstallSource` / `buildLocalUpdateSource` in vercel-labs/skills.
pub fn install_source(
    source: &str,
    source_url: Option<&str>,
    source_type: &str,
    skill_path: Option<&str>,
    git_ref: Option<&str>,
    project: bool,
) -> Option<String> {
    if project {
        let src = local_source(source, source_url, source_type)?;
        return Some(match skill_path.filter(|path| !path.is_empty()) {
            Some(path) => append_folder_and_ref(&src, path, git_ref),
            None => format_source_input(&src, git_ref),
        });
    }
    match skill_path.filter(|path| !path.is_empty()) {
        None => {
            let src = if !source_type.is_empty() && source_type != "github" {
                local_source(source, source_url, source_type)?
            } else {
                nonempty(source_url).unwrap_or(source).to_string()
            };
            Some(format_source_input(&src, git_ref))
        }
        Some(path) => {
            let src = if !source_type.is_empty() && source_type != "github" {
                local_source(source, source_url, source_type)?
            } else if source.is_empty() {
                return None;
            } else {
                source.to_string()
            };
            Some(append_folder_and_ref(&src, path, git_ref))
        }
    }
}

fn run_skills_cli_update(skill: &Skill, tools: &RuntimeTools) -> UpdateOutcome {
    let SkillSource::SkillsCli {
        source,
        source_url,
        source_type,
        skill_path,
        git_ref,
        lock_scope,
        ..
    } = &skill.source
    else {
        return UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: false,
            message: "not an npx skills install".into(),
        };
    };
    let project = matches!(lock_scope, LockScope::Project { .. });
    let Some(install_url) = install_source(
        source,
        source_url.as_deref(),
        source_type,
        skill_path.as_deref(),
        git_ref.as_deref(),
        project,
    ) else {
        return UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: false,
            message: "lock file is missing a usable source for this skill".into(),
        };
    };
    let full_depth = should_use_full_depth(
        source,
        source_url.as_deref(),
        source_type,
        skill_path.as_deref(),
        project,
    );
    let mut request = ToolRequest {
        args: skills_cli_argv(&skill.name, &install_url, !project, full_depth)
            .into_iter()
            .map(OsString::from)
            .collect(),
        ..ToolRequest::default()
    };
    if source_type == "github" {
        request
            .env
            .insert(OsString::from("GH_HOST"), OsString::from("github.com"));
    }
    if let LockScope::Project { root } = lock_scope {
        request.cwd = Some(root.clone());
    }
    match tools.execute(RuntimeTool::Npx, request) {
        Ok(out) if out.status.success() => UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: true,
            message: format!("updated from {install_url}"),
        },
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            let stdout = String::from_utf8_lossy(&out.stdout);
            UpdateOutcome {
                skill_id: skill.id.clone(),
                name: skill.name.clone(),
                ok: false,
                message: format!("{}{}", err.trim(), stdout.trim()),
            }
        }
        Err(error) => UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: false,
            message: error.to_string(),
        },
    }
}

fn skills_cli_argv(name: &str, install_url: &str, global: bool, full_depth: bool) -> Vec<String> {
    let mut args = vec![
        "--yes".into(),
        "skills@latest".into(),
        "add".into(),
        install_url.into(),
        "--skill".into(),
        name.into(),
    ];
    if full_depth {
        args.push("--full-depth".into());
    }
    if global {
        args.push("-g".into());
    }
    args.push("-y".into());
    args
}

fn should_use_full_depth(
    source: &str,
    source_url: Option<&str>,
    source_type: &str,
    skill_path: Option<&str>,
    project: bool,
) -> bool {
    if skill_path.filter(|path| !path.is_empty()).is_none() {
        return false;
    }
    let src = if project || (!source_type.is_empty() && source_type != "github") {
        local_source(source, source_url, source_type)
    } else {
        Some(source.to_string())
    };
    src.is_some_and(|src| !supports_appended_subpath(&src))
}

fn local_source(source: &str, source_url: Option<&str>, source_type: &str) -> Option<String> {
    if let Some(url) = nonempty(source_url) {
        return Some(url.to_string());
    }
    let requires_url = source_type == "git" || source_type == "gitlab";
    if requires_url && is_bare_shorthand(source) {
        return None;
    }
    nonempty(Some(source)).map(str::to_string)
}

fn nonempty(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|s| !s.is_empty())
}

fn is_bare_shorthand(source: &str) -> bool {
    !source.contains(':') && !source.starts_with('.') && !source.starts_with('/')
}

fn supports_appended_subpath(source: &str) -> bool {
    if source.starts_with("git@") || source.starts_with("ssh://") {
        return false;
    }
    if source.ends_with(".git") {
        return false;
    }
    if let Some(rest) = source
        .strip_prefix("https://")
        .or_else(|| source.strip_prefix("http://"))
    {
        let host = rest
            .split('/')
            .next()
            .unwrap_or("")
            .split(':')
            .next()
            .unwrap_or("");
        return host == "github.com" || host == "gitlab.com";
    }
    true
}

fn derive_skill_folder(skill_path: &str) -> String {
    let folder = skill_path
        .strip_suffix("/SKILL.md")
        .or_else(|| skill_path.strip_suffix("SKILL.md"))
        .unwrap_or(skill_path);
    folder.trim_end_matches('/').to_string()
}

fn format_source_input(source: &str, git_ref: Option<&str>) -> String {
    match nonempty(git_ref) {
        Some(git_ref) => format!("{source}#{git_ref}"),
        None => source.to_string(),
    }
}

fn append_folder_and_ref(source: &str, skill_path: &str, git_ref: Option<&str>) -> String {
    if !supports_appended_subpath(source) {
        return format_source_input(source, git_ref);
    }
    let folder = derive_skill_folder(skill_path);
    let with_folder = if folder.is_empty() {
        source.to_string()
    } else {
        format!("{source}/{folder}")
    };
    format_source_input(&with_folder, git_ref)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lockfile::LockScope;
    use crate::model::{Scope, Skill, VersionStatus};

    fn sample_cli(name: &str) -> Skill {
        Skill {
            id: name.into(),
            name: name.into(),
            description: String::new(),
            skill_md: PathBuf::from("/tmp/SKILL.md"),
            canonical_dir: PathBuf::from("/tmp"),
            agents: vec![],
            scope: Scope::Global,
            project_root: None,
            source: SkillSource::SkillsCli {
                source: "owner/repo".into(),
                source_url: Some("https://github.com/owner/repo".into()),
                source_type: "github".into(),
                skill_path: None,
                folder_hash: Some("abc".into()),
                git_ref: None,
                lock_scope: LockScope::Global,
            },
            version: VersionStatus::UpdateAvailable,
            latest_ref: None,
            installed_version: None,
            latest_version: None,
            version_error: None,
            update_files: Vec::new(),
            local_modified: false,
            content_fingerprint: format!("sample-{name}"),
        }
    }

    #[test]
    fn local_skill_cannot_update() {
        let mut skill = sample_cli("x");
        skill.source = SkillSource::Local;
        let out = update_skill(&skill);
        assert!(!out.ok);
        assert_eq!(out.skill_id, "x");
    }

    #[test]
    fn update_all_skips_up_to_date() {
        let mut skill = sample_cli("x");
        skill.version = VersionStatus::UpToDate;
        let out = update_all(std::slice::from_ref(&skill), |_| true);
        assert!(out.is_empty());
    }

    #[test]
    fn install_skill_rejects_empty_spec() {
        let out = install_skill("  ", None, true, None);
        assert!(!out.ok);
        assert!(out.message.contains("owner/repo"));
    }

    #[test]
    fn normalize_install_spec_strips_cli_noise() {
        assert_eq!(
            normalize_install_spec("npx skills add vercel-labs/agent-skills -g -y"),
            "vercel-labs/agent-skills"
        );
        assert_eq!(
            normalize_install_spec("npx --yes skills@latest add owner/repo --skill foo"),
            "owner/repo"
        );
    }

    #[test]
    fn install_source_matches_skills_cli() {
        assert_eq!(
            install_source(
                "vercel-labs/agent-skills",
                Some("https://github.com/vercel-labs/agent-skills"),
                "github",
                Some("skills/frontend-design/SKILL.md"),
                None,
                false,
            )
            .as_deref(),
            Some("vercel-labs/agent-skills/skills/frontend-design")
        );
        assert_eq!(
            install_source(
                "vercel-labs/agent-skills",
                Some("https://github.com/vercel-labs/agent-skills"),
                "github",
                Some("skills/frontend-design/SKILL.md"),
                Some("main"),
                false,
            )
            .as_deref(),
            Some("vercel-labs/agent-skills/skills/frontend-design#main")
        );
        assert_eq!(
            install_source(
                "vercel-labs/agent-skills",
                Some("https://github.com/vercel-labs/agent-skills"),
                "github",
                None,
                None,
                false,
            )
            .as_deref(),
            Some("https://github.com/vercel-labs/agent-skills")
        );
        assert_eq!(
            install_source(
                "vercel-labs/agent-skills",
                Some("https://github.com/vercel-labs/agent-skills"),
                "github",
                Some("skills/frontend-design/SKILL.md"),
                None,
                true,
            )
            .as_deref(),
            Some("https://github.com/vercel-labs/agent-skills/skills/frontend-design")
        );
        assert_eq!(
            install_source(
                "acme/skills",
                Some("https://github.com/acme/skills.git"),
                "github",
                Some("skills/foo/SKILL.md"),
                Some("v1"),
                true,
            )
            .as_deref(),
            Some("https://github.com/acme/skills.git#v1")
        );
        assert!(
            install_source(
                "acme/skills",
                None,
                "git",
                Some("skills/foo/SKILL.md"),
                None,
                true
            )
            .is_none()
        );
    }

    #[test]
    fn skills_cli_argv_targets_one_skill() {
        assert_eq!(
            skills_cli_argv(
                "frontend-design",
                "vercel-labs/agent-skills/skills/frontend-design",
                true,
                false,
            ),
            [
                "--yes",
                "skills@latest",
                "add",
                "vercel-labs/agent-skills/skills/frontend-design",
                "--skill",
                "frontend-design",
                "-g",
                "-y",
            ]
        );
        assert_eq!(
            skills_cli_argv("foo", "https://github.com/acme/skills.git", false, true),
            [
                "--yes",
                "skills@latest",
                "add",
                "https://github.com/acme/skills.git",
                "--skill",
                "foo",
                "--full-depth",
                "-y",
            ]
        );
    }
}
