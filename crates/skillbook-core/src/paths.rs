use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HarnessSkillDir {
    pub path: PathBuf,
    pub exists: bool,
    pub skill_count: usize,
    pub unique_skill_count: usize,
    pub source_skill_count: usize,
    pub linked_skill_count: usize,
    pub broken_link_count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentHarness {
    pub agent: String,
    pub detected: bool,
    pub skill_dirs: Vec<HarnessSkillDir>,
    pub unique_skill_count: usize,
    pub source_skill_count: usize,
    pub linked_skill_count: usize,
    pub placement_count: usize,
    pub broken_link_count: usize,
    pub detected_via_app: bool,
    pub detected_via_config: bool,
    pub detected_via_skill_directory: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HarnessDetectionSummary {
    pub harnesses: Vec<AgentHarness>,
    pub unique_skill_count: usize,
    pub placement_count: usize,
    pub linked_placement_count: usize,
    pub broken_link_count: usize,
}

struct AgentHarnessSpec {
    agent: &'static str,
    skill_dirs: &'static [&'static str],
    detection_paths: &'static [&'static str],
    app_names: &'static [&'static str],
}

const AGENT_HARNESSES: &[AgentHarnessSpec] = &[
    AgentHarnessSpec {
        agent: "agents",
        skill_dirs: &[".agents/skills", ".config/agents/skills"],
        detection_paths: &[".agents", ".config/agents"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "claude",
        skill_dirs: &[".claude/skills"],
        detection_paths: &[".claude"],
        app_names: &["Claude.app"],
    },
    AgentHarnessSpec {
        agent: "cursor",
        skill_dirs: &[".cursor/skills"],
        detection_paths: &[".cursor"],
        app_names: &["Cursor.app"],
    },
    AgentHarnessSpec {
        agent: "codex",
        skill_dirs: &[".codex/skills"],
        detection_paths: &[".codex"],
        app_names: &["Codex.app"],
    },
    AgentHarnessSpec {
        agent: "opencode",
        skill_dirs: &[".opencode/skills", ".config/opencode/skills"],
        detection_paths: &[".opencode", ".config/opencode"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "openai",
        skill_dirs: &[".openai/skills"],
        detection_paths: &[".openai"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "gemini",
        skill_dirs: &[".gemini/skills"],
        detection_paths: &[".gemini"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "windsurf",
        skill_dirs: &[".codeium/windsurf/skills"],
        detection_paths: &[".codeium/windsurf"],
        app_names: &["Windsurf.app"],
    },
    AgentHarnessSpec {
        agent: "copilot",
        skill_dirs: &[".copilot/skills"],
        detection_paths: &[".copilot"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "openclaw",
        skill_dirs: &[".openclaw/skills"],
        detection_paths: &[".openclaw"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "crush",
        skill_dirs: &[".crush/skills", ".config/crush/skills"],
        detection_paths: &[".crush", ".config/crush"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "devin",
        skill_dirs: &[".config/devin/skills"],
        detection_paths: &[".config/devin"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "goose",
        skill_dirs: &[".goose/skills", ".config/goose/skills"],
        detection_paths: &[".goose", ".config/goose"],
        app_names: &[],
    },
    AgentHarnessSpec {
        agent: "kimchi",
        skill_dirs: &[".config/kimchi/harness/skills"],
        detection_paths: &[".config/kimchi"],
        app_names: &[],
    },
];

/// Directory names that typically hold `skills/` (with or without a leading dot).
pub const AGENT_DIR_NAMES: &[&str] = &[
    ".claude",
    ".cursor",
    ".agents",
    ".codex",
    ".opencode",
    ".openai",
    ".gemini",
    ".windsurf",
    ".factory",
    ".continue",
    ".kilocode",
    ".crush",
    ".goose",
    ".roo",
    ".codeium",
    ".github",
    ".pi",
    ".qwen",
    ".grok",
    ".openclaw",
    ".copilot",
];

/// Relative project containers looked up from a repo / walk root.
pub const PROJECT_CONTAINERS: &[&str] = &[
    ".claude/skills",
    ".cursor/skills",
    ".agents/skills",
    ".codex/skills",
    ".opencode/skills",
    ".openai/skills",
    ".gemini/skills",
    ".windsurf/skills",
    ".factory/skills",
    ".continue/skills",
    ".kilocode/skills",
    ".crush/skills",
    ".goose/skills",
    ".roo/skills",
    ".github/skills",
    ".pi/skills",
];

const SKIP_DIR_NAMES: &[&str] = &[
    "node_modules",
    "bower_components",
    "jspm_packages",
    "vendor",
    "third_party",
    ".git",
    "Library",
    "Pictures",
    "Movies",
    "Music",
    "Photos",
    "Applications",
    ".Trash",
    ".npm",
    ".pnpm-store",
    ".yarn",
    ".cargo",
    ".rustup",
    ".cache",
    ".bundle",
    ".gradle",
    ".m2",
    ".venv",
    "venv",
    "__pycache__",
    "site-packages",
    ".tox",
    ".nox",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".hypothesis",
    "target",
    "dist",
    "build",
    "out",
    ".build",
    "DerivedData",
    ".next",
    ".nuxt",
    ".output",
    ".svelte-kit",
    ".turbo",
    ".parcel-cache",
    ".vite",
    "coverage",
    "Pods",
    "Carthage",
    ".local",
    "go",
    "Android",
    "Caches",
    ".Spotlight-V100",
    ".fseventsd",
];

pub fn skip_dir_name(name: &str) -> bool {
    SKIP_DIR_NAMES.contains(&name)
}

pub fn is_worktree_dir(path: &Path) -> bool {
    if has_managed_worktree_components(path) {
        return true;
    }

    let marker = path.join(".git");
    if !marker.is_file() {
        return false;
    }
    let Ok(contents) = std::fs::read_to_string(marker) else {
        return false;
    };
    let Some(git_dir) = contents
        .lines()
        .next()
        .and_then(|line| line.trim().strip_prefix("gitdir:"))
    else {
        return false;
    };
    let normalized = git_dir.trim().replace('\\', "/");
    let parts = normalized
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    parts
        .windows(2)
        .any(|parts| parts[0] == ".git" && parts[1] == "worktrees")
}

pub fn is_within_worktree(root: &Path, path: &Path) -> bool {
    if has_managed_worktree_components(path) {
        return true;
    }

    let mut current = path.parent();
    while let Some(directory) = current {
        if is_worktree_dir(directory) {
            return true;
        }
        if directory == root {
            break;
        }
        if !directory.starts_with(root) {
            break;
        }
        current = directory.parent();
    }
    false
}

fn has_managed_worktree_components(path: &Path) -> bool {
    let mut previous = None::<String>;
    for component in path.components() {
        let current = component.as_os_str().to_string_lossy();
        if current == "worktrees"
            && previous
                .as_deref()
                .is_some_and(|name| matches!(name, ".claude" | ".codex" | ".factory"))
        {
            return true;
        }
        previous = Some(current.into_owned());
    }
    false
}

pub fn is_agent_dir_name(name: &str) -> bool {
    AGENT_DIR_NAMES.contains(&name)
}

pub fn is_project_container(path: &Path) -> bool {
    project_container_names().any(|c| path.ends_with(c))
}

pub fn project_container_names() -> impl Iterator<Item = &'static str> {
    PROJECT_CONTAINERS.iter().copied()
}

/// Well-known global skill directories for this user.
pub fn global_skill_dirs(home: &Path) -> Vec<(String, PathBuf)> {
    well_known_global_skill_dirs(home)
        .into_iter()
        .filter(|(_, _, exists)| *exists)
        .map(|(agent, path, _)| (agent, path))
        .collect()
}

/// Well-known global skill folders, including paths that do not exist yet.
pub fn well_known_global_skill_dirs(home: &Path) -> Vec<(String, PathBuf, bool)> {
    AGENT_HARNESSES
        .iter()
        .flat_map(|harness| {
            harness.skill_dirs.iter().map(move |relative| {
                let path = home.join(relative);
                let exists = path.is_dir();
                (harness.agent.to_string(), path, exists)
            })
        })
        .collect()
}

pub fn detect_agent_harnesses(home: &Path) -> Vec<AgentHarness> {
    detect_agent_harness_summary(home).harnesses
}

pub fn detect_agent_harness_summary(home: &Path) -> HarnessDetectionSummary {
    let mut canonical_skills = HashSet::new();
    let mut placement_count = 0;
    let mut linked_placement_count = 0;
    let mut broken_link_count = 0;
    let harnesses = AGENT_HARNESSES
        .iter()
        .map(|spec| {
            let mut harness_canonical_skills = HashSet::new();
            let mut source_skills = HashSet::new();
            let mut linked_skills = HashSet::new();
            let mut harness_placement_count = 0;
            let mut harness_broken_link_count = 0;
            let skill_dirs: Vec<_> = spec
                .skill_dirs
                .iter()
                .map(|relative| {
                    let path = home.join(relative);
                    let exists = path.is_dir();
                    let discovered = discover_skills(&path);
                    for skill in &discovered.skills {
                        canonical_skills.insert(skill.canonical_dir.clone());
                        harness_canonical_skills.insert(skill.canonical_dir.clone());
                        if skill.is_symlink {
                            linked_skills.insert(skill.canonical_dir.clone());
                        } else {
                            source_skills.insert(skill.canonical_dir.clone());
                        }
                    }
                    let directory_placement_count = discovered.skills.len();
                    let directory_unique_count = discovered
                        .skills
                        .iter()
                        .map(|skill| &skill.canonical_dir)
                        .collect::<HashSet<_>>()
                        .len();
                    let directory_source_count = discovered
                        .skills
                        .iter()
                        .filter(|skill| !skill.is_symlink)
                        .map(|skill| &skill.canonical_dir)
                        .collect::<HashSet<_>>()
                        .len();
                    let directory_linked_skill_count = discovered
                        .skills
                        .iter()
                        .filter(|skill| skill.is_symlink)
                        .map(|skill| &skill.canonical_dir)
                        .collect::<HashSet<_>>()
                        .len();
                    let directory_linked_count = discovered
                        .skills
                        .iter()
                        .filter(|skill| skill.is_symlink)
                        .count();
                    placement_count += directory_placement_count;
                    linked_placement_count += directory_linked_count;
                    broken_link_count += discovered.broken_link_count;
                    harness_placement_count += directory_placement_count;
                    harness_broken_link_count += discovered.broken_link_count;
                    HarnessSkillDir {
                        skill_count: directory_placement_count,
                        unique_skill_count: directory_unique_count,
                        source_skill_count: directory_source_count,
                        linked_skill_count: directory_linked_skill_count,
                        broken_link_count: discovered.broken_link_count,
                        path,
                        exists,
                    }
                })
                .collect();
            let detected_via_skill_directory = skill_dirs.iter().any(|directory| directory.exists);
            let detected_via_config = spec
                .detection_paths
                .iter()
                .any(|relative| home.join(relative).exists());
            let detected_via_app = spec.app_names.iter().any(|name| {
                Path::new("/Applications").join(name).exists()
                    || home.join("Applications").join(name).exists()
            });
            AgentHarness {
                agent: spec.agent.to_string(),
                detected: detected_via_skill_directory || detected_via_config || detected_via_app,
                skill_dirs,
                unique_skill_count: harness_canonical_skills.len(),
                source_skill_count: source_skills.len(),
                linked_skill_count: linked_skills.len(),
                placement_count: harness_placement_count,
                broken_link_count: harness_broken_link_count,
                detected_via_app,
                detected_via_config,
                detected_via_skill_directory,
            }
        })
        .collect();
    HarnessDetectionSummary {
        harnesses,
        unique_skill_count: canonical_skills.len(),
        placement_count,
        linked_placement_count,
        broken_link_count,
    }
}

struct DiscoveredSkill {
    canonical_dir: PathBuf,
    is_symlink: bool,
}

#[derive(Default)]
struct DiscoveredSkills {
    skills: Vec<DiscoveredSkill>,
    broken_link_count: usize,
}

fn discover_skills(path: &Path) -> DiscoveredSkills {
    let root_is_symlink =
        std::fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_symlink());
    if root_is_symlink && !path.exists() {
        return DiscoveredSkills {
            skills: Vec::new(),
            broken_link_count: 1,
        };
    }
    let Ok(entries) = std::fs::read_dir(path) else {
        return DiscoveredSkills::default();
    };
    let mut discovered = DiscoveredSkills::default();
    for entry in entries.flatten() {
        let entry_path = entry.path();
        let entry_is_symlink = entry
            .file_type()
            .is_ok_and(|file_type| file_type.is_symlink());
        if entry_is_symlink && !entry_path.exists() {
            discovered.broken_link_count += 1;
            continue;
        }
        let skill_dir = if entry_path.is_dir() {
            entry_path
        } else if entry_path
            .file_name()
            .is_some_and(|name| name == "SKILL.md")
        {
            path.to_path_buf()
        } else {
            continue;
        };
        if !skill_dir.join("SKILL.md").is_file() {
            continue;
        }
        discovered.skills.push(DiscoveredSkill {
            canonical_dir: std::fs::canonicalize(&skill_dir).unwrap_or(skill_dir),
            is_symlink: root_is_symlink || entry_is_symlink,
        });
    }
    discovered
}

/// Infer a short agent label from a filesystem path.
pub fn agent_from_path(path: &Path) -> String {
    let s = path.to_string_lossy();
    let checks = [
        ("/.claude/", "claude"),
        ("/.cursor/", "cursor"),
        ("/.codex/", "codex"),
        ("/.opencode/", "opencode"),
        ("/opencode/skills", "opencode"),
        ("/.openai/", "openai"),
        ("/.gemini/", "gemini"),
        ("/windsurf/skills", "windsurf"),
        ("/.factory/", "factory"),
        ("/.continue/", "continue"),
        ("/crush/skills", "crush"),
        ("/devin/skills", "devin"),
        ("/goose/skills", "goose"),
        ("/kimchi/harness/skills", "kimchi"),
        ("/.agents/", "agents"),
        ("/agents/skills", "agents"),
        ("/.copilot/", "copilot"),
        ("/.openclaw/", "openclaw"),
        ("/.github/", "github"),
    ];
    for (needle, label) in checks {
        if s.contains(needle) {
            return label.to_string();
        }
    }
    "local".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_managed_and_git_linked_worktrees() {
        let tmp = tempfile::tempdir().unwrap();
        let managed = tmp.path().join("repo/.claude/worktrees/task");
        std::fs::create_dir_all(&managed).unwrap();
        assert!(is_worktree_dir(&managed));

        let linked = tmp.path().join("linked");
        std::fs::create_dir_all(&linked).unwrap();
        std::fs::write(
            linked.join(".git"),
            "gitdir: /stale/checkout/.git/worktrees/linked\n",
        )
        .unwrap();
        assert!(is_worktree_dir(&linked));
        assert!(is_within_worktree(
            tmp.path(),
            &linked.join(".agents/skills/demo/SKILL.md")
        ));

        let main = tmp.path().join("main");
        std::fs::create_dir_all(main.join(".git")).unwrap();
        assert!(!is_worktree_dir(&main));
    }

    #[test]
    fn labels_common_paths() {
        assert_eq!(
            agent_from_path(Path::new("/Users/a/.claude/skills/foo/SKILL.md")),
            "claude"
        );
        assert_eq!(
            agent_from_path(Path::new("/home/a/.config/opencode/skills/x")),
            "opencode"
        );
        assert_eq!(
            agent_from_path(Path::new("/repo/.cursor/skills/bar")),
            "cursor"
        );
    }

    #[test]
    fn skips_common_dependency_cache_and_generated_directories() {
        for name in [
            "node_modules",
            "bower_components",
            "vendor",
            "third_party",
            ".pnpm-store",
            ".yarn",
            ".venv",
            "venv",
            "__pycache__",
            "site-packages",
            "target",
            "dist",
            "build",
            "out",
            ".next",
            ".nuxt",
            ".svelte-kit",
            ".turbo",
            "coverage",
            "Pods",
            "Carthage",
            "DerivedData",
        ] {
            assert!(skip_dir_name(name), "expected {name} to be skipped");
        }

        for name in ["packages", "Sources", "skills", ".agents", ".claude"] {
            assert!(!skip_dir_name(name), "expected {name} to remain scannable");
        }
    }

    #[test]
    fn well_known_lists_missing_and_existing_dirs() {
        let tmp = tempfile::tempdir().unwrap();
        let missing = well_known_global_skill_dirs(tmp.path());
        assert!(
            missing
                .iter()
                .any(|(agent, _, exists)| agent == "cursor" && !*exists)
        );
        std::fs::create_dir_all(tmp.path().join(".cursor/skills")).unwrap();
        let found = well_known_global_skill_dirs(tmp.path());
        assert!(found.iter().any(|(agent, path, exists)| {
            agent == "cursor" && *exists && path.ends_with(".cursor/skills")
        }));
    }

    #[test]
    fn detects_harness_separately_from_its_skill_directory() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(".cursor")).unwrap();
        let detected = detect_agent_harnesses(tmp.path());
        let cursor = detected
            .iter()
            .find(|harness| harness.agent == "cursor")
            .unwrap();

        assert!(cursor.detected);
        assert!(cursor.detected_via_config);
        assert!(!cursor.detected_via_skill_directory);
        assert_eq!(cursor.skill_dirs.len(), 1);
        assert!(!cursor.skill_dirs[0].exists);
        assert_eq!(cursor.skill_dirs[0].skill_count, 0);
    }

    #[test]
    fn counts_skills_in_all_registered_global_directories() {
        let tmp = tempfile::tempdir().unwrap();
        let skill = tmp.path().join(".config/opencode/skills/release");
        std::fs::create_dir_all(&skill).unwrap();
        std::fs::write(skill.join("SKILL.md"), "---\nname: release\n---\n").unwrap();

        let detected = detect_agent_harnesses(tmp.path());
        let opencode = detected
            .iter()
            .find(|harness| harness.agent == "opencode")
            .unwrap();

        assert!(opencode.detected);
        assert_eq!(
            opencode
                .skill_dirs
                .iter()
                .map(|dir| dir.skill_count)
                .sum::<usize>(),
            1
        );
        assert!(
            global_skill_dirs(tmp.path())
                .iter()
                .any(|(agent, path)| agent == "opencode"
                    && path.ends_with(".config/opencode/skills"))
        );
    }

    #[cfg(unix)]
    #[test]
    fn summarizes_unique_skills_linked_placements_and_config_harnesses() {
        let tmp = tempfile::tempdir().unwrap();
        let shared = tmp.path().join(".agents/skills/shared");
        let agents_only = tmp.path().join(".agents/skills/agents-only");
        let codex_only = tmp.path().join(".codex/skills/codex-only");
        for skill in [&shared, &agents_only, &codex_only] {
            std::fs::create_dir_all(skill).unwrap();
            std::fs::write(skill.join("SKILL.md"), "---\nname: test\n---\n").unwrap();
        }

        let claude = tmp.path().join(".claude/skills");
        let crush = tmp.path().join(".config/crush/skills");
        std::fs::create_dir_all(&claude).unwrap();
        std::fs::create_dir_all(&crush).unwrap();
        std::os::unix::fs::symlink(&shared, claude.join("shared")).unwrap();
        std::os::unix::fs::symlink(&shared, crush.join("shared")).unwrap();
        std::os::unix::fs::symlink(tmp.path().join("missing"), crush.join("broken")).unwrap();

        let summary = detect_agent_harness_summary(tmp.path());
        assert_eq!(summary.unique_skill_count, 3);
        assert_eq!(summary.placement_count, 5);
        assert_eq!(summary.linked_placement_count, 2);
        assert_eq!(summary.broken_link_count, 1);

        let agents = summary
            .harnesses
            .iter()
            .find(|harness| harness.agent == "agents")
            .unwrap();
        assert_eq!(agents.unique_skill_count, 2);
        assert_eq!(agents.source_skill_count, 2);
        assert_eq!(agents.linked_skill_count, 0);

        let crush = summary
            .harnesses
            .iter()
            .find(|harness| harness.agent == "crush")
            .unwrap();
        assert!(crush.detected);
        assert!(crush.detected_via_config);
        assert!(crush.detected_via_skill_directory);
        assert_eq!(crush.unique_skill_count, 1);
        assert_eq!(crush.source_skill_count, 0);
        assert_eq!(crush.linked_skill_count, 1);
        assert_eq!(crush.broken_link_count, 1);
    }

    #[cfg(unix)]
    #[test]
    fn reports_a_broken_skill_directory_link() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(".gemini")).unwrap();
        std::os::unix::fs::symlink(
            tmp.path().join("missing-skills"),
            tmp.path().join(".gemini/skills"),
        )
        .unwrap();

        let summary = detect_agent_harness_summary(tmp.path());
        let gemini = summary
            .harnesses
            .iter()
            .find(|harness| harness.agent == "gemini")
            .unwrap();
        assert!(gemini.detected);
        assert!(!gemini.detected_via_skill_directory);
        assert_eq!(gemini.broken_link_count, 1);
        assert_eq!(summary.broken_link_count, 1);
    }
}
