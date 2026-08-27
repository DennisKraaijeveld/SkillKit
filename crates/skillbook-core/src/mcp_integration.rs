use std::fs::{File, OpenOptions};
use std::io::{BufReader, Read, Write};
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};
use toml_edit::{DocumentMut, Item, Table, value};

const SERVER_NAME: &str = "skillkit";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum McpClient {
    Codex,
    ClaudeCode,
    Cursor,
}

impl McpClient {
    pub const ALL: [Self; 3] = [Self::Codex, Self::ClaudeCode, Self::Cursor];

    pub fn id(self) -> &'static str {
        match self {
            Self::Codex => "codex",
            Self::ClaudeCode => "claude-code",
            Self::Cursor => "cursor",
        }
    }

    fn config_path(self, home: &Path) -> PathBuf {
        match self {
            Self::Codex => home.join(".codex/config.toml"),
            Self::ClaudeCode => home.join(".claude.json"),
            Self::Cursor => home.join(".cursor/mcp.json"),
        }
    }

    fn detected(self, home: &Path) -> bool {
        let markers = match self {
            Self::Codex => vec![
                home.join(".codex"),
                home.join("Applications/Codex.app"),
                PathBuf::from("/Applications/Codex.app"),
            ],
            Self::ClaudeCode => vec![
                home.join(".claude"),
                home.join(".claude.json"),
                home.join(".local/bin/claude"),
                home.join(".claude/local/claude"),
            ],
            Self::Cursor => vec![
                home.join(".cursor"),
                home.join("Applications/Cursor.app"),
                PathBuf::from("/Applications/Cursor.app"),
            ],
        };
        markers.into_iter().any(|path| path.exists())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct McpClientStatus {
    pub client: McpClient,
    pub detected: bool,
    pub configured: bool,
    pub needs_repair: bool,
    pub conflict: bool,
    pub config_path: PathBuf,
    pub issue: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct McpIntegrationStatus {
    pub bundled_available: bool,
    pub installed: bool,
    pub update_available: bool,
    pub installed_path: PathBuf,
    pub clients: Vec<McpClientStatus>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EntryState {
    Absent,
    Exact,
    ManagedOther,
    Conflict,
}

pub fn mcp_integration_status(home: &Path, bundled_server: Option<&Path>) -> McpIntegrationStatus {
    let installed_path = installed_server_path(home);
    let bundled_available = bundled_server.is_some_and(Path::is_file);
    let installed = installed_path.is_file();
    let update_available = installed
        && bundled_available
        && bundled_server.is_some_and(|bundled| !files_equal(bundled, &installed_path));
    let clients = McpClient::ALL
        .into_iter()
        .map(|client| client_status(client, home, &installed_path))
        .collect();
    McpIntegrationStatus {
        bundled_available,
        installed,
        update_available,
        installed_path,
        clients,
    }
}

pub fn install_mcp_server(
    home: &Path,
    bundled_server: &Path,
) -> anyhow::Result<McpIntegrationStatus> {
    let _lock = integration_lock(home)?;
    install_server_inner(home, bundled_server)?;
    Ok(mcp_integration_status(home, Some(bundled_server)))
}

pub fn configure_mcp_client(
    client: McpClient,
    home: &Path,
    bundled_server: &Path,
) -> anyhow::Result<McpIntegrationStatus> {
    let _lock = integration_lock(home)?;
    let installed = install_server_inner(home, bundled_server)?;
    let config_path = client.config_path(home);
    match client {
        McpClient::Codex => configure_codex(&config_path, &installed)?,
        McpClient::ClaudeCode | McpClient::Cursor => {
            configure_json_client(&config_path, &installed)?
        }
    }
    Ok(mcp_integration_status(home, Some(bundled_server)))
}

pub fn disconnect_mcp_client(
    client: McpClient,
    home: &Path,
    bundled_server: Option<&Path>,
) -> anyhow::Result<McpIntegrationStatus> {
    let _lock = integration_lock(home)?;
    let installed = installed_server_path(home);
    let config_path = client.config_path(home);
    match client {
        McpClient::Codex => disconnect_codex(&config_path, &installed)?,
        McpClient::ClaudeCode | McpClient::Cursor => {
            disconnect_json_client(&config_path, &installed)?
        }
    }
    Ok(mcp_integration_status(home, bundled_server))
}

fn client_status(client: McpClient, home: &Path, installed: &Path) -> McpClientStatus {
    let config_path = client.config_path(home);
    let state = match client {
        McpClient::Codex => codex_entry_state(&config_path, installed),
        McpClient::ClaudeCode | McpClient::Cursor => json_entry_state(&config_path, installed),
    };
    let (entry, issue) = match state {
        Ok(entry) => (entry, entry_issue(entry)),
        Err(error) => (EntryState::Conflict, Some(error.to_string())),
    };
    McpClientStatus {
        client,
        detected: client.detected(home),
        configured: entry == EntryState::Exact,
        needs_repair: entry == EntryState::ManagedOther,
        conflict: entry == EntryState::Conflict,
        config_path,
        issue,
    }
}

fn entry_issue(state: EntryState) -> Option<String> {
    match state {
        EntryState::ManagedOther => Some("Configured with another SkillKit MCP path".into()),
        EntryState::Conflict => Some("A different server already uses the name skillkit".into()),
        EntryState::Absent | EntryState::Exact => None,
    }
}

fn installed_server_path(home: &Path) -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        home.join("Library/Application Support/SkillKit/bin/skillkit-mcp")
    }
    #[cfg(not(target_os = "macos"))]
    {
        home.join(".local/share/skillkit/bin/skillkit-mcp")
    }
}

fn install_server_inner(home: &Path, bundled_server: &Path) -> anyhow::Result<PathBuf> {
    if !bundled_server.is_file() {
        anyhow::bail!(
            "The bundled SkillKit MCP helper is unavailable at {}",
            bundled_server.display()
        );
    }
    let installed = installed_server_path(home);
    if files_equal(bundled_server, &installed) {
        ensure_executable(&installed)?;
        return Ok(installed);
    }
    let parent = installed
        .parent()
        .ok_or_else(|| anyhow::anyhow!("MCP helper path has no parent folder"))?;
    std::fs::create_dir_all(parent)?;
    let temporary = temporary_path(&installed);
    let result = (|| {
        std::fs::copy(bundled_server, &temporary)?;
        ensure_executable(&temporary)?;
        replace_file(&temporary, &installed)?;
        Ok::<(), anyhow::Error>(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result?;
    Ok(installed)
}

fn configure_codex(path: &Path, installed: &Path) -> anyhow::Result<()> {
    let mut document = read_toml(path)?;
    match codex_document_state(&document, installed)? {
        EntryState::Conflict => anyhow::bail!("A different server already uses the name skillkit"),
        EntryState::Absent | EntryState::Exact | EntryState::ManagedOther => {}
    }
    if document.get("mcp_servers").is_none() {
        document["mcp_servers"] = Item::Table(Table::new());
    }
    let servers = document["mcp_servers"]
        .as_table_like_mut()
        .ok_or_else(|| anyhow::anyhow!("mcp_servers in {} is not a table", path.display()))?;
    let mut server = Table::new();
    server["command"] = value(installed.display().to_string());
    server["default_tools_approval_mode"] = value("writes");
    servers.insert(SERVER_NAME, Item::Table(server));
    write_private(path, document.to_string().as_bytes())
}

fn disconnect_codex(path: &Path, installed: &Path) -> anyhow::Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let mut document = read_toml(path)?;
    match codex_document_state(&document, installed)? {
        EntryState::Absent => return Ok(()),
        EntryState::Conflict => anyhow::bail!("The skillkit entry is not managed by SkillKit"),
        EntryState::Exact | EntryState::ManagedOther => {}
    }
    let servers = document["mcp_servers"]
        .as_table_like_mut()
        .ok_or_else(|| anyhow::anyhow!("mcp_servers in {} is not a table", path.display()))?;
    servers.remove(SERVER_NAME);
    write_private(path, document.to_string().as_bytes())
}

fn codex_entry_state(path: &Path, installed: &Path) -> anyhow::Result<EntryState> {
    if !path.exists() {
        return Ok(EntryState::Absent);
    }
    codex_document_state(&read_toml(path)?, installed)
}

fn codex_document_state(document: &DocumentMut, installed: &Path) -> anyhow::Result<EntryState> {
    let Some(server) = document
        .get("mcp_servers")
        .and_then(|servers| servers.get(SERVER_NAME))
    else {
        return Ok(EntryState::Absent);
    };
    let command = server.get("command").and_then(Item::as_str);
    Ok(command_state(command, installed))
}

fn read_toml(path: &Path) -> anyhow::Result<DocumentMut> {
    if !path.exists() {
        return Ok(DocumentMut::new());
    }
    let text = std::fs::read_to_string(path)?;
    text.parse::<DocumentMut>()
        .map_err(|error| anyhow::anyhow!("Could not parse {}: {error}", path.display()))
}

fn configure_json_client(path: &Path, installed: &Path) -> anyhow::Result<()> {
    let mut document = read_json(path)?;
    match json_document_state(&document, installed)? {
        EntryState::Conflict => anyhow::bail!("A different server already uses the name skillkit"),
        EntryState::Absent | EntryState::Exact | EntryState::ManagedOther => {}
    }
    let root = document
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("{} must contain a JSON object", path.display()))?;
    let servers = object_entry(root, "mcpServers", path)?;
    servers.insert(
        SERVER_NAME.into(),
        json!({
            "type": "stdio",
            "command": installed.display().to_string(),
            "args": []
        }),
    );
    write_json(path, &document)
}

fn disconnect_json_client(path: &Path, installed: &Path) -> anyhow::Result<()> {
    if !path.exists() {
        return Ok(());
    }
    let mut document = read_json(path)?;
    match json_document_state(&document, installed)? {
        EntryState::Absent => return Ok(()),
        EntryState::Conflict => anyhow::bail!("The skillkit entry is not managed by SkillKit"),
        EntryState::Exact | EntryState::ManagedOther => {}
    }
    let root = document
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("{} must contain a JSON object", path.display()))?;
    if let Some(servers) = root.get_mut("mcpServers").and_then(Value::as_object_mut) {
        servers.remove(SERVER_NAME);
    }
    write_json(path, &document)
}

fn json_entry_state(path: &Path, installed: &Path) -> anyhow::Result<EntryState> {
    if !path.exists() {
        return Ok(EntryState::Absent);
    }
    json_document_state(&read_json(path)?, installed)
}

fn json_document_state(document: &Value, installed: &Path) -> anyhow::Result<EntryState> {
    let root = document
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("MCP configuration must contain a JSON object"))?;
    let Some(server) = root
        .get("mcpServers")
        .and_then(Value::as_object)
        .and_then(|servers| servers.get(SERVER_NAME))
    else {
        return Ok(EntryState::Absent);
    };
    let command = server.get("command").and_then(Value::as_str);
    Ok(command_state(command, installed))
}

fn command_state(command: Option<&str>, installed: &Path) -> EntryState {
    let Some(command) = command else {
        return EntryState::Conflict;
    };
    let path = Path::new(command);
    if path == installed {
        EntryState::Exact
    } else if path.file_name().is_some_and(|name| name == "skillkit-mcp") {
        EntryState::ManagedOther
    } else {
        EntryState::Conflict
    }
}

fn read_json(path: &Path) -> anyhow::Result<Value> {
    if !path.exists() {
        return Ok(Value::Object(Map::new()));
    }
    let bytes = std::fs::read(path)?;
    serde_json::from_slice(&bytes)
        .map_err(|error| anyhow::anyhow!("Could not parse {}: {error}", path.display()))
}

fn object_entry<'a>(
    root: &'a mut Map<String, Value>,
    key: &str,
    path: &Path,
) -> anyhow::Result<&'a mut Map<String, Value>> {
    if !root.contains_key(key) {
        root.insert(key.into(), Value::Object(Map::new()));
    }
    root.get_mut(key)
        .and_then(Value::as_object_mut)
        .ok_or_else(|| anyhow::anyhow!("{key} in {} must be a JSON object", path.display()))
}

fn write_json(path: &Path, document: &Value) -> anyhow::Result<()> {
    let mut bytes = serde_json::to_vec_pretty(document)?;
    bytes.push(b'\n');
    write_private(path, &bytes)
}

fn write_private(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Configuration path has no parent folder"))?;
    std::fs::create_dir_all(parent)?;
    let temporary = temporary_path(path);
    let result = (|| {
        let mut options = OpenOptions::new();
        options.create_new(true).write(true);
        let mut file = options.open(&temporary)?;
        set_private_permissions(&file, path)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        replace_file(&temporary, path)?;
        Ok::<(), anyhow::Error>(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result
}

fn integration_lock(home: &Path) -> anyhow::Result<File> {
    let installed = installed_server_path(home);
    let directory = installed
        .parent()
        .and_then(Path::parent)
        .ok_or_else(|| anyhow::anyhow!("SkillKit support path is unavailable"))?;
    std::fs::create_dir_all(directory)?;
    let path = directory.join("mcp-integration.lock");
    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(&path)?;
    file.lock()?;
    Ok(file)
}

fn temporary_path(path: &Path) -> PathBuf {
    let extension = path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| format!("{extension}.skillkit-{}.tmp", std::process::id()))
        .unwrap_or_else(|| format!("skillkit-{}.tmp", std::process::id()));
    path.with_extension(extension)
}

fn replace_file(from: &Path, to: &Path) -> std::io::Result<()> {
    #[cfg(windows)]
    if to.exists() {
        std::fs::remove_file(to)?;
    }
    std::fs::rename(from, to)
}

fn files_equal(left: &Path, right: &Path) -> bool {
    let Ok(left_file) = File::open(left) else {
        return false;
    };
    let Ok(right_file) = File::open(right) else {
        return false;
    };
    if left_file.metadata().ok().map(|meta| meta.len())
        != right_file.metadata().ok().map(|meta| meta.len())
    {
        return false;
    }
    let mut left = BufReader::new(left_file);
    let mut right = BufReader::new(right_file);
    let mut left_buffer = [0_u8; 8192];
    let mut right_buffer = [0_u8; 8192];
    loop {
        let Ok(left_count) = left.read(&mut left_buffer) else {
            return false;
        };
        let Ok(right_count) = right.read(&mut right_buffer) else {
            return false;
        };
        if left_count != right_count || left_buffer[..left_count] != right_buffer[..right_count] {
            return false;
        }
        if left_count == 0 {
            return true;
        }
    }
}

#[cfg(unix)]
fn ensure_executable(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(path, permissions)
}

#[cfg(not(unix))]
fn ensure_executable(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(unix)]
fn set_private_permissions(file: &File, existing: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mode = std::fs::metadata(existing)
        .map(|metadata| metadata.permissions().mode())
        .unwrap_or(0o600);
    file.set_permissions(std::fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_private_permissions(_file: &File, _existing: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    struct Fixture {
        _temp: TempDir,
        home: PathBuf,
        bundled: PathBuf,
    }

    impl Fixture {
        fn new() -> Self {
            let temp = tempfile::tempdir().unwrap();
            let home = temp.path().join("home");
            let bundled = temp
                .path()
                .join("SkillKit.app/Contents/Helpers/skillkit-mcp");
            std::fs::create_dir_all(bundled.parent().unwrap()).unwrap();
            std::fs::create_dir_all(&home).unwrap();
            std::fs::write(&bundled, b"mcp-helper-v1").unwrap();
            Self {
                _temp: temp,
                home,
                bundled,
            }
        }

        fn status(&self) -> McpIntegrationStatus {
            mcp_integration_status(&self.home, Some(&self.bundled))
        }
    }

    #[test]
    fn installs_and_updates_the_stable_helper() {
        let fixture = Fixture::new();
        let before = fixture.status();
        assert!(before.bundled_available);
        assert!(!before.installed);

        let installed = install_mcp_server(&fixture.home, &fixture.bundled).unwrap();
        assert!(installed.installed);
        assert!(!installed.update_available);
        assert_eq!(
            std::fs::read(&installed.installed_path).unwrap(),
            b"mcp-helper-v1"
        );

        std::fs::write(&fixture.bundled, b"mcp-helper-v2").unwrap();
        assert!(fixture.status().update_available);
        let updated = install_mcp_server(&fixture.home, &fixture.bundled).unwrap();
        assert_eq!(
            std::fs::read(&updated.installed_path).unwrap(),
            b"mcp-helper-v2"
        );
    }

    #[test]
    fn codex_registration_preserves_existing_configuration() {
        let fixture = Fixture::new();
        let path = McpClient::Codex.config_path(&fixture.home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            &path,
            "# keep this comment\nmodel = \"gpt-test\"\n\n[mcp_servers.other]\ncommand = \"other\"\n",
        )
        .unwrap();

        let status =
            configure_mcp_client(McpClient::Codex, &fixture.home, &fixture.bundled).unwrap();
        assert!(status.clients[0].configured);
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("# keep this comment"));
        assert!(text.contains("[mcp_servers.other]"));
        assert!(text.contains("default_tools_approval_mode = \"writes\""));

        disconnect_mcp_client(McpClient::Codex, &fixture.home, Some(&fixture.bundled)).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(!text.contains("[mcp_servers.skillkit]"));
        assert!(text.contains("[mcp_servers.other]"));
    }

    #[test]
    fn json_clients_preserve_other_servers_and_fields() {
        let fixture = Fixture::new();
        for client in [McpClient::ClaudeCode, McpClient::Cursor] {
            let path = client.config_path(&fixture.home);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(
                &path,
                br#"{"theme":"dark","mcpServers":{"other":{"command":"other"}}}"#,
            )
            .unwrap();

            let status = configure_mcp_client(client, &fixture.home, &fixture.bundled).unwrap();
            let client_status = status
                .clients
                .iter()
                .find(|status| status.client == client)
                .unwrap();
            assert!(client_status.configured);
            let json: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            assert_eq!(json["theme"], "dark");
            assert_eq!(json["mcpServers"]["other"]["command"], "other");
            assert_eq!(
                json["mcpServers"][SERVER_NAME]["command"],
                status.installed_path.display().to_string()
            );

            disconnect_mcp_client(client, &fixture.home, Some(&fixture.bundled)).unwrap();
            let json: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            assert!(json["mcpServers"].get(SERVER_NAME).is_none());
            assert_eq!(json["mcpServers"]["other"]["command"], "other");
        }
    }

    #[test]
    fn refuses_to_replace_an_unrelated_named_server() {
        let fixture = Fixture::new();
        let path = McpClient::Cursor.config_path(&fixture.home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            &path,
            br#"{"mcpServers":{"skillkit":{"command":"different-server"}}}"#,
        )
        .unwrap();

        let error =
            configure_mcp_client(McpClient::Cursor, &fixture.home, &fixture.bundled).unwrap_err();
        assert!(error.to_string().contains("different server"));
        assert_eq!(
            serde_json::from_slice::<Value>(&std::fs::read(&path).unwrap()).unwrap()["mcpServers"]
                [SERVER_NAME]["command"],
            "different-server"
        );
    }

    #[test]
    fn malformed_configuration_is_reported_without_replacement() {
        let fixture = Fixture::new();
        let path = McpClient::Codex.config_path(&fixture.home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, "not valid = [").unwrap();
        let before = std::fs::read(&path).unwrap();

        let status = fixture.status();
        assert!(status.clients[0].conflict);
        assert!(
            status.clients[0]
                .issue
                .as_deref()
                .unwrap()
                .contains("Could not parse")
        );
        assert!(configure_mcp_client(McpClient::Codex, &fixture.home, &fixture.bundled).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), before);
    }

    #[test]
    fn stale_skillkit_command_is_repairable() {
        let fixture = Fixture::new();
        let path = McpClient::Cursor.config_path(&fixture.home);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            &path,
            br#"{"mcpServers":{"skillkit":{"command":"skillkit-mcp"}}}"#,
        )
        .unwrap();

        let before = fixture.status();
        let cursor = before
            .clients
            .iter()
            .find(|status| status.client == McpClient::Cursor)
            .unwrap();
        assert!(cursor.needs_repair);
        assert!(!cursor.conflict);

        let after =
            configure_mcp_client(McpClient::Cursor, &fixture.home, &fixture.bundled).unwrap();
        assert!(after.clients[2].configured);
    }
}
