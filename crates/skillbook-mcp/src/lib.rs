use std::collections::{BTreeMap, BTreeSet};
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};

use rmcp::{
    Json, ServerHandler,
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::{Implementation, ServerCapabilities, ServerInfo},
    schemars, tool, tool_handler, tool_router,
};
use serde::{Deserialize, Serialize};
use skillbook_core::{
    AgentLink, AppConfig, ScanResult, Scope, Skill, link_skill_to_project, parse_skill_md,
    read_skill_file, scan_with_home, scan_with_home_including_global_equivalents,
};

const DEFAULT_LIMIT: usize = 25;
const MAX_LIMIT: usize = 100;
const SERVER_INSTRUCTIONS: &str = "Use SkillKit to inspect the live local Agent Skills catalog. Call search_skills before get_skill or link_skill_to_project. Read tools never modify files. link_skill_to_project creates conflict-safe symlinks and may register the project; use it only when the user asked to change project skill availability. Newly linked skills may require a new agent session before the client discovers them. In project-scoped mode, other project-only skills are hidden.";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum SkillScopeFilter {
    Global,
    Project,
    Custom,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, schemars::JsonSchema)]
pub struct SearchSkillsRequest {
    #[schemars(
        description = "Text matched against skill name, description, source, agent, and path"
    )]
    pub query: Option<String>,
    #[schemars(description = "Restrict results to global, project, or custom placements")]
    pub scope: Option<SkillScopeFilter>,
    #[schemars(description = "Restrict results to skills placed in this existing project folder")]
    pub project_root: Option<String>,
    #[schemars(description = "Restrict results to placements for this agent identifier")]
    pub agent: Option<String>,
    #[schemars(description = "Restrict results to local, git, or npx sources")]
    pub source_kind: Option<String>,
    #[schemars(
        description = "Restrict results by whether installed contents differ from their tracked source"
    )]
    pub local_modified: Option<bool>,
    #[schemars(description = "Zero-based result offset")]
    pub cursor: Option<u32>,
    #[schemars(description = "Number of results to return, from 1 through 100")]
    #[schemars(range(min = 1, max = 100))]
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Deserialize, Serialize, schemars::JsonSchema)]
pub struct GetSkillRequest {
    #[schemars(description = "Exact skill id returned by search_skills or inspect_project_skills")]
    pub id: String,
    #[schemars(
        description = "Include the Markdown body; defaults to false to keep responses compact"
    )]
    pub include_body: Option<bool>,
}

#[derive(Debug, Clone, Deserialize, Serialize, schemars::JsonSchema)]
pub struct InspectProjectSkillsRequest {
    #[schemars(description = "Existing project folder to inspect")]
    pub project_root: String,
    #[schemars(description = "Optional text filter applied to project skills")]
    pub query: Option<String>,
    #[schemars(description = "Agent identifiers whose missing placements should be reported")]
    pub agents: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize, Serialize, schemars::JsonSchema)]
pub struct LinkSkillToProjectRequest {
    #[schemars(
        description = "Exact source skill id returned by search_skills or inspect_project_skills"
    )]
    pub id: String,
    #[schemars(description = "Existing project folder that will receive skill symlinks")]
    pub project_root: String,
    #[schemars(
        description = "Explicit destination agent identifiers, such as agents, claude, cursor, or codex"
    )]
    #[schemars(length(min = 1))]
    pub agents: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct SkillPlacementView {
    pub agent: String,
    pub path: String,
    pub scope: String,
    pub root: Option<String>,
    pub is_symlink: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct SkillSummary {
    pub id: String,
    pub name: String,
    pub description: String,
    pub canonical_path: String,
    pub skill_md: String,
    pub scopes: Vec<String>,
    pub project_roots: Vec<String>,
    pub source_kind: String,
    pub source_label: String,
    pub github_url: Option<String>,
    pub version_status: String,
    pub installed_version: Option<String>,
    pub latest_version: Option<String>,
    pub local_modified: bool,
    pub placements: Vec<SkillPlacementView>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct SearchSkillsResponse {
    pub skills: Vec<SkillSummary>,
    pub total: u32,
    pub next_cursor: Option<u32>,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct SkillDetail {
    #[serde(flatten)]
    pub summary: SkillSummary,
    pub yaml: String,
    pub body: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct GetSkillResponse {
    pub skill: SkillDetail,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct ProjectSkillView {
    #[serde(flatten)]
    pub skill: SkillSummary,
    pub project_agents: Vec<String>,
    pub missing_agents: Vec<String>,
    pub shared_outside_project: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct DuplicateSkillGroup {
    pub reason: String,
    pub copies: Vec<SkillSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct InspectProjectSkillsResponse {
    pub project_root: String,
    pub registered: bool,
    pub requested_agents: Vec<String>,
    pub skills: Vec<ProjectSkillView>,
    pub duplicates: Vec<DuplicateSkillGroup>,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, schemars::JsonSchema)]
pub struct LinkSkillToProjectResponse {
    pub ok: bool,
    pub skill_id: String,
    pub skill_name: String,
    pub project_root: String,
    pub agents: Vec<String>,
    pub placements: Vec<String>,
    pub registered: bool,
    pub message: String,
    pub warning: Option<String>,
    pub requires_new_session: bool,
}

#[derive(Debug, Clone)]
enum CatalogScope {
    All,
    Project(PathBuf),
}

#[derive(Debug, Clone)]
struct CatalogAccess {
    home: PathBuf,
    config_path: PathBuf,
    scope: CatalogScope,
}

struct CatalogSnapshot {
    config: AppConfig,
    result: ScanResult,
}

impl CatalogAccess {
    fn scan(&self, extra_project: Option<&Path>) -> Result<CatalogSnapshot, String> {
        self.scan_with_global_equivalents(extra_project, false)
    }

    fn scan_with_global_equivalents(
        &self,
        extra_project: Option<&Path>,
        include_global_equivalents: bool,
    ) -> Result<CatalogSnapshot, String> {
        let config = AppConfig::load_from(&self.config_path)
            .map_err(|error| format!("Could not load SkillKit config: {error}"))?;
        let mut scan_config = config.clone();
        match &self.scope {
            CatalogScope::All => {}
            CatalogScope::Project(root) => {
                scan_config.project_roots = vec![root.clone()];
                scan_config.custom_roots.clear();
            }
        }
        if let Some(root) = extra_project {
            add_project_root(&mut scan_config, root);
        }
        Ok(CatalogSnapshot {
            result: if include_global_equivalents {
                scan_with_home_including_global_equivalents(&scan_config, &self.home)
            } else {
                scan_with_home(&scan_config, &self.home)
            },
            config,
        })
    }

    fn search(&self, request: SearchSkillsRequest) -> Result<SearchSkillsResponse, String> {
        let project_root = request
            .project_root
            .as_deref()
            .map(|path| self.allowed_project(path))
            .transpose()?;
        let source_kind = request
            .source_kind
            .as_deref()
            .map(normalize_source_kind)
            .transpose()?;
        let snapshot = self.scan(project_root.as_deref())?;
        let query = request.query.as_deref().map(str::trim).unwrap_or("");
        let agent = request.agent.as_deref().map(str::trim).unwrap_or("");

        let mut skills = snapshot
            .result
            .skills
            .iter()
            .filter(|skill| self.skill_visible(skill))
            .filter(|skill| query.is_empty() || skill.matches_query(query))
            .filter(|skill| {
                request
                    .scope
                    .is_none_or(|scope| self.skill_has_scope(skill, scope))
            })
            .filter(|skill| {
                project_root
                    .as_deref()
                    .is_none_or(|root| skill_has_project(skill, root))
            })
            .filter(|skill| {
                agent.is_empty()
                    || self
                        .visible_placements(skill)
                        .any(|placement| placement.agent.eq_ignore_ascii_case(agent))
            })
            .filter(|skill| {
                source_kind
                    .as_deref()
                    .is_none_or(|kind| source_matches(skill, kind))
            })
            .filter(|skill| {
                request
                    .local_modified
                    .is_none_or(|modified| skill.local_modified == modified)
            })
            .map(|skill| self.summary(skill))
            .collect::<Vec<_>>();
        skills.sort_by(|left, right| {
            left.name
                .to_lowercase()
                .cmp(&right.name.to_lowercase())
                .then(left.id.cmp(&right.id))
        });

        let total = skills.len();
        let cursor = request.cursor.unwrap_or(0) as usize;
        let limit = request
            .limit
            .map(|value| value as usize)
            .unwrap_or(DEFAULT_LIMIT);
        if !(1..=MAX_LIMIT).contains(&limit) {
            return Err(format!("limit must be from 1 through {MAX_LIMIT}"));
        }
        let page = skills
            .into_iter()
            .skip(cursor)
            .take(limit)
            .collect::<Vec<_>>();
        let next = cursor.saturating_add(page.len());

        Ok(SearchSkillsResponse {
            skills: page,
            total: total as u32,
            next_cursor: (next < total).then_some(next as u32),
            errors: snapshot.result.errors,
        })
    }

    fn get(&self, request: GetSkillRequest) -> Result<GetSkillResponse, String> {
        let snapshot = self.scan(None)?;
        let skill = snapshot
            .result
            .skills
            .iter()
            .find(|skill| skill.id == request.id && self.skill_visible(skill))
            .ok_or_else(|| "Skill not found or unavailable in this server scope".to_string())?;
        let text = read_skill_file(&skill.skill_md)
            .map_err(|error| format!("Could not read {}: {error}", skill.skill_md.display()))?;
        let parsed = parse_skill_md(&text);

        Ok(GetSkillResponse {
            skill: SkillDetail {
                summary: self.summary(skill),
                yaml: parsed.frontmatter.unwrap_or_default(),
                body: request.include_body.unwrap_or(false).then_some(parsed.body),
            },
            errors: snapshot.result.errors,
        })
    }

    fn inspect(
        &self,
        request: InspectProjectSkillsRequest,
    ) -> Result<InspectProjectSkillsResponse, String> {
        let project_root = self.allowed_project(&request.project_root)?;
        let snapshot = self.scan_with_global_equivalents(Some(&project_root), true)?;
        let requested_agents = normalized_agents(request.agents.unwrap_or_default())?;
        let query = request.query.as_deref().map(str::trim).unwrap_or("");
        let relevant = snapshot
            .result
            .skills
            .iter()
            .filter(|skill| self.skill_visible(skill))
            .filter(|skill| query.is_empty() || skill.matches_query(query))
            .collect::<Vec<_>>();

        let mut skills = relevant
            .iter()
            .copied()
            .filter(|skill| skill_has_project(skill, &project_root))
            .map(|skill| {
                let project_agents = project_agents(skill, &project_root);
                let missing_agents = requested_agents
                    .iter()
                    .filter(|agent| !project_agents.iter().any(|placed| placed == *agent))
                    .cloned()
                    .collect();
                ProjectSkillView {
                    skill: self.summary(skill),
                    project_agents,
                    missing_agents,
                    shared_outside_project: skill
                        .agents
                        .iter()
                        .any(|placement| !placement_in_project(placement, &project_root)),
                }
            })
            .collect::<Vec<_>>();
        skills.sort_by(|left, right| {
            left.skill
                .name
                .to_lowercase()
                .cmp(&right.skill.name.to_lowercase())
                .then(left.skill.id.cmp(&right.skill.id))
        });

        let mut by_duplicate = BTreeMap::<String, Vec<&Skill>>::new();
        for skill in relevant {
            by_duplicate
                .entry(skill.duplicate_key())
                .or_default()
                .push(skill);
        }
        let mut duplicates = by_duplicate
            .into_values()
            .filter(|copies| {
                copies.len() > 1
                    && copies
                        .iter()
                        .any(|skill| skill_has_project(skill, &project_root))
            })
            .map(|mut copies| {
                copies.sort_by(|left, right| left.id.cmp(&right.id));
                DuplicateSkillGroup {
                    reason: copies[0].duplicate_reason().to_string(),
                    copies: copies
                        .into_iter()
                        .map(|skill| self.summary(skill))
                        .collect(),
                }
            })
            .collect::<Vec<_>>();
        duplicates.sort_by(|left, right| {
            left.copies[0]
                .name
                .to_lowercase()
                .cmp(&right.copies[0].name.to_lowercase())
        });

        Ok(InspectProjectSkillsResponse {
            project_root: project_root.display().to_string(),
            registered: config_has_project(&snapshot.config, &project_root),
            requested_agents,
            skills,
            duplicates,
            errors: snapshot.result.errors,
        })
    }

    fn link(
        &self,
        request: LinkSkillToProjectRequest,
    ) -> Result<LinkSkillToProjectResponse, String> {
        let project_root = self.allowed_project(&request.project_root)?;
        let agents = normalized_agents(request.agents)?;
        if agents.is_empty() {
            return Err("Choose at least one destination agent".to_string());
        }
        let _lock = self.mutation_lock()?;
        let snapshot = self.scan(Some(&project_root))?;
        let skill = snapshot
            .result
            .skills
            .iter()
            .find(|skill| skill.id == request.id && self.skill_visible(skill))
            .cloned()
            .ok_or_else(|| "Skill not found or unavailable in this server scope".to_string())?;

        let outcome = link_skill_to_project(&skill, &project_root, &agents);
        let mut warning = None;
        let mut registered = config_has_project(&snapshot.config, &project_root);
        if outcome.ok && !registered {
            let mut config = snapshot.config;
            add_project_root(&mut config, &project_root);
            match config.save_to(&self.config_path) {
                Ok(()) => registered = true,
                Err(error) => {
                    warning = Some(format!(
                        "The links were created, but the project could not be registered in SkillKit: {error}"
                    ));
                }
            }
        }

        let placements = if outcome.ok {
            self.scan(Some(&project_root))?
                .result
                .skills
                .iter()
                .find(|candidate| candidate.id == skill.id)
                .map(|candidate| {
                    candidate
                        .agents
                        .iter()
                        .filter(|placement| placement_in_project(placement, &project_root))
                        .map(|placement| placement.path.display().to_string())
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default()
        } else {
            Vec::new()
        };

        Ok(LinkSkillToProjectResponse {
            ok: outcome.ok,
            skill_id: skill.id,
            skill_name: skill.name,
            project_root: project_root.display().to_string(),
            agents,
            placements,
            registered,
            message: outcome.message,
            warning,
            requires_new_session: outcome.ok,
        })
    }

    fn allowed_project(&self, raw: &str) -> Result<PathBuf, String> {
        let raw = raw.trim();
        if raw.is_empty() {
            return Err("project_root is required".to_string());
        }
        let root = PathBuf::from(raw)
            .canonicalize()
            .map_err(|error| format!("Project folder is unavailable: {error}"))?;
        if !root.is_dir() {
            return Err("Project folder does not exist".to_string());
        }
        if let CatalogScope::Project(allowed) = &self.scope
            && !same_path(allowed, &root)
        {
            return Err(format!(
                "This MCP server is restricted to {}",
                allowed.display()
            ));
        }
        Ok(root)
    }

    fn skill_visible(&self, skill: &Skill) -> bool {
        self.visible_placements(skill).next().is_some()
    }

    fn visible_placements<'a>(
        &'a self,
        skill: &'a Skill,
    ) -> impl Iterator<Item = &'a AgentLink> + 'a {
        skill
            .agents
            .iter()
            .filter(|placement| self.placement_visible(placement))
    }

    fn placement_visible(&self, placement: &AgentLink) -> bool {
        match &self.scope {
            CatalogScope::All => true,
            CatalogScope::Project(root) => match placement.scope {
                Scope::Global => true,
                Scope::Project => placement_in_project(placement, root),
                Scope::Custom => false,
            },
        }
    }

    fn skill_has_scope(&self, skill: &Skill, scope: SkillScopeFilter) -> bool {
        self.visible_placements(skill).any(|placement| {
            matches!(
                (scope, placement.scope),
                (SkillScopeFilter::Global, Scope::Global)
                    | (SkillScopeFilter::Project, Scope::Project)
                    | (SkillScopeFilter::Custom, Scope::Custom)
            )
        })
    }

    fn summary(&self, skill: &Skill) -> SkillSummary {
        let mut placements = self
            .visible_placements(skill)
            .map(placement_view)
            .collect::<Vec<_>>();
        placements.sort_by(|left, right| {
            left.agent
                .cmp(&right.agent)
                .then(left.path.cmp(&right.path))
        });
        let scopes = placements
            .iter()
            .map(|placement| placement.scope.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let project_roots = placements
            .iter()
            .filter(|placement| placement.scope == "project")
            .filter_map(|placement| placement.root.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();

        SkillSummary {
            id: skill.id.clone(),
            name: skill.name.clone(),
            description: skill.description.clone(),
            canonical_path: skill.canonical_dir.display().to_string(),
            skill_md: skill.skill_md.display().to_string(),
            scopes,
            project_roots,
            source_kind: skill.source.kind_label().to_string(),
            source_label: skill.source.label(),
            github_url: skill.source.github_url(),
            version_status: skill.version.label().to_string(),
            installed_version: skill.installed_version.clone(),
            latest_version: skill.latest_version.clone(),
            local_modified: skill.local_modified,
            placements,
        }
    }

    fn mutation_lock(&self) -> Result<File, String> {
        let parent = self
            .config_path
            .parent()
            .ok_or_else(|| "SkillKit config path has no parent folder".to_string())?;
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("Could not create SkillKit config folder: {error}"))?;
        let lock_path = parent.join("mutation.lock");
        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .open(&lock_path)
            .map_err(|error| format!("Could not open {}: {error}", lock_path.display()))?;
        file.lock()
            .map_err(|error| format!("Could not lock {}: {error}", lock_path.display()))?;
        Ok(file)
    }
}

#[derive(Debug, Clone)]
pub struct SkillbookServer {
    catalog: CatalogAccess,
    tool_router: ToolRouter<Self>,
}

impl SkillbookServer {
    pub fn new(project_root: Option<PathBuf>) -> anyhow::Result<Self> {
        let home = dirs::home_dir().ok_or_else(|| anyhow::anyhow!("no home directory"))?;
        let config_path = skillbook_core::config_path()?;
        Self::with_paths(home, config_path, project_root)
    }

    fn with_paths(
        home: PathBuf,
        config_path: PathBuf,
        project_root: Option<PathBuf>,
    ) -> anyhow::Result<Self> {
        let scope = match project_root {
            Some(root) => {
                let root = root.canonicalize().map_err(|error| {
                    anyhow::anyhow!("project scope {} is unavailable: {error}", root.display())
                })?;
                if !root.is_dir() {
                    anyhow::bail!("project scope {} is not a folder", root.display());
                }
                CatalogScope::Project(root)
            }
            None => CatalogScope::All,
        };
        Ok(Self {
            catalog: CatalogAccess {
                home,
                config_path,
                scope,
            },
            tool_router: Self::tool_router(),
        })
    }
}

#[tool_router(router = tool_router)]
impl SkillbookServer {
    #[tool(
        name = "search_skills",
        description = "Search the live SkillKit catalog. Use this before get_skill or link_skill_to_project to obtain exact ids and current placement metadata.",
        annotations(
            title = "Search skills",
            read_only_hint = true,
            destructive_hint = false,
            idempotent_hint = true,
            open_world_hint = false
        )
    )]
    pub async fn search_skills(
        &self,
        Parameters(request): Parameters<SearchSkillsRequest>,
    ) -> Result<Json<SearchSkillsResponse>, String> {
        let catalog = self.catalog.clone();
        tokio::task::spawn_blocking(move || catalog.search(request))
            .await
            .map_err(|error| format!("Skill search task failed: {error}"))?
            .map(Json)
    }

    #[tool(
        name = "get_skill",
        description = "Read one exact skill from the live catalog, including parsed YAML and optionally its Markdown body. The id must come from a SkillKit search or project inspection.",
        annotations(
            title = "Get skill",
            read_only_hint = true,
            destructive_hint = false,
            idempotent_hint = true,
            open_world_hint = false
        )
    )]
    pub async fn get_skill(
        &self,
        Parameters(request): Parameters<GetSkillRequest>,
    ) -> Result<Json<GetSkillResponse>, String> {
        let catalog = self.catalog.clone();
        tokio::task::spawn_blocking(move || catalog.get(request))
            .await
            .map_err(|error| format!("Skill read task failed: {error}"))?
            .map(Json)
    }

    #[tool(
        name = "inspect_project_skills",
        description = "Inspect one existing project's current skill placements, requested-agent coverage, independent duplicates, registration state, and scan errors without changing files.",
        annotations(
            title = "Inspect project skills",
            read_only_hint = true,
            destructive_hint = false,
            idempotent_hint = true,
            open_world_hint = false
        )
    )]
    pub async fn inspect_project_skills(
        &self,
        Parameters(request): Parameters<InspectProjectSkillsRequest>,
    ) -> Result<Json<InspectProjectSkillsResponse>, String> {
        let catalog = self.catalog.clone();
        tokio::task::spawn_blocking(move || catalog.inspect(request))
            .await
            .map_err(|error| format!("Project inspection task failed: {error}"))?
            .map(Json)
    }

    #[tool(
        name = "link_skill_to_project",
        description = "Create conflict-safe symlinks from one catalog skill into explicitly selected agent skill folders in an existing project. This changes local files and may register the project in SkillKit.",
        annotations(
            title = "Link skill to project",
            read_only_hint = false,
            destructive_hint = false,
            idempotent_hint = true,
            open_world_hint = false
        )
    )]
    pub async fn link_skill_to_project(
        &self,
        Parameters(request): Parameters<LinkSkillToProjectRequest>,
    ) -> Result<Json<LinkSkillToProjectResponse>, String> {
        let catalog = self.catalog.clone();
        tokio::task::spawn_blocking(move || catalog.link(request))
            .await
            .map_err(|error| format!("Skill link task failed: {error}"))?
            .map(Json)
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for SkillbookServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(
                Implementation::new("skillkit", env!("CARGO_PKG_VERSION"))
                    .with_title("SkillKit")
                    .with_description("Inspect and place local Agent Skills"),
            )
            .with_instructions(SERVER_INSTRUCTIONS)
    }
}

fn placement_view(placement: &AgentLink) -> SkillPlacementView {
    SkillPlacementView {
        agent: placement.agent.clone(),
        path: placement.path.display().to_string(),
        scope: scope_label(placement.scope).to_string(),
        root: placement
            .root
            .as_ref()
            .map(|root| root.display().to_string()),
        is_symlink: placement.is_symlink,
    }
}

fn scope_label(scope: Scope) -> &'static str {
    match scope {
        Scope::Global => "global",
        Scope::Project => "project",
        Scope::Custom => "custom",
    }
}

fn normalize_source_kind(raw: &str) -> Result<String, String> {
    match raw.trim().to_lowercase().as_str() {
        "local" => Ok("local".to_string()),
        "git" => Ok("git".to_string()),
        "npx" | "npx skills" | "skills" | "skills_cli" => Ok("npx".to_string()),
        _ => Err("source_kind must be local, git, or npx".to_string()),
    }
}

fn source_matches(skill: &Skill, source_kind: &str) -> bool {
    match source_kind {
        "npx" => skill.source.is_npx_skills(),
        "git" => skill.source.kind_label() == "git",
        "local" => skill.source.kind_label() == "local",
        _ => false,
    }
}

fn normalized_agents(agents: Vec<String>) -> Result<Vec<String>, String> {
    let mut normalized = BTreeSet::new();
    for agent in agents {
        let agent = agent.trim().to_lowercase();
        if agent.is_empty() {
            return Err("Agent identifiers cannot be empty".to_string());
        }
        normalized.insert(agent);
    }
    Ok(normalized.into_iter().collect())
}

fn add_project_root(config: &mut AppConfig, root: &Path) {
    if !config
        .project_roots
        .iter()
        .any(|candidate| same_path(candidate, root))
    {
        config.project_roots.push(root.to_path_buf());
        config.project_roots.sort();
        config.project_roots.dedup();
    }
}

fn config_has_project(config: &AppConfig, root: &Path) -> bool {
    config
        .project_roots
        .iter()
        .any(|candidate| same_path(candidate, root))
}

fn skill_has_project(skill: &Skill, root: &Path) -> bool {
    skill
        .agents
        .iter()
        .any(|placement| placement_in_project(placement, root))
}

fn project_agents(skill: &Skill, root: &Path) -> Vec<String> {
    skill
        .agents
        .iter()
        .filter(|placement| placement_in_project(placement, root))
        .map(|placement| placement.agent.to_lowercase())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn placement_in_project(placement: &AgentLink, root: &Path) -> bool {
    placement.scope == Scope::Project
        && placement
            .root
            .as_deref()
            .is_some_and(|candidate| same_path(candidate, root))
}

fn same_path(left: &Path, right: &Path) -> bool {
    if left == right {
        return true;
    }
    match (left.canonicalize(), right.canonicalize()) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use rmcp::{
        ClientHandler, ServiceExt,
        model::{CallToolRequestParams, ClientInfo},
    };
    use serde_json::json;
    use tempfile::TempDir;

    use super::*;

    struct Fixture {
        temp: TempDir,
        home: PathBuf,
        config_path: PathBuf,
        project: PathBuf,
    }

    impl Fixture {
        fn new() -> Self {
            let temp = tempfile::tempdir().unwrap();
            let home = temp.path().join("home");
            let project = temp.path().join("project");
            let config_path = temp.path().join("config/config.toml");
            fs::create_dir_all(&home).unwrap();
            fs::create_dir_all(project.join(".git")).unwrap();
            Self {
                temp,
                home,
                config_path,
                project,
            }
        }

        fn skill(&self, parent: &Path, folder: &str, name: &str, description: &str) -> PathBuf {
            let dir = parent.join(folder);
            fs::create_dir_all(&dir).unwrap();
            fs::write(
                dir.join("SKILL.md"),
                format!(
                    "---\nname: {name}\ndescription: {description}\n---\n\n# {name}\n\nBody for {name}.\n"
                ),
            )
            .unwrap();
            dir
        }

        fn server(&self, scoped: bool) -> SkillbookServer {
            SkillbookServer::with_paths(
                self.home.clone(),
                self.config_path.clone(),
                scoped.then(|| self.project.clone()),
            )
            .unwrap()
        }
    }

    #[test]
    fn search_is_paginated_and_project_scope_hides_other_projects() {
        let fixture = Fixture::new();
        let global = fixture.home.join(".codex/skills");
        fixture.skill(&global, "alpha", "alpha", "Alpha workflow");
        fixture.skill(&global, "beta", "beta", "Beta workflow");
        let other = fixture.temp.path().join("other");
        fs::create_dir_all(other.join(".git")).unwrap();
        fixture.skill(
            &other.join(".claude/skills"),
            "private",
            "private",
            "Other project",
        );
        let mut config = AppConfig::default();
        config.project_roots = vec![other];
        config.custom_roots = vec![fixture.temp.path().join("private-missing-root")];
        config.save_to(&fixture.config_path).unwrap();

        let response = fixture
            .server(true)
            .catalog
            .search(SearchSkillsRequest {
                limit: Some(1),
                ..SearchSkillsRequest::default()
            })
            .unwrap();

        assert_eq!(response.total, 2);
        assert_eq!(response.skills.len(), 1);
        assert_eq!(response.next_cursor, Some(1));
        assert!(response.skills.iter().all(|skill| skill.name != "private"));
        assert!(response.errors.is_empty());
    }

    #[test]
    fn project_scope_must_be_a_folder() {
        let fixture = Fixture::new();
        let file = fixture.temp.path().join("not-a-project");
        fs::write(&file, "not a folder").unwrap();

        assert!(
            SkillbookServer::with_paths(fixture.home, fixture.config_path, Some(file)).is_err()
        );
    }

    #[test]
    fn get_skill_only_includes_body_when_requested() {
        let fixture = Fixture::new();
        let global = fixture.home.join(".codex/skills");
        fixture.skill(&global, "alpha", "alpha", "Alpha workflow");
        let server = fixture.server(false);
        let id = server
            .catalog
            .search(SearchSkillsRequest::default())
            .unwrap()
            .skills[0]
            .id
            .clone();

        let compact = server
            .catalog
            .get(GetSkillRequest {
                id: id.clone(),
                include_body: None,
            })
            .unwrap();
        let full = server
            .catalog
            .get(GetSkillRequest {
                id,
                include_body: Some(true),
            })
            .unwrap();

        assert_eq!(compact.skill.body, None);
        assert!(full.skill.body.unwrap().contains("Body for alpha"));
    }

    #[test]
    fn inspection_reports_missing_agents_and_independent_duplicates() {
        let fixture = Fixture::new();
        fixture.skill(
            &fixture.home.join(".codex/skills"),
            "shared",
            "shared",
            "Shared workflow",
        );
        fixture.skill(
            &fixture.project.join(".claude/skills"),
            "shared",
            "shared",
            "Shared workflow",
        );

        let response = fixture
            .server(false)
            .catalog
            .inspect(InspectProjectSkillsRequest {
                project_root: fixture.project.display().to_string(),
                query: None,
                agents: Some(vec!["claude".into(), "codex".into()]),
            })
            .unwrap();

        assert_eq!(response.skills.len(), 1);
        assert_eq!(response.skills[0].project_agents, ["claude"]);
        assert_eq!(response.skills[0].missing_agents, ["codex"]);
        assert_eq!(response.duplicates.len(), 1);
        assert_eq!(response.duplicates[0].copies.len(), 2);
    }

    #[test]
    fn link_is_idempotent_conflict_safe_and_registers_project() {
        let fixture = Fixture::new();
        fixture.skill(
            &fixture.home.join(".codex/skills"),
            "shared",
            "shared",
            "Shared workflow",
        );
        let server = fixture.server(false);
        let id = server
            .catalog
            .search(SearchSkillsRequest::default())
            .unwrap()
            .skills[0]
            .id
            .clone();
        let request = LinkSkillToProjectRequest {
            id,
            project_root: fixture.project.display().to_string(),
            agents: vec!["codex".into(), "claude".into()],
        };

        let first = server.catalog.link(request.clone()).unwrap();
        let second = server.catalog.link(request).unwrap();

        assert!(first.ok, "{}", first.message);
        assert!(first.registered);
        assert_eq!(first.placements.len(), 2);
        assert!(second.ok, "{}", second.message);
        assert!(second.message.contains("already linked"));
        let config = AppConfig::load_from(&fixture.config_path).unwrap();
        assert!(config_has_project(&config, &fixture.project));
    }

    #[test]
    fn tool_metadata_separates_reads_from_the_write() {
        let fixture = Fixture::new();
        let server = fixture.server(false);
        let tools = server.tool_router.list_all();

        assert_eq!(tools.len(), 4);
        for tool in tools {
            let annotations = tool.annotations.unwrap();
            if tool.name == "link_skill_to_project" {
                assert_eq!(annotations.read_only_hint, Some(false));
                assert_eq!(annotations.destructive_hint, Some(false));
                assert_eq!(annotations.idempotent_hint, Some(true));
            } else {
                assert_eq!(annotations.read_only_hint, Some(true));
            }
            assert_eq!(annotations.open_world_hint, Some(false));
            assert!(tool.output_schema.is_some());
        }
        assert!(
            server
                .get_info()
                .instructions
                .unwrap()
                .contains("new agent session")
        );
    }

    #[derive(Debug, Clone, Default)]
    struct TestClient;

    impl ClientHandler for TestClient {
        fn get_info(&self) -> ClientInfo {
            ClientInfo::default()
        }
    }

    #[tokio::test]
    async fn protocol_serves_structured_search_results() -> anyhow::Result<()> {
        let fixture = Fixture::new();
        fixture.skill(
            &fixture.home.join(".codex/skills"),
            "alpha",
            "alpha",
            "Alpha workflow",
        );
        let server = fixture.server(false);
        let (server_transport, client_transport) = tokio::io::duplex(16 * 1024);
        let server_handle = tokio::spawn(async move {
            server.serve(server_transport).await?.waiting().await?;
            anyhow::Ok(())
        });
        let client = TestClient.serve(client_transport).await?;
        let tools = client.list_tools(None).await?;
        assert!(tools.tools.iter().any(|tool| tool.name == "search_skills"));

        let arguments = json!({"query": "alpha"}).as_object().unwrap().clone();
        let result = client
            .call_tool(CallToolRequestParams::new("search_skills").with_arguments(arguments))
            .await?;
        let response: SearchSkillsResponse =
            serde_json::from_value(result.structured_content.unwrap())?;
        assert_eq!(response.total, 1);
        assert_eq!(response.skills[0].name, "alpha");

        client.cancel().await?;
        server_handle.await??;
        Ok(())
    }
}
