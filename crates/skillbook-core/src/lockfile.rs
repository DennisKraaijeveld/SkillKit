use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::model::SkillSource;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LockScope {
    Global,
    Project { root: PathBuf },
}

#[derive(Debug, Clone, Deserialize)]
pub struct SkillLockFile {
    #[serde(default)]
    pub version: u32,
    #[serde(default)]
    pub skills: BTreeMap<String, SkillLockEntry>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillLockEntry {
    pub source: Option<String>,
    pub source_type: Option<String>,
    pub source_url: Option<String>,
    pub skill_path: Option<String>,
    pub skill_folder_hash: Option<String>,
    pub computed_hash: Option<String>,
    pub ref_name: Option<String>,
    #[serde(rename = "ref")]
    pub git_ref: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct LockIndex {
    /// (skill name, scope) → entry. First match wins when looking up by name+scope.
    pub entries: Vec<(String, LockScope, SkillLockEntry)>,
}

impl LockIndex {
    pub fn lookup(
        &self,
        name: &str,
        scope: crate::model::Scope,
        project_root: Option<&Path>,
    ) -> Option<&SkillLockEntry> {
        self.lookup_scoped(name, scope, project_root)
            .map(|(_, entry)| entry)
    }

    pub fn lookup_scoped(
        &self,
        name: &str,
        scope: crate::model::Scope,
        project_root: Option<&Path>,
    ) -> Option<(&LockScope, &SkillLockEntry)> {
        self.entries.iter().find_map(|(n, lock_scope, entry)| {
            if n != name {
                return None;
            }
            match (scope, lock_scope, project_root) {
                (crate::model::Scope::Global, LockScope::Global, _) => Some((lock_scope, entry)),
                (
                    crate::model::Scope::Project | crate::model::Scope::Custom,
                    LockScope::Project { root },
                    Some(project),
                ) if project == root || project.starts_with(root) || root.starts_with(project) => {
                    Some((lock_scope, entry))
                }
                _ => None,
            }
        })
    }

    pub fn lookup_any(&self, name: &str) -> Option<(&LockScope, &SkillLockEntry)> {
        self.entries
            .iter()
            .find(|(n, _, _)| n == name)
            .map(|(_, scope, entry)| (scope, entry))
    }
}

pub fn load_all_locks(home: &Path, project_roots: &[PathBuf]) -> LockIndex {
    let mut index = LockIndex::default();
    let global = home.join(".agents/.skill-lock.json");
    if let Some(file) = read_lock(&global) {
        for (name, entry) in file.skills {
            index.entries.push((name, LockScope::Global, entry));
        }
    }
    let mut roots: Vec<PathBuf> = project_roots.to_vec();
    roots.sort();
    roots.dedup();
    for root in roots {
        for name in [
            "skills-lock.json",
            ".skill-lock.json",
            ".agents/.skill-lock.json",
        ] {
            if let Some(file) = read_lock(&root.join(name)) {
                for (skill, entry) in file.skills {
                    index
                        .entries
                        .push((skill, LockScope::Project { root: root.clone() }, entry));
                }
            }
        }
    }
    index
}

fn read_lock(path: &Path) -> Option<SkillLockFile> {
    let text = std::fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

impl SkillLockEntry {
    pub fn to_source(&self, lock_scope: LockScope) -> SkillSource {
        SkillSource::SkillsCli {
            source: self.source.clone().unwrap_or_else(|| "unknown".into()),
            source_url: self.source_url.clone(),
            source_type: self.source_type.clone().unwrap_or_else(|| "github".into()),
            skill_path: self.skill_path.clone(),
            folder_hash: self
                .skill_folder_hash
                .clone()
                .or_else(|| self.computed_hash.clone()),
            git_ref: self.git_ref.clone().or_else(|| self.ref_name.clone()),
            lock_scope,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn parses_global_lock() {
        let dir = tempdir().unwrap();
        let agents = dir.path().join(".agents");
        std::fs::create_dir_all(&agents).unwrap();
        std::fs::write(
            agents.join(".skill-lock.json"),
            r#"{
              "version": 3,
              "skills": {
                "frontend-design": {
                  "source": "vercel-labs/agent-skills",
                  "sourceType": "github",
                  "sourceUrl": "https://github.com/vercel-labs/agent-skills",
                  "skillPath": "skills/frontend-design/SKILL.md",
                  "skillFolderHash": "abc123"
                }
              }
            }"#,
        )
        .unwrap();
        let index = load_all_locks(dir.path(), &[]);
        let (scope, entry) = index.lookup_any("frontend-design").unwrap();
        assert!(matches!(scope, LockScope::Global));
        assert_eq!(entry.skill_folder_hash.as_deref(), Some("abc123"));
        match entry.to_source(LockScope::Global) {
            SkillSource::SkillsCli {
                git_ref, source, ..
            } => {
                assert_eq!(source, "vercel-labs/agent-skills");
                assert_eq!(git_ref, None);
            }
            other => panic!("expected SkillsCli, got {other:?}"),
        }
    }

    #[test]
    fn scoped_lookup_does_not_leak_global_lock_to_project_skill() {
        let mut index = LockIndex::default();
        index.entries.push((
            "frontend-design".into(),
            LockScope::Global,
            SkillLockEntry {
                source: Some("vercel-labs/agent-skills".into()),
                git_ref: Some("main".into()),
                ..SkillLockEntry::default()
            },
        ));
        assert!(
            index
                .lookup_scoped(
                    "frontend-design",
                    crate::model::Scope::Project,
                    Some(Path::new("/proj")),
                )
                .is_none()
        );
        let (scope, entry) = index
            .lookup_scoped("frontend-design", crate::model::Scope::Global, None)
            .unwrap();
        assert!(matches!(scope, LockScope::Global));
        assert_eq!(entry.git_ref.as_deref(), Some("main"));
        match entry.to_source(LockScope::Global) {
            SkillSource::SkillsCli { git_ref, .. } => {
                assert_eq!(git_ref.as_deref(), Some("main"));
            }
            other => panic!("expected SkillsCli, got {other:?}"),
        }
    }

    #[test]
    fn project_lock_matches_project_root() {
        let root = PathBuf::from("/proj");
        let mut index = LockIndex::default();
        index.entries.push((
            "frontend-design".into(),
            LockScope::Project { root: root.clone() },
            SkillLockEntry {
                source: Some("vercel-labs/agent-skills".into()),
                ..SkillLockEntry::default()
            },
        ));
        assert!(
            index
                .lookup_scoped("frontend-design", crate::model::Scope::Global, None)
                .is_none()
        );
        assert!(
            index
                .lookup_scoped("frontend-design", crate::model::Scope::Project, Some(&root),)
                .is_some()
        );
    }
}
