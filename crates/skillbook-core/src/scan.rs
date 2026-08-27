use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use sha1::{Digest, Sha1};
use walkdir::WalkDir;

use crate::config::AppConfig;
use crate::frontmatter::parse_skill_md;
use crate::lockfile::load_all_locks;
use crate::model::{AgentLink, ScanResult, Scope, Skill, SkillSource, VersionStatus};
#[cfg(target_os = "macos")]
use crate::paths::PROJECT_CONTAINERS;
use crate::paths::{
    agent_from_path, global_skill_dirs, is_agent_dir_name, is_within_worktree, is_worktree_dir,
    project_container_names, skip_dir_name,
};
use crate::runtime_tools::{RuntimeOverrides, RuntimeTools};
use crate::source::attach_sources_with_runtime;

/// Scan the machine for Agent Skills using `config`.
pub fn scan(config: &AppConfig) -> ScanResult {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    scan_with_home(config, &home)
}

pub fn scan_with_home(config: &AppConfig, home: &Path) -> ScanResult {
    let tools = RuntimeTools::current(RuntimeOverrides {
        git: config.git_path.clone(),
        npx: config.npx_path.clone(),
    });
    scan_with_home_and_runtime_options(config, home, &tools, true)
}

pub fn scan_with_home_including_global_equivalents(config: &AppConfig, home: &Path) -> ScanResult {
    let tools = RuntimeTools::current(RuntimeOverrides {
        git: config.git_path.clone(),
        npx: config.npx_path.clone(),
    });
    scan_with_home_and_runtime_options(config, home, &tools, false)
}

pub fn scan_with_runtime(config: &AppConfig, tools: &RuntimeTools) -> ScanResult {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    scan_with_home_and_runtime(config, &home, tools)
}

pub fn scan_with_home_and_runtime(
    config: &AppConfig,
    home: &Path,
    tools: &RuntimeTools,
) -> ScanResult {
    scan_with_home_and_runtime_options(config, home, tools, true)
}

fn scan_with_home_and_runtime_options(
    config: &AppConfig,
    home: &Path,
    tools: &RuntimeTools,
    suppress_global_copies: bool,
) -> ScanResult {
    let mut result = ScanResult::default();
    let mut state = ScanState::default();

    for (agent, dir) in global_skill_dirs(home) {
        state.watched.insert(dir.clone());
        collect_from_skills_dir(
            &dir,
            &agent,
            Scope::Global,
            None,
            None,
            &mut state.by_canonical,
            &mut state.errors,
        );
    }

    if !config.project_roots.is_empty() {
        scan_roots(
            &config.project_roots,
            home,
            Scope::Project,
            config,
            &mut state,
        );
    }

    if !config.custom_roots.is_empty() {
        scan_roots(
            &config.custom_roots,
            home,
            Scope::Custom,
            config,
            &mut state,
        );
    }

    let locks = load_all_locks(home, &state.project_roots);
    let mut skills: Vec<Skill> = state.by_canonical.into_values().collect();
    attach_sources_with_runtime(&mut skills, &locks, tools);
    if suppress_global_copies {
        suppress_global_equivalents(&mut skills);
    }
    result.skills = skills;
    result.errors = state.errors;
    result.watched_dirs = state.watched.into_iter().collect();
    result.sort_skills();
    result
}

#[derive(Default)]
struct ScanState {
    by_canonical: BTreeMap<PathBuf, Skill>,
    watched: HashSet<PathBuf>,
    project_roots: Vec<PathBuf>,
    errors: Vec<String>,
}

fn scan_roots(
    roots: &[PathBuf],
    home: &Path,
    default_scope: Scope,
    config: &AppConfig,
    state: &mut ScanState,
) {
    for root in roots {
        if !root.exists() {
            state
                .errors
                .push(format!("scan root missing: {}", root.display()));
            continue;
        }
        let found = discover_skill_md_files(root, config);
        for skill_md in found {
            let Some(parent) = skill_md.parent() else {
                continue;
            };
            if is_under_global(parent, home) && default_scope != Scope::Custom {
                // Already collected via global_skill_dirs.
                continue;
            }
            let scope = if default_scope == Scope::Custom {
                Scope::Custom
            } else {
                Scope::Project
            };
            let project_root = if scope == Scope::Project {
                project_root_for_skill(root, parent)
            } else {
                infer_project_root(parent)
            };
            let location_root = if scope == Scope::Custom {
                Some(root.clone())
            } else {
                project_root.clone().or_else(|| Some(root.clone()))
            };
            if let Some(pr) = &project_root {
                state.project_roots.push(pr.clone());
            }
            watch_skill_path(&skill_md, &mut state.watched);
            let agent = agent_from_path(&skill_md);
            ingest_skill(
                parent,
                &agent,
                scope,
                project_root,
                location_root,
                &mut state.by_canonical,
                &mut state.errors,
            );
        }
    }
}

fn watch_skill_path(skill_md: &Path, watched: &mut HashSet<PathBuf>) {
    if let Some(skill_dir) = skill_md.parent() {
        watched.insert(skill_dir.to_path_buf());
        if let Some(container) = skill_dir.parent() {
            watched.insert(container.to_path_buf());
        }
    }
}

fn is_under_global(path: &Path, home: &Path) -> bool {
    global_skill_dirs(home)
        .into_iter()
        .any(|(_, dir)| path.starts_with(&dir))
}

fn discover_skill_md_files(root: &Path, config: &AppConfig) -> Vec<PathBuf> {
    #[cfg_attr(not(target_os = "macos"), allow(unused_mut))]
    let mut found = walk_skill_mds(root, config);
    #[cfg(target_os = "macos")]
    {
        if let Some(paths) = mdfind_skill_mds(root) {
            found.extend(filter_skill_mds(paths, root, config));
            found.sort();
            found.dedup();
        }
    }
    found
        .into_iter()
        .filter(|path| {
            path.starts_with(root)
                && !contains_ignored_directory(root, path, config)
                && !is_within_worktree(root, path)
        })
        .collect()
}

#[cfg(target_os = "macos")]
fn mdfind_skill_mds(root: &Path) -> Option<Vec<PathBuf>> {
    let output = std::process::Command::new("mdfind")
        .arg("-onlyin")
        .arg(root)
        .arg("kMDItemFSName == \"SKILL.md\"")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    Some(
        text.lines()
            .filter(|l| !l.is_empty())
            .map(PathBuf::from)
            .collect(),
    )
}

#[cfg(target_os = "macos")]
fn filter_skill_mds(paths: Vec<PathBuf>, root: &Path, config: &AppConfig) -> Vec<PathBuf> {
    paths
        .into_iter()
        .filter(|path| {
            is_in_known_container(path) && !contains_ignored_directory(root, path, config)
        })
        .collect()
}

#[cfg(target_os = "macos")]
fn is_in_known_container(skill_md: &Path) -> bool {
    let s = skill_md.to_string_lossy();
    PROJECT_CONTAINERS.iter().any(|c| s.contains(c))
        || s.contains("/skills/")
        || skill_md
            .file_name()
            .is_some_and(|n| n == "SKILL.md" && skill_md.parent().is_some())
}

fn walk_skill_mds(root: &Path, config: &AppConfig) -> Vec<PathBuf> {
    if is_worktree_dir(root) {
        return Vec::new();
    }
    let mut out = Vec::new();
    let walker = WalkDir::new(root)
        .follow_links(false)
        .max_depth(12)
        .into_iter()
        .filter_entry(|e| {
            if e.depth() == 0 {
                return true;
            }
            if !e.file_type().is_dir() {
                return true;
            }
            let name = e.file_name().to_string_lossy();
            if directory_name_is_ignored(&name, config) {
                return false;
            }
            if is_worktree_dir(e.path()) {
                return false;
            }
            if name.starts_with('.') {
                return is_agent_dir_name(&name) || name == ".config" || name == ".agents";
            }
            true
        });
    for entry in walker.flatten() {
        if entry.path().is_file() && entry.file_name() == "SKILL.md" {
            out.push(entry.path().to_path_buf());
        } else if entry.file_type().is_symlink() && entry.path().is_dir() {
            let skill_md = entry.path().join("SKILL.md");
            if skill_md.is_file() {
                out.push(skill_md);
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

fn contains_ignored_directory(root: &Path, path: &Path, config: &AppConfig) -> bool {
    let Ok(relative) = path.strip_prefix(root) else {
        return false;
    };
    let directory = relative.parent().unwrap_or(relative);
    directory.components().any(|component| {
        directory_name_is_ignored(&component.as_os_str().to_string_lossy(), config)
    })
}

fn directory_name_is_ignored(name: &str, config: &AppConfig) -> bool {
    skip_dir_name(name)
        || config.is_ignored_name(name)
        || (name.starts_with('.')
            && !is_agent_dir_name(name)
            && name != ".config"
            && name != ".agents")
}

fn collect_from_skills_dir(
    dir: &Path,
    agent: &str,
    scope: Scope,
    project_root: Option<PathBuf>,
    location_root: Option<PathBuf>,
    by_canonical: &mut BTreeMap<PathBuf, Skill>,
    errors: &mut Vec<String>,
) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in rd.flatten() {
        let path = entry.path();
        let skill_md = if path.is_dir() {
            path.join("SKILL.md")
        } else if path.file_name().is_some_and(|n| n == "SKILL.md") {
            path.clone()
        } else {
            continue;
        };
        if !skill_md.is_file() {
            continue;
        }
        let skill_dir = skill_md.parent().unwrap_or(&path);
        ingest_skill(
            skill_dir,
            agent,
            scope,
            project_root.clone(),
            location_root.clone(),
            by_canonical,
            errors,
        );
    }
}

fn ingest_skill(
    skill_dir: &Path,
    agent: &str,
    scope: Scope,
    project_root: Option<PathBuf>,
    location_root: Option<PathBuf>,
    by_canonical: &mut BTreeMap<PathBuf, Skill>,
    errors: &mut Vec<String>,
) {
    let canonical_dir =
        std::fs::canonicalize(skill_dir).unwrap_or_else(|_| skill_dir.to_path_buf());
    let canonical_md = canonical_dir.join("SKILL.md");
    let link = AgentLink {
        agent: agent.to_string(),
        path: skill_dir.to_path_buf(),
        scope,
        root: location_root,
        is_symlink: std::fs::symlink_metadata(skill_dir)
            .is_ok_and(|metadata| metadata.file_type().is_symlink()),
    };
    if let Some(existing) = by_canonical.get_mut(&canonical_dir) {
        if !existing.agents.iter().any(|a| a.path == link.path) {
            existing.agents.push(link);
        }
        return;
    }
    let contents = match std::fs::read_to_string(&canonical_md) {
        Ok(c) => c,
        Err(err) => {
            errors.push(format!("read {}: {err}", canonical_md.display()));
            return;
        }
    };
    let parsed = parse_skill_md(&contents);
    let folder_name = canonical_dir
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "skill".into());
    let name = parsed.name.unwrap_or(folder_name);
    let skill = Skill {
        id: canonical_dir.to_string_lossy().into_owned(),
        name,
        description: parsed.description.unwrap_or_default(),
        skill_md: canonical_md,
        canonical_dir: canonical_dir.clone(),
        agents: vec![link],
        scope,
        project_root,
        source: SkillSource::Local,
        version: VersionStatus::Unknown,
        latest_ref: None,
        installed_version: parsed.version,
        latest_version: None,
        version_error: None,
        update_files: Vec::new(),
        local_modified: false,
        content_fingerprint: skill_fingerprint(&canonical_dir, &contents),
    };
    by_canonical.insert(canonical_dir, skill);
}

fn skill_fingerprint(skill_dir: &Path, skill_md: &str) -> String {
    let mut paths = WalkDir::new(skill_dir)
        .follow_links(false)
        .into_iter()
        .flatten()
        .filter(|entry| entry.depth() > 0)
        .map(|entry| entry.path().to_path_buf())
        .collect::<Vec<_>>();
    paths.sort();

    let mut hasher = Sha1::new();
    for path in paths {
        let Ok(relative) = path.strip_prefix(skill_dir) else {
            continue;
        };
        hasher.update(relative.to_string_lossy().as_bytes());
        let Ok(metadata) = std::fs::symlink_metadata(&path) else {
            return format!("{:x}", Sha1::digest(skill_md.as_bytes()));
        };
        if metadata.file_type().is_symlink() {
            hasher.update(b"symlink");
            match std::fs::read_link(&path) {
                Ok(target) => hasher.update(target.to_string_lossy().as_bytes()),
                Err(_) => return format!("{:x}", Sha1::digest(skill_md.as_bytes())),
            }
        } else if metadata.is_file() {
            hasher.update(b"file");
            match std::fs::read(&path) {
                Ok(contents) => hasher.update(contents),
                Err(_) => return format!("{:x}", Sha1::digest(skill_md.as_bytes())),
            }
        } else if metadata.is_dir() {
            hasher.update(b"directory");
        }
    }
    format!("{:x}", hasher.finalize())
}

fn suppress_global_equivalents(skills: &mut Vec<Skill>) {
    let global = skills
        .iter()
        .filter(|skill| skill.scope == Scope::Global)
        .map(|skill| {
            (
                skill.name.trim().to_lowercase(),
                skill.content_fingerprint.clone(),
            )
        })
        .collect::<HashSet<_>>();
    skills.retain(|skill| {
        skill.scope != Scope::Project
            || !global.contains(&(
                skill.name.trim().to_lowercase(),
                skill.content_fingerprint.clone(),
            ))
    });
}

fn infer_project_root(skill_dir: &Path) -> Option<PathBuf> {
    // `.claude/skills/foo` → project is two parents up from the skill folder.
    let mut dir = skill_dir;
    for _ in 0..6 {
        if dir.join(".git").exists() {
            return Some(dir.to_path_buf());
        }
        dir = dir.parent()?;
    }
    skill_dir
        .parent()
        .and_then(|skills| skills.parent())
        .and_then(|agent| agent.parent())
        .map(Path::to_path_buf)
}

fn project_root_for_skill(scan_root: &Path, skill_dir: &Path) -> Option<PathBuf> {
    if scan_root.join(".git").exists()
        || project_container_names().any(|container| scan_root.join(container).is_dir())
    {
        return Some(scan_root.to_path_buf());
    }

    let relative = skill_dir.strip_prefix(scan_root).ok()?;
    let project_name = relative.components().next()?;
    Some(scan_root.join(project_name.as_os_str()))
}

pub fn read_skill_file(path: &Path) -> anyhow::Result<String> {
    Ok(std::fs::read_to_string(path)?)
}

pub fn write_skill_file(path: &Path, contents: &str) -> anyhow::Result<()> {
    let tmp = path.with_extension("md.tmp");
    std::fs::write(&tmp, contents)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

pub fn create_skill(parent: &Path, name: &str, description: &str) -> anyhow::Result<PathBuf> {
    let slug = sanitize_skill_name(name);
    if slug.is_empty() {
        anyhow::bail!("name must use letters, numbers, or dashes");
    }
    let description = description.trim();
    if description.is_empty() {
        anyhow::bail!("description is required");
    }
    let dir = parent.join(&slug);
    if dir.exists() {
        anyhow::bail!("folder already exists: {}", dir.display());
    }
    std::fs::create_dir_all(&dir)?;
    let yaml = format!("name: {slug}\ndescription: {description}");
    let body = format!("# {name}\n\n");
    write_skill_file(
        &dir.join("SKILL.md"),
        &crate::frontmatter::join_skill_md(Some(&yaml), &body),
    )?;
    Ok(dir)
}

pub fn create_skill_in_folders(
    parents: &[PathBuf],
    name: &str,
    description: &str,
) -> anyhow::Result<PathBuf> {
    let slug = sanitize_skill_name(name);
    if slug.is_empty() {
        anyhow::bail!("name must use letters, numbers, or dashes");
    }

    let mut seen = HashSet::new();
    let mut unique_parents = Vec::new();
    for parent in parents {
        let identity = parent.canonicalize().unwrap_or_else(|_| parent.clone());
        if seen.insert(identity) {
            unique_parents.push(parent.clone());
        }
    }
    if unique_parents.is_empty() {
        anyhow::bail!("choose at least one skill folder");
    }

    let targets: Vec<PathBuf> = unique_parents
        .iter()
        .map(|parent| parent.join(&slug))
        .collect();
    for target in &targets {
        if std::fs::symlink_metadata(target).is_ok() {
            anyhow::bail!("folder already exists: {}", target.display());
        }
    }

    let source = create_skill(&unique_parents[0], name, description)?;
    let canonical_source = match source.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            let _ = std::fs::remove_dir_all(&source);
            return Err(error.into());
        }
    };
    let mut links = Vec::new();

    for target in targets.iter().skip(1) {
        let result = target
            .parent()
            .ok_or_else(|| anyhow::anyhow!("target skill folder is invalid"))
            .and_then(|parent| {
                std::fs::create_dir_all(parent)?;
                create_skill_symlink(&canonical_source, target)?;
                Ok(())
            });
        if let Err(error) = result {
            for link in links {
                let _ = std::fs::remove_file(link);
            }
            let _ = std::fs::remove_dir_all(&source);
            return Err(error);
        }
        links.push(target.clone());
    }

    Ok(source)
}

#[cfg(unix)]
fn create_skill_symlink(source: &Path, target: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(source, target)
}

#[cfg(windows)]
fn create_skill_symlink(source: &Path, target: &Path) -> std::io::Result<()> {
    std::os::windows::fs::symlink_dir(source, target)
}

fn sanitize_skill_name(name: &str) -> String {
    let slug: String = name
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    slug.trim_matches('-')
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

/// Spec requires `name` and `description` in YAML frontmatter.
pub fn validate_skill_frontmatter(yaml: &str) -> Result<(), String> {
    let yaml = yaml.trim();
    if yaml.is_empty() {
        return Err("SKILL.md needs YAML frontmatter with name and description".into());
    }
    let parsed = parse_skill_md(&format!("---\n{yaml}\n---\n"));
    if parsed.name.is_none() {
        return Err("YAML needs a name".into());
    }
    if parsed.description.is_none() {
        return Err("YAML needs a description".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::AppConfig;
    use tempfile::tempdir;

    fn write_skill(dir: &Path, name: &str, body: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(
            dir.join("SKILL.md"),
            format!("---\nname: {name}\ndescription: {name} skill\n---\n\n{body}\n"),
        )
        .unwrap();
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn spotlight_results_skip_dependency_and_generated_folders() {
        let root = PathBuf::from("/workspace");
        let mut config = AppConfig::default();
        config.ignored_names = vec!["private".into()];
        let visible = root.join("app/.agents/skills/visible/SKILL.md");
        let paths = vec![
            visible.clone(),
            root.join("app/node_modules/pkg/.agents/skills/dependency/SKILL.md"),
            root.join("app/vendor/pkg/.agents/skills/vendor/SKILL.md"),
            root.join("app/.next/cache/.agents/skills/generated/SKILL.md"),
            root.join("ios/Pods/pkg/.agents/skills/pod/SKILL.md"),
            root.join("private/.agents/skills/ignored/SKILL.md"),
        ];

        assert_eq!(filter_skill_mds(paths, &root, &config), [visible]);
    }

    #[test]
    fn finds_global_and_dedupes_symlinks() {
        let tmp = tempdir().unwrap();
        let home = tmp.path();
        let canonical = home.join(".agents/skills/shared");
        write_skill(&canonical, "shared", "# Shared");
        let claude = home.join(".claude/skills");
        std::fs::create_dir_all(&claude).unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(&canonical, claude.join("shared")).unwrap();

        let cfg = AppConfig::default();
        let result = scan_with_home(&cfg, home);
        let skill = result
            .skills
            .iter()
            .find(|s| s.name == "shared")
            .expect("shared skill");
        let agents: Vec<_> = skill.agent_names();
        assert!(agents.contains(&"agents".to_string()) || agents.contains(&"claude".to_string()));
        assert!(skill.agents.len() >= 2 || skill.canonical_dir.ends_with("shared"));
        assert!(skill.agents.iter().all(|link| link.scope == Scope::Global));
        #[cfg(unix)]
        assert!(skill.agents.iter().any(|link| link.is_symlink));
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_global_skill_keeps_its_project_placement() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        let canonical = home.join(".agents/skills/shared");
        write_skill(&canonical, "shared", "# Shared");

        let project = tmp.path().join("project");
        std::fs::create_dir_all(project.join(".git")).unwrap();
        let project_skills = project.join(".agents/skills");
        std::fs::create_dir_all(&project_skills).unwrap();
        std::os::unix::fs::symlink(&canonical, project_skills.join("shared")).unwrap();

        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![project.clone()];
        let result = scan_with_home(&cfg, &home);

        assert_eq!(result.skills.len(), 1);
        let skill = &result.skills[0];
        assert_eq!(skill.scope, Scope::Global);
        assert!(skill.agents.iter().any(|link| {
            link.scope == Scope::Project
                && link.root.as_deref() == Some(project.as_path())
                && link.is_symlink
        }));
    }

    #[test]
    fn scans_custom_root_project_layout() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let project = tmp.path().join("proj");
        write_skill(&project.join(".cursor/skills/deploy"), "deploy", "# Deploy");
        let mut cfg = AppConfig::default();
        cfg.project_roots.clear();
        cfg.custom_roots = vec![project.clone()];
        let result = scan_with_home(&cfg, &home);
        assert_eq!(result.skills.len(), 1);
        assert_eq!(result.skills[0].name, "deploy");
        assert_eq!(result.skills[0].scope, Scope::Custom);
        assert!(result.skills[0].agents.iter().any(|a| a.agent == "cursor"));
        assert!(
            result.skills[0]
                .agents
                .iter()
                .any(|link| link.root.as_deref() == Some(project.as_path()))
        );
    }

    #[test]
    fn home_walk_finds_project_skill_and_skips_node_modules() {
        let tmp = tempdir().unwrap();
        let home = tmp.path();
        write_skill(&home.join("app/.cursor/skills/ship"), "ship", "# Ship");
        write_skill(
            &home.join("app/node_modules/.cursor/skills/junk"),
            "junk",
            "# Junk",
        );
        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![home.to_path_buf()];
        let result = scan_with_home(&cfg, home);
        let names: Vec<_> = result.skills.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"ship"), "{names:?}");
        assert!(!names.contains(&"junk"), "{names:?}");
        assert_eq!(
            result
                .skills
                .iter()
                .find(|s| s.name == "ship")
                .unwrap()
                .scope,
            Scope::Project
        );
    }

    #[test]
    fn skips_managed_and_git_linked_worktrees() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        let work = tmp.path().join("Work");
        let project = work.join("product");
        write_skill(
            &project.join(".agents/skills/project-only"),
            "project-only",
            "# Project",
        );
        write_skill(
            &project.join(".claude/worktrees/route-titles/.agents/skills/copied"),
            "copied",
            "# Copied",
        );
        let linked = work.join("product-task");
        std::fs::create_dir_all(&linked).unwrap();
        std::fs::write(
            linked.join(".git"),
            "gitdir: /stale/product/.git/worktrees/product-task\n",
        )
        .unwrap();
        write_skill(
            &linked.join(".agents/skills/copied-again"),
            "copied-again",
            "# Copied",
        );

        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![work];
        let result = scan_with_home(&cfg, &home);

        assert_eq!(
            result
                .skills
                .iter()
                .map(|skill| skill.name.as_str())
                .collect::<Vec<_>>(),
            ["project-only"]
        );
    }

    #[test]
    fn anchors_nested_skills_to_the_immediate_project_folder() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        let work = tmp.path().join("Work");
        let project = work.join("product");
        let nested = project.join("packages/plugin");
        std::fs::create_dir_all(nested.join(".git")).unwrap();
        write_skill(&nested.join(".agents/skills/deploy"), "deploy", "# Deploy");

        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![work];
        let result = scan_with_home(&cfg, &home);

        assert_eq!(result.skills.len(), 1);
        assert_eq!(
            result.skills[0].project_root.as_deref(),
            Some(project.as_path())
        );
        assert!(
            result.skills[0]
                .agents
                .iter()
                .all(|placement| placement.root.as_deref() == Some(project.as_path()))
        );
    }

    #[test]
    fn hides_only_project_skills_identical_to_a_global_skill() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        let global = home.join(".agents/skills/shared");
        write_skill(&global, "shared", "# Shared");
        std::fs::create_dir_all(global.join("references")).unwrap();
        std::fs::write(global.join("references/guide.md"), "same").unwrap();

        let work = tmp.path().join("Work");
        let project_skill = work.join("product/.agents/skills/shared");
        write_skill(&project_skill, "shared", "# Shared");
        std::fs::create_dir_all(project_skill.join("references")).unwrap();
        std::fs::write(project_skill.join("references/guide.md"), "same").unwrap();

        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![work.clone()];
        let result = scan_with_home(&cfg, &home);
        assert_eq!(result.skills.len(), 1);
        assert_eq!(result.skills[0].scope, Scope::Global);

        let inspection = scan_with_home_including_global_equivalents(&cfg, &home);
        assert_eq!(inspection.skills.len(), 2);

        std::fs::write(
            project_skill.join("references/guide.md"),
            "project override",
        )
        .unwrap();
        let result = scan_with_home(&cfg, &home);
        assert_eq!(result.skills.len(), 2);
        assert!(
            result
                .skills
                .iter()
                .any(|skill| skill.scope == Scope::Project)
        );
    }

    #[test]
    fn ignored_directory_names_are_skipped() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let root = tmp.path().join("tree");
        write_skill(&root.join("keep/.cursor/skills/ok"), "ok", "# Ok");
        write_skill(&root.join("secret/.cursor/skills/hidden"), "hidden", "# No");
        let mut cfg = AppConfig::default();
        cfg.project_roots.clear();
        cfg.custom_roots = vec![root];
        cfg.ignored_names = vec!["secret".into()];
        let result = scan_with_home(&cfg, &home);
        let names: Vec<_> = result.skills.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["ok"]);
    }

    #[test]
    fn explicitly_selected_vendor_named_root_is_scanned() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let root = tmp.path().join("vendor");
        write_skill(
            &root.join(".agents/skills/explicit"),
            "explicit",
            "# Explicit",
        );

        let mut cfg = AppConfig::default();
        cfg.custom_roots = vec![root];
        let result = scan_with_home(&cfg, &home);

        assert_eq!(
            result
                .skills
                .iter()
                .map(|skill| skill.name.as_str())
                .collect::<Vec<_>>(),
            ["explicit"]
        );
    }

    #[test]
    fn missing_custom_root_is_reported() {
        let tmp = tempdir().unwrap();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let mut cfg = AppConfig::default();
        cfg.project_roots.clear();
        cfg.custom_roots = vec![tmp.path().join("does-not-exist")];
        let result = scan_with_home(&cfg, &home);
        assert!(result.skills.is_empty());
        assert!(
            result
                .errors
                .iter()
                .any(|e| e.contains("scan root missing"))
        );
    }

    #[test]
    fn write_skill_file_roundtrips() {
        let tmp = tempdir().unwrap();
        let path = tmp.path().join("SKILL.md");
        write_skill_file(&path, "---\nname: x\n---\n\n# Hi\n").unwrap();
        assert_eq!(
            read_skill_file(&path).unwrap(),
            "---\nname: x\n---\n\n# Hi\n"
        );
    }

    #[test]
    fn watches_skill_containers_not_the_walk_root() {
        let tmp = tempdir().unwrap();
        let home = tmp.path();
        write_skill(&home.join("app/.cursor/skills/ship"), "ship", "# Ship");
        let mut cfg = AppConfig::default();
        cfg.project_roots = vec![home.to_path_buf()];
        let result = scan_with_home(&cfg, home);
        assert!(!result.watched_dirs.iter().any(|p| p == home));
        assert!(
            result
                .watched_dirs
                .iter()
                .any(|p| p.ends_with(".cursor/skills") || p.ends_with("ship")),
            "{:?}",
            result.watched_dirs
        );
    }

    #[test]
    fn create_skill_writes_frontmatter() {
        let tmp = tempdir().unwrap();
        let dir = create_skill(tmp.path(), "My Skill", "Does a thing").unwrap();
        assert_eq!(dir.file_name().unwrap(), "my-skill");
        let text = read_skill_file(&dir.join("SKILL.md")).unwrap();
        assert!(text.contains("name: my-skill"));
        assert!(text.contains("description: Does a thing"));
        assert!(validate_skill_frontmatter("name: my-skill\ndescription: Does a thing").is_ok());
        assert!(validate_skill_frontmatter("name: x").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn create_skill_in_multiple_folders_uses_one_shared_copy() {
        let tmp = tempdir().unwrap();
        let agents = tmp.path().join(".agents/skills");
        let claude = tmp.path().join(".claude/skills");

        let source = create_skill_in_folders(
            &[agents.clone(), claude.clone()],
            "Shared Notes",
            "Keeps shared notes",
        )
        .unwrap();

        let linked = claude.join("shared-notes");
        assert_eq!(
            source.canonicalize().unwrap(),
            linked.canonicalize().unwrap()
        );
        assert!(
            std::fs::symlink_metadata(linked)
                .unwrap()
                .file_type()
                .is_symlink()
        );
    }

    #[test]
    fn create_skill_in_folders_checks_every_target_before_writing() {
        let tmp = tempdir().unwrap();
        let agents = tmp.path().join(".agents/skills");
        let claude = tmp.path().join(".claude/skills");
        std::fs::create_dir_all(claude.join("shared-notes")).unwrap();

        let error = create_skill_in_folders(
            &[agents.clone(), claude],
            "Shared Notes",
            "Keeps shared notes",
        )
        .unwrap_err();

        assert!(error.to_string().contains("folder already exists"));
        assert!(!agents.join("shared-notes").exists());
    }
}
