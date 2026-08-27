use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::config::AppConfig;
use crate::paths::{is_worktree_dir, skip_dir_name};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectCandidate {
    pub name: String,
    pub path: PathBuf,
    pub work_root: PathBuf,
}

pub fn discover_projects(
    config: &AppConfig,
    inferred_project_roots: &[PathBuf],
) -> Vec<ProjectCandidate> {
    let mut candidates = BTreeMap::<PathBuf, PathBuf>::new();

    for configured_root in &config.project_roots {
        if !configured_root.is_dir() {
            continue;
        }

        let work_root = canonical_path(configured_root);
        let Ok(entries) = std::fs::read_dir(&work_root) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if entry.file_type().is_ok_and(|kind| kind.is_dir())
                && !name.starts_with('.')
                && !skip_dir_name(&name)
                && !config.is_ignored_name(&name)
                && !is_worktree_dir(&path)
            {
                candidates.insert(canonical_path(&path), work_root.clone());
            }
        }
    }

    if config.project_roots.is_empty() {
        for inferred in inferred_project_roots {
            if !inferred.is_dir() {
                continue;
            }
            let inferred = canonical_path(inferred);
            candidates
                .entry(inferred.clone())
                .or_insert_with(|| inferred.clone());
        }
    }

    let mut projects: Vec<_> = candidates
        .into_iter()
        .map(|(path, work_root)| ProjectCandidate {
            name: path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .filter(|name| !name.is_empty())
                .unwrap_or_else(|| path.display().to_string()),
            path,
            work_root,
        })
        .collect();
    projects.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then(left.path.cmp(&right.path))
    });
    projects
}

fn canonical_path(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn discovers_only_top_level_folders_below_a_work_folder() {
        let tmp = tempdir().unwrap();
        let work = tmp.path().join("Work");
        let alpha = work.join("alpha");
        let beta = work.join("clients/acme/beta");
        let plain = work.join("plain");
        std::fs::create_dir_all(alpha.join(".git")).unwrap();
        std::fs::create_dir_all(beta.join(".git")).unwrap();
        std::fs::create_dir_all(&plain).unwrap();

        let mut config = AppConfig::default();
        config.project_roots = vec![work.clone()];
        let projects = discover_projects(&config, &[]);

        assert_eq!(
            projects
                .iter()
                .map(|project| project.name.as_str())
                .collect::<Vec<_>>(),
            ["alpha", "clients", "plain"]
        );
        let work = canonical_path(&work);
        assert!(projects.iter().all(|project| project.work_root == work));
    }

    #[test]
    fn does_not_promote_inferred_descendants() {
        let tmp = tempdir().unwrap();
        let work = tmp.path().join("Work");
        let project = work.join("sitenu-crm");
        let worktree = project.join(".claude/worktrees/task");
        std::fs::create_dir_all(worktree.join(".agents/skills/example")).unwrap();

        let mut config = AppConfig::default();
        config.project_roots = vec![work.clone()];
        let projects = discover_projects(&config, std::slice::from_ref(&worktree));

        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].path, canonical_path(&project));
        assert_eq!(projects[0].work_root, canonical_path(&work));
    }

    #[test]
    fn includes_inferred_projects_when_no_work_folder_is_selected() {
        let tmp = tempdir().unwrap();
        let project = tmp.path().join("plain-project");
        std::fs::create_dir_all(project.join(".agents/skills/example")).unwrap();

        let config = AppConfig::default();
        let projects = discover_projects(&config, std::slice::from_ref(&project));

        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].name, "plain-project");
        assert_eq!(projects[0].path, canonical_path(&project));
        assert_eq!(projects[0].work_root, canonical_path(&project));
    }

    #[test]
    fn returns_no_projects_for_an_empty_work_folder() {
        let tmp = tempdir().unwrap();
        let project = tmp.path().join("project");
        std::fs::create_dir_all(&project).unwrap();

        let mut config = AppConfig::default();
        config.project_roots = vec![project.clone()];
        let projects = discover_projects(&config, &[]);

        assert!(projects.is_empty());
    }

    #[test]
    fn skips_dependency_and_ignored_folders() {
        let tmp = tempdir().unwrap();
        let work = tmp.path().join("Work");
        let visible = work.join("visible");
        let dependency = work.join("node_modules/dependency");
        let ignored = work.join("archive/old-project");
        let hidden = work.join(".claude/worktrees/transient");
        std::fs::create_dir_all(visible.join(".git")).unwrap();
        std::fs::create_dir_all(dependency.join(".git")).unwrap();
        std::fs::create_dir_all(ignored.join(".git")).unwrap();
        std::fs::create_dir_all(hidden.join(".git")).unwrap();

        let mut config = AppConfig::default();
        config.project_roots = vec![work];
        config.ignored_names = vec!["archive".into()];
        let projects = discover_projects(&config, &[]);

        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].name, "visible");
    }

    #[test]
    fn skips_linked_worktrees_below_a_work_folder() {
        let tmp = tempdir().unwrap();
        let work = tmp.path().join("Work");
        let project = work.join("project");
        let worktree = work.join("project-task");
        std::fs::create_dir_all(project.join(".git")).unwrap();
        std::fs::create_dir_all(&worktree).unwrap();
        std::fs::write(
            worktree.join(".git"),
            "gitdir: /repo/.git/worktrees/project-task\n",
        )
        .unwrap();

        let mut config = AppConfig::default();
        config.project_roots = vec![work];
        let projects = discover_projects(&config, &[]);

        assert_eq!(projects.len(), 1);
        assert_eq!(projects[0].name, "project");
    }
}
