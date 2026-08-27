use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use crate::paths::skip_dir_name;

/// Debounced filesystem watcher over skill directories — never the whole home tree.
pub struct SkillWatcher {
    _watcher: RecommendedWatcher,
    signal: Arc<WatchSignal>,
    dirs: Vec<PathBuf>,
}

impl SkillWatcher {
    pub fn new(dirs: &[PathBuf]) -> anyhow::Result<Self> {
        let mut dirs = dirs.to_vec();
        dirs.sort();
        dirs.dedup();
        let signal = Arc::new(WatchSignal::default());
        let callback_signal = Arc::clone(&signal);
        let mut watcher = notify::recommended_watcher(move |event| {
            if let Ok(event) = event {
                callback_signal.record(&event);
            }
        })?;
        for dir in &dirs {
            if dir.is_dir() {
                let _ = watcher.watch(dir, RecursiveMode::Recursive);
            }
        }
        Ok(Self {
            _watcher: watcher,
            signal,
            dirs,
        })
    }

    pub fn dirs(&self) -> &[PathBuf] {
        &self.dirs
    }

    pub fn waiter(&self) -> SkillWatchWaiter {
        SkillWatchWaiter {
            signal: Arc::clone(&self.signal),
        }
    }

    /// Ignore events for a short window after our own writes (save, update).
    pub fn ignore_for(&self, duration: Duration) {
        self.signal.ignore_for(duration);
    }

    pub fn interrupt_waiters(&self) {
        self.signal.interrupt_waiters();
    }
}

impl Drop for SkillWatcher {
    fn drop(&mut self) {
        self.signal.close();
    }
}

#[derive(Clone)]
pub struct SkillWatchWaiter {
    signal: Arc<WatchSignal>,
}

impl SkillWatchWaiter {
    pub fn wait_changed(&self) -> bool {
        self.signal.wait_changed()
    }
}

#[derive(Default)]
struct WatchSignal {
    state: Mutex<WatchState>,
    changed: Condvar,
}

#[derive(Default)]
struct WatchState {
    pending: bool,
    last_event: Option<Instant>,
    ignore_until: Option<Instant>,
    interrupted: bool,
    closed: bool,
}

impl WatchSignal {
    fn record(&self, event: &Event) {
        if !event_is_relevant(event) {
            return;
        }
        let now = Instant::now();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        if state.closed || state.ignore_until.is_some_and(|until| now < until) {
            return;
        }
        state.ignore_until = None;
        state.pending = true;
        state.last_event = Some(now);
        self.changed.notify_one();
    }

    fn ignore_for(&self, duration: Duration) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.pending = false;
        state.last_event = None;
        state.ignore_until = Some(Instant::now() + duration);
    }

    fn wait_changed(&self) -> bool {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        loop {
            if state.interrupted {
                state.interrupted = false;
                return false;
            }
            while !state.closed && !state.pending {
                state = self
                    .changed
                    .wait(state)
                    .unwrap_or_else(|error| error.into_inner());
                if state.interrupted {
                    state.interrupted = false;
                    return false;
                }
            }
            if state.closed {
                return false;
            }
            let Some(last_event) = state.last_event else {
                state.pending = false;
                continue;
            };
            let quiet_at = last_event + DEBOUNCE;
            let now = Instant::now();
            if now < quiet_at {
                let (next, _) = self
                    .changed
                    .wait_timeout(state, quiet_at.duration_since(now))
                    .unwrap_or_else(|error| error.into_inner());
                state = next;
                continue;
            }
            state.pending = false;
            state.last_event = None;
            return true;
        }
    }

    fn close(&self) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.closed = true;
        self.changed.notify_all();
    }

    fn interrupt_waiters(&self) {
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        state.interrupted = true;
        self.changed.notify_all();
    }
}

const DEBOUNCE: Duration = Duration::from_millis(600);

pub fn event_is_relevant(event: &Event) -> bool {
    if matches!(event.kind, EventKind::Access(_) | EventKind::Other) {
        return false;
    }
    event.paths.iter().any(|p| path_is_relevant(p))
}

/// Skill markdown, lockfiles, and files under a `skills/` folder — not caches, `.git`, or tmp.
pub fn path_is_relevant(path: &Path) -> bool {
    if path
        .components()
        .any(|c| skip_dir_name(&c.as_os_str().to_string_lossy()))
    {
        return false;
    }
    let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
        return false;
    };
    if name == ".DS_Store" || name.ends_with(".tmp") || name.ends_with('~') {
        return false;
    }
    name == "SKILL.md"
        || name == "skills-lock.json"
        || name == ".skill-lock.json"
        || path.components().any(|c| c.as_os_str() == "skills")
}

#[cfg(test)]
mod tests {
    use super::*;
    use notify::event::{AccessKind, ModifyKind};
    use std::fs;
    use std::path::Path;
    use std::thread;

    fn wait_for_change(watcher: &SkillWatcher) -> bool {
        let waiter = watcher.waiter();
        let (sent, received) = std::sync::mpsc::channel();
        let wait = thread::spawn(move || sent.send(waiter.wait_changed()));
        let changed = received
            .recv_timeout(Duration::from_secs(5))
            .unwrap_or(false);
        if !changed {
            watcher.interrupt_waiters();
        }
        let _ = wait.join();
        changed
    }

    fn modify(path: &str) -> Event {
        Event {
            kind: EventKind::Modify(ModifyKind::Any),
            paths: vec![PathBuf::from(path)],
            attrs: Default::default(),
        }
    }

    #[test]
    fn ignores_home_cache_and_git_internals() {
        assert!(!path_is_relevant(Path::new(
            "/Users/a/Library/Caches/com.apple.metal/shaders"
        )));
        assert!(!path_is_relevant(Path::new(
            "/Users/a/Work/repo/.git/FETCH_HEAD"
        )));
        assert!(!path_is_relevant(Path::new(
            "/Users/a/.cursor/skills/foo/SKILL.md.tmp"
        )));
        assert!(path_is_relevant(Path::new(
            "/Users/a/.cursor/skills/foo/SKILL.md"
        )));
        assert!(path_is_relevant(Path::new(
            "/Users/a/Work/app/.cursor/skills/ship/SKILL.md"
        )));
        assert!(path_is_relevant(Path::new(
            "/Users/a/.agents/.skill-lock.json"
        )));
        assert!(!event_is_relevant(&Event {
            kind: EventKind::Access(AccessKind::Any),
            paths: vec![PathBuf::from("/Users/a/.cursor/skills/foo/SKILL.md")],
            attrs: Default::default(),
        }));
        assert!(event_is_relevant(&modify(
            "/Users/a/.cursor/skills/foo/SKILL.md"
        )));
    }

    #[test]
    fn watcher_observes_skill_file_lifecycle() {
        let temp = tempfile::tempdir().unwrap();
        let skills = temp.path().join("skills");
        fs::create_dir(&skills).unwrap();
        let watcher = SkillWatcher::new(std::slice::from_ref(&skills)).unwrap();
        let original = skills.join("example.md");
        let renamed = skills.join("renamed.md");

        fs::write(&original, "first").unwrap();
        assert!(wait_for_change(&watcher));

        thread::sleep(DEBOUNCE);
        fs::rename(&original, &renamed).unwrap();
        assert!(wait_for_change(&watcher));

        thread::sleep(DEBOUNCE);
        fs::remove_file(&renamed).unwrap();
        assert!(wait_for_change(&watcher));
    }
}
