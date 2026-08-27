use std::path::PathBuf;

use rmcp::{ServiceExt, transport::stdio};
use skillbook_mcp::SkillbookServer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let project_root = parse_project_root(std::env::args_os().skip(1))?;
    SkillbookServer::new(project_root)?
        .serve(stdio())
        .await?
        .waiting()
        .await?;
    Ok(())
}

fn parse_project_root(
    mut arguments: impl Iterator<Item = std::ffi::OsString>,
) -> anyhow::Result<Option<PathBuf>> {
    let mut project_root = None;
    while let Some(argument) = arguments.next() {
        if argument == "--project-root" {
            let value = arguments
                .next()
                .ok_or_else(|| anyhow::anyhow!("--project-root requires a folder path"))?;
            project_root = Some(PathBuf::from(value));
        } else {
            anyhow::bail!("unknown argument: {}", argument.to_string_lossy());
        }
    }
    Ok(project_root)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_optional_project_scope() {
        assert_eq!(parse_project_root(Vec::new().into_iter()).unwrap(), None);
        assert_eq!(
            parse_project_root(vec!["--project-root".into(), "/tmp/project".into()].into_iter())
                .unwrap(),
            Some(PathBuf::from("/tmp/project"))
        );
    }

    #[test]
    fn rejects_unknown_and_incomplete_arguments() {
        assert!(parse_project_root(vec!["--unknown".into()].into_iter()).is_err());
        assert!(parse_project_root(vec!["--project-root".into()].into_iter()).is_err());
    }
}
