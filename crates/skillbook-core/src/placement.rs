use std::path::{Path, PathBuf};

use crate::{Skill, UpdateOutcome};

pub fn link_skill_to_project(
    skill: &Skill,
    project_root: &Path,
    agents: &[String],
) -> UpdateOutcome {
    match link_skill_to_project_inner(skill, project_root, agents) {
        Ok(message) => UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: true,
            message,
        },
        Err(message) => UpdateOutcome {
            skill_id: skill.id.clone(),
            name: skill.name.clone(),
            ok: false,
            message,
        },
    }
}

fn link_skill_to_project_inner(
    skill: &Skill,
    project_root: &Path,
    agents: &[String],
) -> Result<String, String> {
    if !project_root.is_dir() {
        return Err("Project folder does not exist".into());
    }
    if agents.is_empty() {
        return Err("Choose at least one skill folder".into());
    }

    let source = std::fs::canonicalize(&skill.canonical_dir)
        .map_err(|error| format!("Source skill is unavailable: {error}"))?;
    let folder_name = source
        .file_name()
        .filter(|name| !name.is_empty())
        .ok_or_else(|| "Source skill has no folder name".to_string())?;

    let mut targets = Vec::new();
    for agent in agents {
        let relative =
            project_container(agent).ok_or_else(|| format!("Unsupported skill folder: {agent}"))?;
        let target = project_root.join(relative).join(folder_name);
        if targets.contains(&target) {
            continue;
        }
        targets.push(target);
    }

    let mut already_linked = 0usize;
    for target in &targets {
        if std::fs::symlink_metadata(target).is_ok() {
            if target
                .canonicalize()
                .is_ok_and(|canonical| canonical == source)
            {
                already_linked += 1;
                continue;
            }
            return Err(format!(
                "A different skill already exists at {}",
                target.display()
            ));
        }
    }

    let mut created: Vec<PathBuf> = Vec::new();
    for target in &targets {
        if target
            .canonicalize()
            .is_ok_and(|canonical| canonical == source)
        {
            continue;
        }
        let parent = target
            .parent()
            .ok_or_else(|| "Target skill folder is invalid".to_string())?;
        if let Err(error) = std::fs::create_dir_all(parent) {
            rollback_links(&created);
            return Err(format!("Could not create {}: {error}", parent.display()));
        }
        if let Err(error) = create_symlink(&source, target) {
            rollback_links(&created);
            return Err(format!("Could not link {}: {error}", target.display()));
        }
        created.push(target.clone());
    }

    let count = created.len();
    if count == 0 && already_linked > 0 {
        return Ok(format!("{} is already linked to this project", skill.name));
    }
    let destination = if count == 1 { "folder" } else { "folders" };
    Ok(format!(
        "Linked {} to {count} project skill {destination}",
        skill.name
    ))
}

fn project_container(agent: &str) -> Option<&'static str> {
    match agent {
        "agents" => Some(".agents/skills"),
        "claude" => Some(".claude/skills"),
        "cursor" => Some(".cursor/skills"),
        "codex" | "openai" => Some(".codex/skills"),
        "opencode" => Some(".opencode/skills"),
        "gemini" => Some(".gemini/skills"),
        "windsurf" => Some(".windsurf/skills"),
        "copilot" | "github" => Some(".github/skills"),
        _ => None,
    }
}

fn rollback_links(paths: &[PathBuf]) {
    for path in paths {
        let _ = std::fs::remove_file(path);
    }
}

#[cfg(unix)]
fn create_symlink(source: &Path, target: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(source, target)
}

#[cfg(windows)]
fn create_symlink(source: &Path, target: &Path) -> std::io::Result<()> {
    std::os::windows::fs::symlink_dir(source, target)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Scope, VersionStatus, test_skill};
    use tempfile::tempdir;

    fn fixture_skill(root: &Path) -> Skill {
        let source = root.join("source/shared");
        std::fs::create_dir_all(&source).unwrap();
        std::fs::write(
            source.join("SKILL.md"),
            "---\nname: shared\ndescription: shared skill\n---\n",
        )
        .unwrap();
        let mut skill = test_skill("shared", "shared", Scope::Global, VersionStatus::Untracked);
        skill.id = source.display().to_string();
        skill.canonical_dir = source.clone();
        skill.skill_md = source.join("SKILL.md");
        skill
    }

    #[test]
    fn links_one_canonical_skill_into_multiple_project_folders() {
        let tmp = tempdir().unwrap();
        let project = tmp.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        let skill = fixture_skill(tmp.path());

        let result = link_skill_to_project(&skill, &project, &["claude".into(), "codex".into()]);

        assert!(result.ok, "{}", result.message);
        assert_eq!(
            project
                .join(".claude/skills/shared")
                .canonicalize()
                .unwrap(),
            skill.canonical_dir.canonicalize().unwrap()
        );
        assert_eq!(
            project.join(".codex/skills/shared").canonicalize().unwrap(),
            skill.canonical_dir.canonicalize().unwrap()
        );
    }

    #[test]
    fn refuses_to_replace_an_independent_copy() {
        let tmp = tempdir().unwrap();
        let project = tmp.path().join("project");
        std::fs::create_dir_all(project.join(".agents/skills/shared")).unwrap();
        let skill = fixture_skill(tmp.path());

        let result = link_skill_to_project(&skill, &project, &["agents".into()]);

        assert!(!result.ok);
        assert!(result.message.contains("different skill already exists"));
    }

    #[test]
    fn linking_twice_is_idempotent() {
        let tmp = tempdir().unwrap();
        let project = tmp.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        let skill = fixture_skill(tmp.path());

        assert!(link_skill_to_project(&skill, &project, &["agents".into()]).ok);
        let second = link_skill_to_project(&skill, &project, &["agents".into()]);

        assert!(second.ok);
        assert!(second.message.contains("already linked"));
    }
}
