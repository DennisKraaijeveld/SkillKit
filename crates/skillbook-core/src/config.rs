use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

pub const CURRENT_ONBOARDING_VERSION: u32 = 1;

/// On-disk settings for SkillKit.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Version of the prerequisite setup flow this installation completed.
    #[serde(default)]
    pub onboarding_version: u32,
    /// Project folders to scan for skill containers (`.claude/skills`, etc.).
    #[serde(default)]
    pub project_roots: Vec<PathBuf>,
    /// Extra roots to scan without treating them as projects.
    #[serde(default)]
    pub custom_roots: Vec<PathBuf>,
    /// Additional directory names to skip during walks.
    #[serde(default)]
    pub ignored_names: Vec<String>,
    /// Appearance: `system`, `light`, or `dark`.
    #[serde(default = "default_appearance")]
    pub appearance: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub git_path: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub npx_path: Option<PathBuf>,
    #[serde(default, skip_serializing)]
    scan_root: Option<PathBuf>,
    #[serde(default, skip_serializing)]
    scan_home: Option<bool>,
}

fn default_appearance() -> String {
    "system".into()
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            onboarding_version: 0,
            project_roots: Vec::new(),
            custom_roots: Vec::new(),
            ignored_names: Vec::new(),
            appearance: default_appearance(),
            git_path: None,
            npx_path: None,
            scan_root: None,
            scan_home: None,
        }
    }
}

impl AppConfig {
    pub fn load() -> anyhow::Result<Self> {
        let path = config_path()?;
        Self::load_from(&path)
    }

    pub fn load_from(path: &Path) -> anyhow::Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }
        let text = std::fs::read_to_string(path)?;
        Self::from_toml(&text)
    }

    pub fn from_toml(text: &str) -> anyhow::Result<Self> {
        let mut cfg: Self = toml::from_str(text)?;
        cfg.apply_legacy();
        Ok(cfg)
    }

    fn apply_legacy(&mut self) {
        if let Some(root) = self.scan_root.take() {
            self.project_roots.push(root);
        } else if self.project_roots.is_empty()
            && self.scan_home == Some(true)
            && let Some(home) = dirs::home_dir()
        {
            self.project_roots.push(home);
        }
        self.project_roots.sort();
        self.project_roots.dedup();
        self.scan_home = None;
    }

    pub fn save(&self) -> anyhow::Result<()> {
        let path = config_path()?;
        self.save_to(&path)
    }

    pub fn save_to(&self, path: &Path) -> anyhow::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let text = toml::to_string_pretty(self)?;
        atomic_write(path, text.as_bytes())?;
        Ok(())
    }

    pub fn is_ignored_name(&self, name: &str) -> bool {
        self.ignored_names.iter().any(|n| n == name)
    }

    pub fn onboarding_complete(&self) -> bool {
        self.onboarding_version >= CURRENT_ONBOARDING_VERSION
    }

    /// Normalized appearance key: `system`, `light`, or `dark`.
    pub fn appearance_mode(&self) -> &str {
        match self.appearance.as_str() {
            "light" | "dark" => self.appearance.as_str(),
            _ => "system",
        }
    }
}

pub fn config_path() -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        let home = dirs::home_dir().ok_or_else(|| anyhow::anyhow!("no home directory"))?;
        Ok(home.join("Library/Application Support/SkillKit/config.toml"))
    }
    #[cfg(not(target_os = "macos"))]
    {
        let dir = dirs::config_dir().ok_or_else(|| anyhow::anyhow!("no config directory"))?;
        Ok(dir.join("skillkit/config.toml"))
    }
}

pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    let tmp = path.with_extension("toml.tmp");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_roundtrip() {
        let cfg = AppConfig::default();
        let text = toml::to_string(&cfg).unwrap();
        let back: AppConfig = toml::from_str(&text).unwrap();
        assert!(back.project_roots.is_empty());
        assert!(back.custom_roots.is_empty());
        assert_eq!(back.onboarding_version, 0);
        assert!(!back.onboarding_complete());
        assert_eq!(back.appearance_mode(), "system");
        assert!(!text.contains("scan_home"));
        assert!(!text.contains("scan_root"));
    }

    #[test]
    fn load_from_supports_missing_and_existing_paths() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("config.toml");

        assert!(
            AppConfig::load_from(&path)
                .unwrap()
                .project_roots
                .is_empty()
        );

        std::fs::write(&path, "appearance = \"dark\"\n").unwrap();
        assert_eq!(AppConfig::load_from(&path).unwrap().appearance, "dark");
    }

    #[test]
    fn onboarding_version_roundtrips_and_old_configs_remain_incomplete() {
        let older = AppConfig::from_toml("appearance = \"dark\"\n").unwrap();
        assert!(!older.onboarding_complete());

        let mut completed = older;
        completed.onboarding_version = CURRENT_ONBOARDING_VERSION;
        let serialized = toml::to_string(&completed).unwrap();
        let restored = AppConfig::from_toml(&serialized).unwrap();

        assert!(restored.onboarding_complete());
        assert!(serialized.contains("onboarding_version = 1"));
    }

    #[test]
    fn command_overrides_roundtrip_without_affecting_older_configs() {
        let older = AppConfig::from_toml("appearance = \"dark\"\n").unwrap();
        assert_eq!(older.git_path, None);
        assert_eq!(older.npx_path, None);

        let configured =
            AppConfig::from_toml("git_path = \"/opt/tools/git\"\nnpx_path = \"/opt/tools/npx\"\n")
                .unwrap();
        assert_eq!(configured.git_path, Some(PathBuf::from("/opt/tools/git")));
        assert_eq!(configured.npx_path, Some(PathBuf::from("/opt/tools/npx")));
        let serialized = toml::to_string(&configured).unwrap();
        assert!(serialized.contains("git_path = \"/opt/tools/git\""));
        assert!(serialized.contains("npx_path = \"/opt/tools/npx\""));
    }

    #[test]
    fn legacy_scan_home_true_becomes_home_dir() {
        let cfg = AppConfig::from_toml("scan_home = true\n").unwrap();
        assert_eq!(
            cfg.project_roots,
            dirs::home_dir().into_iter().collect::<Vec<_>>()
        );
    }

    #[test]
    fn legacy_scan_home_false_stays_unset() {
        let cfg = AppConfig::from_toml("scan_home = false\n").unwrap();
        assert!(cfg.project_roots.is_empty());
    }

    #[test]
    fn scan_root_migrates_once_and_wins_over_legacy_flag() {
        let cfg = AppConfig::from_toml("scan_home = true\nscan_root = \"/tmp/work\"\n").unwrap();
        assert_eq!(cfg.project_roots, [PathBuf::from("/tmp/work")]);
        let text = toml::to_string(&cfg).unwrap();
        assert!(!text.contains("scan_root"));
    }

    #[test]
    fn project_roots_are_deduplicated() {
        let cfg = AppConfig::from_toml(
            "project_roots = [\"/tmp/work\", \"/tmp/work\", \"/tmp/other\"]\n",
        )
        .unwrap();
        assert_eq!(
            cfg.project_roots,
            [PathBuf::from("/tmp/other"), PathBuf::from("/tmp/work")]
        );
    }

    #[test]
    fn legacy_github_token_is_ignored_and_not_serialized() {
        let cfg =
            AppConfig::from_toml("github_token = \"ghp_legacy\"\nappearance = \"dark\"\n").unwrap();
        let text = toml::to_string(&cfg).unwrap();

        assert_eq!(cfg.appearance_mode(), "dark");
        assert!(!text.contains("github_token"));
        assert!(!text.contains("ghp_legacy"));
    }

    #[test]
    fn appearance_mode_normalizes_unknown() {
        let mut cfg = AppConfig {
            appearance: "light".into(),
            ..AppConfig::default()
        };
        assert_eq!(cfg.appearance_mode(), "light");
        cfg.appearance = "DARK".into();
        assert_eq!(cfg.appearance_mode(), "system");
        cfg.appearance = "dark".into();
        assert_eq!(cfg.appearance_mode(), "dark");
    }
}
