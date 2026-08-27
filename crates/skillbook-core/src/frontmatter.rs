use serde::Deserialize;

/// Parsed `SKILL.md` with YAML frontmatter stripped for preview.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedSkillMd {
    pub name: Option<String>,
    pub description: Option<String>,
    pub version: Option<String>,
    pub frontmatter: Option<String>,
    pub body: String,
}

#[derive(Debug, Default, Deserialize)]
struct FrontmatterYaml {
    name: Option<String>,
    description: Option<String>,
    version: Option<String>,
    metadata: Option<FrontmatterMetadata>,
}

#[derive(Debug, Default, Deserialize)]
struct FrontmatterMetadata {
    version: Option<String>,
}

/// Split `---` YAML frontmatter from the markdown body.
pub fn split_frontmatter(contents: &str) -> (Option<&str>, &str) {
    let text = contents.strip_prefix('\u{feff}').unwrap_or(contents);
    let trimmed = text.trim_start_matches(['\r', '\n']);
    if !trimmed.starts_with("---") {
        return (None, text);
    }
    let after = trimmed.strip_prefix("---").unwrap();
    let after = after.strip_prefix('\r').unwrap_or(after);
    let after = after.strip_prefix('\n').unwrap_or(after);
    let Some(end) = after.find("\n---") else {
        return (None, text);
    };
    let yaml = &after[..end];
    let rest = &after[end + 4..];
    let rest = rest.strip_prefix('\r').unwrap_or(rest);
    let rest = rest.strip_prefix('\n').unwrap_or(rest);
    (Some(yaml), rest)
}

pub fn parse_skill_md(contents: &str) -> ParsedSkillMd {
    let (yaml, body) = split_frontmatter(contents);
    let mut name = None;
    let mut description = None;
    let mut version = None;
    if let Some(yaml) = yaml
        && let Ok(fm) = serde_saphyr::from_str::<FrontmatterYaml>(yaml)
    {
        name = fm.name.filter(|s| !s.is_empty());
        description = fm.description.filter(|s| !s.is_empty());
        version = fm
            .version
            .or_else(|| fm.metadata.and_then(|metadata| metadata.version))
            .filter(|s| !s.is_empty());
    }
    ParsedSkillMd {
        name,
        description,
        version,
        frontmatter: yaml.map(str::to_string),
        body: body.to_string(),
    }
}

/// Reconstruct a `SKILL.md` from YAML frontmatter and a markdown body.
///
/// Bezel's document model does not preserve YAML, so the app keeps the
/// frontmatter aside and writes it back on save.
pub fn join_skill_md(frontmatter: Option<&str>, body: &str) -> String {
    match frontmatter.map(str::trim).filter(|s| !s.is_empty()) {
        Some(yaml) => {
            let body = body.trim_start_matches(['\r', '\n']);
            format!("---\n{}\n---\n\n{body}", yaml.trim_end())
        }
        None => body.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_skill() {
        let raw = "---\nname: frontend-design\ndescription: Make interfaces shine.\nversion: 1.2.3\n---\n\n# Frontend Design\n\nDo the work.\n";
        let parsed = parse_skill_md(raw);
        assert_eq!(parsed.name.as_deref(), Some("frontend-design"));
        assert_eq!(parsed.version.as_deref(), Some("1.2.3"));
        assert_eq!(
            parsed.description.as_deref(),
            Some("Make interfaces shine.")
        );
        assert!(parsed.body.contains("# Frontend Design"));
        assert!(!parsed.body.contains("name: frontend-design"));
    }

    #[test]
    fn body_only_without_frontmatter() {
        let parsed = parse_skill_md("# Just a note\n");
        assert_eq!(parsed.name, None);
        assert_eq!(parsed.body, "# Just a note\n");
    }

    #[test]
    fn join_roundtrip_frontmatter() {
        let joined = join_skill_md(Some("name: x\ndescription: y"), "# Hi\n");
        let parsed = parse_skill_md(&joined);
        assert_eq!(parsed.name.as_deref(), Some("x"));
        assert_eq!(parsed.description.as_deref(), Some("y"));
        assert!(parsed.body.contains("# Hi"));
    }

    #[test]
    fn parses_frontmatter_features_used_by_skills() {
        let raw = r#"---
name: "café-tools"
description: >-
  Search and summarize
  multilingual repositories.
version: 2.4.0
metadata:
  owner: platform
  tags: [search, unicode]
---

# Café tools
"#;
        let parsed = parse_skill_md(raw);
        assert_eq!(parsed.name.as_deref(), Some("café-tools"));
        assert_eq!(
            parsed.description.as_deref(),
            Some("Search and summarize multilingual repositories.")
        );
        assert_eq!(parsed.version.as_deref(), Some("2.4.0"));
        assert_eq!(
            parsed.frontmatter.as_deref(),
            Some(
                "name: \"café-tools\"\ndescription: >-\n  Search and summarize\n  multilingual repositories.\nversion: 2.4.0\nmetadata:\n  owner: platform\n  tags: [search, unicode]"
            )
        );
    }

    #[test]
    fn parses_version_from_skill_metadata() {
        let parsed = parse_skill_md(
            "---\nname: portable-text\ndescription: Render content\nmetadata:\n  version: \"1.4.0\"\n---\n",
        );
        assert_eq!(parsed.version.as_deref(), Some("1.4.0"));
    }

    #[test]
    fn rejects_ambiguous_duplicate_required_keys() {
        let parsed =
            parse_skill_md("---\nname: first\nname: second\ndescription: Duplicate key\n---\n");
        assert_eq!(parsed.name, None);
        assert_eq!(parsed.description, None);
    }

    #[test]
    fn preserves_crlf_frontmatter_and_body_content() {
        let raw =
            "\u{feff}\r\n---\r\nname: windows\r\ndescription: CRLF input\r\n---\r\n\r\n# Body\r\n";
        let parsed = parse_skill_md(raw);
        assert_eq!(parsed.name.as_deref(), Some("windows"));
        assert_eq!(parsed.description.as_deref(), Some("CRLF input"));
        assert_eq!(parsed.body, "\r\n# Body\r\n");
    }
}
