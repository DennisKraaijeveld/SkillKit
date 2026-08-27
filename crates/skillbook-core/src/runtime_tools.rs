use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeTool {
    Git,
    Npx,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeToolState {
    Available,
    Missing,
    Invalid,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeToolStatus {
    pub tool: RuntimeTool,
    pub state: RuntimeToolState,
    pub path: Option<PathBuf>,
    pub version: Option<String>,
    pub issue: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeStatus {
    pub git: RuntimeToolStatus,
    pub npx: RuntimeToolStatus,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RuntimeOverrides {
    pub git: Option<PathBuf>,
    pub npx: Option<PathBuf>,
}

#[derive(Debug, Clone, Default)]
pub struct ToolRequest {
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
    pub remove_env: Vec<OsString>,
}

#[derive(Debug)]
pub enum ToolFailure {
    Unavailable(RuntimeTool),
    WorkingDirectoryMissing(PathBuf),
    PermissionDenied(PathBuf),
    Cancelled(RuntimeTool),
    TimedOut(RuntimeTool),
    SpawnFailed(String),
}

impl fmt::Display for ToolFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unavailable(RuntimeTool::Npx) => formatter.write_str(
                "npx is required to install skills. Choose its location or install Node.js, then check again.",
            ),
            Self::Unavailable(RuntimeTool::Git) => {
                formatter.write_str("Git is not available. Choose its location, then check again.")
            }
            Self::WorkingDirectoryMissing(_) => formatter
                .write_str("Project folder no longer exists. Choose another project."),
            Self::PermissionDenied(path) => {
                write!(formatter, "Permission denied while starting {}", path.display())
            }
            Self::Cancelled(RuntimeTool::Git) => formatter.write_str("Git command cancelled."),
            Self::Cancelled(RuntimeTool::Npx) => formatter.write_str("npx command cancelled."),
            Self::TimedOut(RuntimeTool::Git) => formatter.write_str("Git remote check timed out."),
            Self::TimedOut(RuntimeTool::Npx) => formatter.write_str("npx command timed out."),
            Self::SpawnFailed(message) => formatter.write_str(message),
        }
    }
}

impl std::error::Error for ToolFailure {}

#[derive(Debug, Clone)]
pub struct RuntimeContext {
    home: PathBuf,
    path: Option<OsString>,
    variables: BTreeMap<String, OsString>,
}

impl RuntimeContext {
    pub fn new(
        home: impl Into<PathBuf>,
        path: Option<OsString>,
        variables: BTreeMap<String, OsString>,
    ) -> Self {
        Self {
            home: home.into(),
            path,
            variables,
        }
    }
}

#[derive(Debug, Clone)]
pub struct RuntimeTools {
    context: RuntimeContext,
    overrides: RuntimeOverrides,
    status: RuntimeStatus,
}

impl RuntimeTools {
    pub fn current(overrides: RuntimeOverrides) -> Self {
        let home = dirs::home_dir().unwrap_or_default();
        let variables = std::env::vars_os()
            .filter_map(|(key, value)| key.into_string().ok().map(|key| (key, value)))
            .collect();
        Self::discover(
            RuntimeContext::new(home, std::env::var_os("PATH"), variables),
            overrides,
        )
    }

    pub fn discover(context: RuntimeContext, overrides: RuntimeOverrides) -> Self {
        let git = discover_tool(RuntimeTool::Git, &context, overrides.git.as_deref());
        let npx = discover_tool(RuntimeTool::Npx, &context, overrides.npx.as_deref());
        Self {
            context,
            overrides,
            status: RuntimeStatus { git, npx },
        }
    }

    pub fn status(&self) -> &RuntimeStatus {
        &self.status
    }

    pub fn refresh(&mut self) {
        self.status = RuntimeStatus {
            git: discover_tool(
                RuntimeTool::Git,
                &self.context,
                self.overrides.git.as_deref(),
            ),
            npx: discover_tool(
                RuntimeTool::Npx,
                &self.context,
                self.overrides.npx.as_deref(),
            ),
        };
    }

    pub fn execute(&self, tool: RuntimeTool, request: ToolRequest) -> Result<Output, ToolFailure> {
        let (mut command, path) = self.command(tool, request)?;
        command
            .output()
            .map_err(|error| spawn_failure(tool, path, error))
    }

    pub fn execute_interruptible(
        &self,
        tool: RuntimeTool,
        request: ToolRequest,
        timeout: Duration,
        mut should_continue: impl FnMut() -> bool,
    ) -> Result<Output, ToolFailure> {
        let (mut command, path) = self.command(tool, request)?;
        command
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = command
            .spawn()
            .map_err(|error| spawn_failure(tool, path.clone(), error))?;
        let started = Instant::now();
        loop {
            match child.try_wait() {
                Ok(Some(_)) => {
                    return child
                        .wait_with_output()
                        .map_err(|error| ToolFailure::SpawnFailed(error.to_string()));
                }
                Ok(None) if !should_continue() => {
                    stop_child(&mut child);
                    return Err(ToolFailure::Cancelled(tool));
                }
                Ok(None) if started.elapsed() >= timeout => {
                    stop_child(&mut child);
                    return Err(ToolFailure::TimedOut(tool));
                }
                Ok(None) => thread::sleep(Duration::from_millis(25)),
                Err(error) => {
                    stop_child(&mut child);
                    return Err(ToolFailure::SpawnFailed(error.to_string()));
                }
            }
        }
    }

    fn command(
        &self,
        tool: RuntimeTool,
        request: ToolRequest,
    ) -> Result<(Command, PathBuf), ToolFailure> {
        if let Some(cwd) = &request.cwd
            && !cwd.is_dir()
        {
            return Err(ToolFailure::WorkingDirectoryMissing(cwd.clone()));
        }

        let status = match tool {
            RuntimeTool::Git => &self.status.git,
            RuntimeTool::Npx => &self.status.npx,
        };
        let path = status
            .path
            .as_deref()
            .filter(|path| status.state == RuntimeToolState::Available && is_executable(path))
            .ok_or(ToolFailure::Unavailable(tool))?;

        let mut command = Command::new(path);
        command.args(request.args);
        if let Some(cwd) = request.cwd {
            command.current_dir(cwd);
        }
        for (key, value) in request.env {
            command.env(key, value);
        }
        for key in request.remove_env {
            command.env_remove(key);
        }
        if tool == RuntimeTool::Npx {
            command.env_remove("GITHUB_TOKEN").env_remove("GH_TOKEN");
        }
        apply_path(&mut command, path, self.context.path.as_deref());
        Ok((command, path.to_path_buf()))
    }
}

fn spawn_failure(tool: RuntimeTool, path: PathBuf, error: std::io::Error) -> ToolFailure {
    match error.kind() {
        std::io::ErrorKind::NotFound => ToolFailure::Unavailable(tool),
        std::io::ErrorKind::PermissionDenied => ToolFailure::PermissionDenied(path),
        _ => ToolFailure::SpawnFailed(error.to_string()),
    }
}

fn stop_child(child: &mut std::process::Child) {
    let _ = child.kill();
    let _ = child.wait();
}

impl RuntimeTool {
    fn executable_name(self) -> &'static str {
        match self {
            Self::Git => "git",
            Self::Npx => "npx",
        }
    }

    fn version_args(self) -> &'static [&'static str] {
        &["--version"]
    }
}

fn discover_tool(
    tool: RuntimeTool,
    context: &RuntimeContext,
    override_path: Option<&Path>,
) -> RuntimeToolStatus {
    if let Some(path) = override_path {
        return probe_candidate(tool, path, context, true);
    }

    for candidate in candidates(tool, context) {
        let status = probe_candidate(tool, &candidate, context, false);
        if status.state == RuntimeToolState::Available {
            return status;
        }
    }

    missing(tool, None)
}

fn candidates(tool: RuntimeTool, context: &RuntimeContext) -> Vec<PathBuf> {
    let mut directories = Vec::new();
    if let Some(path) = &context.path {
        directories.extend(std::env::split_paths(path));
    }

    let variable_dir = |name: &str, suffix: &str| {
        context.variables.get(name).map(PathBuf::from).map(|path| {
            if suffix.is_empty() {
                path
            } else {
                path.join(suffix)
            }
        })
    };
    directories.extend(
        [
            variable_dir("VP_BIN_DIR", ""),
            variable_dir("VP_HOME", "bin"),
            variable_dir("VOLTA_HOME", "bin"),
            variable_dir("MISE_DATA_DIR", "shims"),
            variable_dir("XDG_DATA_HOME", "mise/shims"),
            variable_dir("FNM_MULTISHELL_PATH", "bin"),
            variable_dir("FNM_DIR", "aliases/default/bin"),
            variable_dir("NVM_BIN", ""),
        ]
        .into_iter()
        .flatten(),
    );

    directories.extend([
        context.home.join(".local/share/vite-plus/bin"),
        context.home.join(".vite-plus/bin"),
        context.home.join(".volta/bin"),
        context.home.join(".local/share/mise/shims"),
        context.home.join(".local/share/fnm/aliases/default/bin"),
        context.home.join(".fnm/aliases/default/bin"),
        context.home.join(".local/bin"),
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/usr/bin"),
        PathBuf::from("/bin"),
    ]);

    let mut candidates = Vec::new();
    for directory in directories {
        let candidate = directory.join(tool.executable_name());
        if !candidates.contains(&candidate) {
            candidates.push(candidate);
        }
    }
    candidates
}

fn probe_candidate(
    tool: RuntimeTool,
    path: &Path,
    context: &RuntimeContext,
    explicit: bool,
) -> RuntimeToolStatus {
    if !path.is_file() {
        return unavailable_candidate(tool, path, explicit, "File does not exist");
    }
    if !is_executable(path) {
        return unavailable_candidate(tool, path, explicit, "File is not executable");
    }

    let mut command = Command::new(path);
    command.args(tool.version_args());
    if tool == RuntimeTool::Npx {
        command.env_remove("GITHUB_TOKEN").env_remove("GH_TOKEN");
    }
    apply_path(&mut command, path, context.path.as_deref());
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    match output_with_timeout(command, Duration::from_secs(5)) {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            let version = normalize_version(
                tool,
                if stdout.trim().is_empty() {
                    &stderr
                } else {
                    &stdout
                },
            );
            RuntimeToolStatus {
                tool,
                state: RuntimeToolState::Available,
                path: Some(path.to_path_buf()),
                version,
                issue: None,
            }
        }
        Ok(output) => unavailable_candidate(
            tool,
            path,
            explicit,
            &format!("Version check exited with {}", output.status),
        ),
        Err(error) => unavailable_candidate(tool, path, explicit, &error),
    }
}

fn unavailable_candidate(
    tool: RuntimeTool,
    path: &Path,
    explicit: bool,
    issue: &str,
) -> RuntimeToolStatus {
    if explicit {
        RuntimeToolStatus {
            tool,
            state: RuntimeToolState::Invalid,
            path: Some(path.to_path_buf()),
            version: None,
            issue: Some(issue.to_string()),
        }
    } else {
        missing(tool, Some(issue.to_string()))
    }
}

fn missing(tool: RuntimeTool, issue: Option<String>) -> RuntimeToolStatus {
    RuntimeToolStatus {
        tool,
        state: RuntimeToolState::Missing,
        path: None,
        version: None,
        issue,
    }
}

fn apply_path(command: &mut Command, executable: &Path, inherited_path: Option<&std::ffi::OsStr>) {
    let mut directories = Vec::new();
    if let Some(parent) = executable.parent() {
        directories.push(parent.to_path_buf());
    }
    if let Some(path) = inherited_path {
        directories.extend(std::env::split_paths(path));
    }
    if let Ok(path) = std::env::join_paths(directories) {
        command.env("PATH", path);
    }
}

fn output_with_timeout(mut command: Command, timeout: Duration) -> Result<Output, String> {
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return child.wait_with_output().map_err(|error| error.to_string()),
            Ok(None) if started.elapsed() < timeout => thread::sleep(Duration::from_millis(10)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err("Version check timed out".into());
            }
            Err(error) => return Err(error.to_string()),
        }
    }
}

fn normalize_version(tool: RuntimeTool, value: &str) -> Option<String> {
    let value = value.lines().next()?.trim();
    if value.is_empty() {
        return None;
    }
    Some(
        match tool {
            RuntimeTool::Git => value.strip_prefix("git version ").unwrap_or(value),
            RuntimeTool::Npx => value,
        }
        .to_string(),
    )
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn discovers_npx_from_legacy_vite_plus_home_outside_gui_path() {
        let temp = tempfile::tempdir().unwrap();
        let npx = temp.path().join(".vite-plus/bin/npx");
        write_executable(&npx, "#!/bin/sh\necho 11.19.0\n");

        let tools = RuntimeTools::discover(
            RuntimeContext::new(
                temp.path(),
                Some(OsString::from("/usr/bin:/bin")),
                BTreeMap::new(),
            ),
            RuntimeOverrides::default(),
        );

        assert_eq!(tools.status().npx.state, RuntimeToolState::Available);
        assert_eq!(tools.status().npx.path.as_deref(), Some(npx.as_path()));
        assert_eq!(tools.status().npx.version.as_deref(), Some("11.19.0"));
    }

    #[test]
    fn executes_npx_with_its_sibling_runtime_on_path() {
        let temp = tempfile::tempdir().unwrap();
        let bin = temp.path().join(".vite-plus/bin");
        let npx = bin.join("npx");
        write_executable(
            &npx,
            "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then exec node --version; fi\nexec node \"$@\"\n",
        );
        write_executable(&bin.join("node"), "#!/bin/sh\necho sibling-runtime\n");
        let tools = RuntimeTools::discover(
            RuntimeContext::new(
                temp.path(),
                Some(OsString::from("/usr/bin:/bin")),
                BTreeMap::new(),
            ),
            RuntimeOverrides::default(),
        );

        let output = tools
            .execute(
                RuntimeTool::Npx,
                ToolRequest {
                    args: vec![OsString::from("skills")],
                    ..ToolRequest::default()
                },
            )
            .unwrap();

        assert!(output.status.success());
        assert_eq!(
            String::from_utf8_lossy(&output.stdout).trim(),
            "sibling-runtime"
        );
    }

    #[test]
    fn explicit_invalid_npx_path_is_reported_without_silent_fallback() {
        let temp = tempfile::tempdir().unwrap();
        let invalid = temp.path().join("missing-npx");
        let tools = RuntimeTools::discover(
            RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: None,
                npx: Some(invalid.clone()),
            },
        );

        assert_eq!(tools.status().npx.state, RuntimeToolState::Invalid);
        assert_eq!(tools.status().npx.path.as_deref(), Some(invalid.as_path()));
        assert_eq!(
            tools.status().npx.issue.as_deref(),
            Some("File does not exist")
        );
    }

    #[test]
    fn npx_execution_removes_github_credentials() {
        let temp = tempfile::tempdir().unwrap();
        let npx = temp.path().join("npx");
        write_executable(
            &npx,
            "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 1.0.0; exit; fi\nif [ -n \"$GITHUB_TOKEN$GH_TOKEN\" ]; then exit 9; fi\necho credentials-removed\n",
        );
        let tools = RuntimeTools::discover(
            RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: None,
                npx: Some(npx),
            },
        );
        let mut request = ToolRequest::default();
        request
            .env
            .insert(OsString::from("GITHUB_TOKEN"), OsString::from("secret"));
        request
            .env
            .insert(OsString::from("GH_TOKEN"), OsString::from("secret"));

        let output = tools.execute(RuntimeTool::Npx, request).unwrap();

        assert!(output.status.success());
        assert_eq!(
            String::from_utf8_lossy(&output.stdout).trim(),
            "credentials-removed"
        );
    }

    #[test]
    fn interruptible_execution_cancels_the_child() {
        let temp = tempfile::tempdir().unwrap();
        let git = temp.path().join("git");
        write_executable(
            &git,
            "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'git version 2.50.0'; exit; fi\nexec /bin/sleep 5\n",
        );
        let tools = RuntimeTools::discover(
            RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: Some(git),
                npx: None,
            },
        );
        let started = Instant::now();

        let error = tools
            .execute_interruptible(
                RuntimeTool::Git,
                ToolRequest::default(),
                Duration::from_secs(5),
                || false,
            )
            .unwrap_err();

        assert!(matches!(error, ToolFailure::Cancelled(RuntimeTool::Git)));
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn interruptible_execution_enforces_its_deadline() {
        let temp = tempfile::tempdir().unwrap();
        let git = temp.path().join("git");
        write_executable(
            &git,
            "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'git version 2.50.0'; exit; fi\nexec /bin/sleep 5\n",
        );
        let tools = RuntimeTools::discover(
            RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: Some(git),
                npx: None,
            },
        );
        let started = Instant::now();

        let error = tools
            .execute_interruptible(
                RuntimeTool::Git,
                ToolRequest::default(),
                Duration::from_millis(50),
                || true,
            )
            .unwrap_err();

        assert!(matches!(error, ToolFailure::TimedOut(RuntimeTool::Git)));
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn missing_project_folder_has_actionable_copy() {
        let temp = tempfile::tempdir().unwrap();
        let npx = temp.path().join("npx");
        write_executable(&npx, "#!/bin/sh\necho 1.0.0\n");
        let tools = RuntimeTools::discover(
            RuntimeContext::new(temp.path(), None, BTreeMap::new()),
            RuntimeOverrides {
                git: None,
                npx: Some(npx),
            },
        );

        let error = tools
            .execute(
                RuntimeTool::Npx,
                ToolRequest {
                    cwd: Some(temp.path().join("deleted-project")),
                    ..ToolRequest::default()
                },
            )
            .unwrap_err();

        assert_eq!(
            error.to_string(),
            "Project folder no longer exists. Choose another project."
        );
    }

    fn write_executable(path: &Path, contents: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, contents).unwrap();
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
    }
}
