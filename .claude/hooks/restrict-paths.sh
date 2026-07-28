#!/usr/bin/env bash
# ============================================================================
# restrict-paths.sh — Claude Code PreToolUse hook
# Installed by: /optimus:permissions (optimus-claude plugin)
# Source:       https://github.com/oprogramadorreal/optimus-claude
# Docs:         skills/permissions/README.md
# ============================================================================
# HOOK_VERSION: 7
# ^ Bump on every behavioural change. The plugin's SessionStart hook compares
#   this against the copy installed in a project and recommends re-running
#   /optimus:permissions when the project's copy is older — a plugin update
#   never re-copies an already-installed hook on its own.
# ============================================================================
#
# PURPOSE:
#   Prevents Claude Code from writing or deleting files outside your project
#   directory. This is a safety guardrail, not a permissions bypass — it adds
#   restrictions, not removes them.
#
# WHAT THIS SCRIPT DOES:
#   - Edit/Write operations inside the project  → silently allowed
#   - Edit/Write operations outside the project → prompts you for approval
#   - Creating a NEW file under the OS temp root → prompts you, and tells Claude
#                                                 the session scratchpad is exempt
#   - Edit/Write/delete in Claude's memory store → silently allowed
#   - Edit/Write/delete in Claude's scratchpad   → silently allowed
#   - rm/rmdir commands outside the project     → hard blocked
#   - Edit/Write of precious unversioned files  → prompts you for approval
#   - rm/rmdir of precious unversioned files    → hard blocked
#   - Git operations on feature branches        → silently allowed
#   - Git operations on protected branches       → hard blocked
#   - Everything else (reads, searches, etc.)   → passes through unchanged
#
# WHAT THIS SCRIPT DOES NOT DO:
#   - Does NOT send data anywhere (no network calls)
#   - Does NOT log or record file paths or commands
#   - Does NOT modify, read, or copy your files
#   - Does NOT run in the background or persist after Claude Code exits
#
# FAIL-OPEN DESIGN:
#   When the hook cannot determine whether an operation is safe (e.g.,
#   CLAUDE_PROJECT_DIR is unset, JSON parsing fails, or the file_path field
#   is missing), it allows the operation rather than blocking it. This avoids
#   breaking legitimate tool use when input formats change.
#
# MULTI-REPO WORKSPACE SUPPORT:
#   When the project root is not itself a git repo (e.g., a directory
#   containing multiple independent git repos), the hook resolves the git
#   context per-file and per-command. This ensures precious file protection
#   and branch protection work correctly in each sub-repo.
#
# PRECIOUS FILE PROTECTION (always-on):
#   Well-known sensitive files (.env, *.key, *.pem, *.sqlite, etc.) that are
#   not tracked by git receive extra protection: edits prompt for approval,
#   deletions are blocked. No configuration needed — patterns are hardcoded
#   in the is_precious() function. See the skill's README for the full list.
#
# CLAUDE MEMORY STORE (always-allowed):
#   Claude Code keeps a per-project auto-memory store under
#   <home>/.claude/projects/<project>/memory/. Although that path is outside
#   CLAUDE_PROJECT_DIR, it is Claude's own scratchpad (plain markdown, designed
#   to be written and pruned by Claude), so writes AND deletes there are allowed
#   without a prompt. The exemption is scoped to a single-segment memory/ subtree
#   only — the rest of ~/.claude (settings.json, etc.) is NOT exempt and still
#   prompts on out-of-project write / is blocked on out-of-project delete.
#
# CLAUDE SESSION SCRATCHPAD (always-allowed):
#   The harness gives each session a scratchpad under
#   <temp>/claude/<project>/<session>/scratchpad/ (temp root taken from
#   TMPDIR/TEMP/TMP, or /tmp). Like the memory store it is Claude's own throwaway
#   working area, so writes AND deletes there are allowed without a prompt. The
#   match requires the full <temp>/claude/<project>/<session>/scratchpad shape
#   (both <project> and <session> are single path segments), so it can't stretch
#   to an unrelated 'scratchpad' dir elsewhere under the temp root. If the temp
#   root can't be resolved, the path falls back to the normal out-of-project prompt.
#
#   TEMP-WRITE NUDGE: creating a NEW file under the temp root WITHOUT this shape
#   (an invented temp dir) still prompts you — the nudge never decides for you,
#   so a temp path you asked for yourself still comes to you for approval.
#
#   TWO AUDIENCES, TWO FIELDS. For a PreToolUse "ask", Claude Code shows
#   permissionDecisionReason to the USER, while additionalContext injects
#   information for CLAUDE alongside the tool decision. Only "deny" sends its
#   reason to the model. So the prompt text is
#   written for you, and the scratchpad reminder — the part only Claude can act
#   on — rides additionalContext. Putting the reminder in the reason instead
#   would deliver it to the one party who cannot act on it.
#
#   The reminder deliberately does NOT name a scratchpad path: only the harness
#   knows it, and it already gives it to Claude in the system prompt. A path
#   built here from the project basename would name a look-alike directory the
#   harness neither creates nor cleans up.
#
#   Scope: a file that ALREADY EXISTS keeps the plain prompt (existence is
#   tested on the NORMALIZED path, so a phantom intermediate dir cannot make an
#   existing file look new), and ~/.claude keeps its own — it is Claude's
#   config, not scratch, and it can sit under the temp root in CI images. The
#   nudge is skipped when the path contains a ".." this platform's realpath left
#   unresolved. The ~/.claude veto is deliberately NOT a whole-$HOME veto, which
#   would disable the nudge wherever the temp root lives under the home dir
#   (TMPDIR=$HOME/tmp, MSYS2/Cygwin default mounts) — the common case.
#
# PATH NORMALIZATION:
#   normalize() lowercases on Windows, resolves "..", collapses repeated slashes
#   and drops a trailing one, so every spelling of a path compares equal. The
#   collapse is load-bearing: macOS TMPDIR ends in '/', a non-GNU realpath that
#   rejects '-m' returns the string untouched, and the cd/pwd fallback splices
#   '//tmp' when the parent is '/' — each would otherwise leave a base that stops
#   matching paths written the ordinary way, silently killing an exemption.
#
#   A leading '//' is preserved only when it is present BOTH in the path as the
#   OS spells it (i.e. after cygpath, which is what turns '\\server\share' into
#   '//server/share' — probing the raw argument would miss every natively spelled
#   UNC path) AND in the post-realpath string. That is a UNC network root on
#   MSYS/Cygwin, genuinely distinct from '/'. Requiring both readings matters in
#   both directions: on Linux realpath collapses '//x' to '/x' (POSIX leaves
#   exactly two leading slashes implementation-defined) and the platform's answer
#   is respected, while the cd/pwd fallback's spliced '//tmp' is NOT mistaken for
#   a UNC root. Three or more leading slashes are plain '/'.
#
#   normalize() also resolves '.' and '..' ITSELF (collapse_dot_segments) when
#   the steps above left them in place — a realpath that rejects '-m', or the
#   cd/pwd fallback. Doing so is what lets an ordinary in-project 'a/../b' stay
#   allowed on those platforms: the alternative, failing closed on any '..',
#   turns it into a hard DENY that goes to the model and can never be approved.
#   An absolute path cannot climb above its own root (POSIX: '/..' is '/').
#
#   Exemption gates take an ALREADY normalized path (the `_n` suffix), so a
#   caller normalizes once and consults all of them. Every gate that can reach an
#   auto-allow keeps a has_unresolved_traversal backstop for the one case the
#   resolution above cannot settle — a RELATIVE path, which has no root to anchor
#   '..' against — so such a path can never pass a prefix test.
#
# COMMAND PARSING:
#   A Bash tool call arrives as ONE string that may hold many commands. Both
#   Bash-side guards (delete protection, git branch protection) work on it in
#   four stages, each of which exists because skipping it turned the guard off
#   for an ordinary spelling rather than an exotic one:
#     1. Split on the shell's command operators — '&&', '||', ';', '|', '&' and
#        newline — then peel any leading keyword ('do ', 'then ', '{ ') the split
#        left at the front of a fragment.
#     2. shell_split() each fragment into words, honouring quotes and escapes and
#        expanding '~' and every SET $VAR, so a gate compares the path the shell
#        will act on rather than the characters as typed. A name this hook cannot
#        see (a caller's shell variable is not exported) stays literal — see
#        expand_word.
#     3. cmd_word_index() locates the fragment's command word THROUGH a wrapper
#        prefix (sudo, command, env VAR=val, xargs and its flags, /bin/rm, \rm),
#        and stops at the first token that is a real command — so an argument
#        that merely reads 'rm' is never mistaken for one.
#     4. `sh -c <string>`, `bash -c <string>` and `eval` carry a whole command
#        inside a single ARGUMENT, which stage 3 can never reach. unwrap_shell_c()
#        pulls the string out and feeds it back through stage 1, depth-bounded.
#   Two things a fragment's words are NOT: a redirection operator or its target
#   ('> /dev/null' is a stream, not a file to delete or a refspec to push), and a
#   relative path meaning what it says — a target is resolved against the chain's
#   own `cd` first, so `cd /etc && rm passwd` is judged as /etc/passwd.
#   Not covered, by design: command substitution (`rm $(cat list)`) and
#   `find -exec`, where the delete is not the fragment's own command. This is a
#   guardrail against accidents, not a sandbox against a determined bypass.
#
#   Known false positive, and deliberately kept: stage 1 splits on operators
#   BEFORE stage 2 parses quotes, so an operator INSIDE a quoted argument
#   (`echo "a; rm /etc/passwd"`) leaves a fragment that reads as a real command,
#   and it is denied. Stage 4 inherits the same wart — a mangled fragment
#   beginning `eval` gets unwrapped too. Quote-aware splitting would remove it,
#   and would also turn today's denies into silent allows: that same mangling is
#   the only reason `sh -c "cd /etc; rm passwd"` is caught, since the payload
#   reaches stage 4 as `cd /etc` and the delete arrives as its own fragment.
#   An over-eager prompt is recoverable; a missed delete is not.
#
# TO DISABLE OR REMOVE:
#   1. Delete this file: rm .claude/hooks/restrict-paths.sh
#   2. Remove the PreToolUse hook entry from .claude/settings.json
#   Or simply ignore it — the hook only runs when Claude Code invokes tools.
# ============================================================================

input=$(cat)

root="${CLAUDE_PROJECT_DIR}"
# Fail-open: if project root is unknown, allow rather than block all tool use
[[ -z "$root" ]] && exit 0

# --- Git repo resolution (per-path, with caching) ---
# In multi-repo workspaces the project root may not be a git repo.
# We resolve the git toplevel from each file's directory instead.
declare -A _git_root_cache 2>/dev/null || true  # associative array; ignore if bash < 4

find_git_root() {
  # Returns the git toplevel for a given path, or empty string if not in a repo.
  # Results are cached to avoid repeated git calls.
  local target_dir="$1"
  [[ -d "$target_dir" ]] || target_dir="$(dirname "$target_dir")"
  [[ -d "$target_dir" ]] || { echo ""; return; }

  # Check cache (bash 4+ associative arrays)
  if declare -p _git_root_cache &>/dev/null 2>&1; then
    if [[ -n "${_git_root_cache[$target_dir]+_}" ]]; then
      echo "${_git_root_cache[$target_dir]}"
      return
    fi
  fi

  local result
  result="$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null)" || result=""
  # Normalize on Windows
  if [[ -n "$result" ]] && command -v cygpath &>/dev/null; then
    result="$(cygpath -u "$result" 2>/dev/null || echo "$result")"
  fi

  # Cache result
  if declare -p _git_root_cache &>/dev/null 2>&1; then
    _git_root_cache[$target_dir]="$result"
  fi
  echo "$result"
}

is_git_tracked() {
  # Check if a file is tracked by git in its containing repo.
  # Fail-open: if not in a git repo or git unavailable, assume tracked (allow).
  local filepath="$1"
  local repo_root
  repo_root="$(find_git_root "$filepath")"
  [[ -n "$repo_root" ]] || return 0  # fail-open: no repo → assume tracked
  git -C "$repo_root" ls-files --error-unmatch "$filepath" &>/dev/null
}

# basename without the fork. The precious tests below run on EVERY Edit, Write
# and NotebookEdit, so a `$(basename ...)` here is a subshell on the hook's
# hottest path — and the `basename | tr` pipeline this replaces measured ~109 ms
# per call on Windows, where nothing else on that path forks at all.
_basename=""
basename_of() {
  local p="$1"
  while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
  _basename="${p##*/}"
}

# Case-fold ONCE, here, and hand the folded basename to both list tests. Folding
# separately inside each let the two disagree about the same file: this rule is
# platform-gated, and the recoverable test used to fold unconditionally, so on
# Linux 'NOTES.TXT.BAK' was recoverable to one entry point and unknown to the other.
precious_basename() {
  basename_of "$1"
  # Case-insensitive matching for Windows (NTFS) and macOS (APFS)
  [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == darwin* ]] && _basename="${_basename,,}"
}

is_precious() {
  precious_basename "$1"
  local lname="$_basename"
  is_precious_name "$lname" && return 0
  is_recoverable_precious_name "$lname"
}

# Strip ONE trailing backup or rotation suffix from a name. Result in _stripped;
# returns 1 when the name carries none. Shared by is_precious_name so the whole
# CLASS of backup suffixes is closed rather than one instance of it.
_stripped=""
strip_backup_suffix() {
  local n="$1"
  case "$n" in
    *'~') _stripped="${n%\~}"; return 0 ;;
    *.bak|*.backup|*.old|*.orig|*.save|*.saved|*.copy|*.prev) _stripped="${n%.*}"; return 0 ;;
    # Rotation: 'server.key.1', 'db.sqlite.02', 'prod.dump.003'.
    *.[0-9]|*.[0-9][0-9]|*.[0-9][0-9][0-9]) _stripped="${n%.*}"; return 0 ;;
  esac
  return 1
}

# The hard list, matched on a basename the caller has already case-folded.
# Split out of is_precious so is_recoverable_precious can re-test a '.bak' stem
# against it without recursing back through the tail call below.
is_precious_name() {
  local lname="$1"
  case "$lname" in
    # Secrets / credentials
    .env*) return 0 ;;
    local.settings.json|credentials.*|secrets.*) return 0 ;;
    docker-compose.override.yml) return 0 ;;
    appsettings.*.json)
      # appsettings.json (no dot-suffix) is usually tracked; variants are not
      [[ "$lname" != "appsettings.json" ]] && return 0 ;;
    # Service account / API keys
    *keyfile*.json) return 0 ;;
    # Monitoring agent configs (may contain license keys)
    newrelic.config) return 0 ;;
    # Certificates / keys
    *.key|*.pem|*.pfx|*.p12|*.cert|*.crt|*.jks) return 0 ;;
    # Database files
    *.sqlite|*.sqlite3|*.db|*.db-shm|*.db-wal|*.db-journal|*.mdf|*.ldf|*.ndf) return 0 ;;
    # Database dumps
    *.dump|*.sql.gz) return 0 ;;
  esac
  # A backup copy holds exactly what it copied, so re-test the stem against the
  # same list. Without this, only the PREFIX patterns above ('.env*',
  # 'credentials.*') survived an appended suffix — 'id_rsa.pem.bak',
  # 'server.key.old' and 'app.sqlite~' matched nothing, and the suffix laundered
  # them off the list. Re-testing only '.bak' closed one instance of that and
  # left '.old', '.orig', '.backup', '~' and '.1' doing the same job. Each hop
  # strips at least one character, so the recursion is bounded by the name.
  if strip_backup_suffix "$lname"; then
    is_precious_name "$_stripped"
    return $?
  fi
  return 1
}

# Precious, but recoverable: worth an ask before overwriting, never worth an
# undeniable block on delete. A PreToolUse deny is delivered to the model, not
# the user, so there is no path to "yes, delete it" — and these are exactly the
# files a cleanup step legitimately removes (the harness writes
# .claude/<skill>-deep-progress.json.bak on every run).
is_recoverable_precious() {
  precious_basename "$1"
  is_recoverable_precious_name "$_basename"
}

# Matched on a basename the caller has already case-folded, like is_precious_name.
# The trigger list stays deliberately narrower than strip_backup_suffix: this one
# also decides which ORDINARY files prompt before an overwrite, so widening it to
# every rotation suffix would start prompting on 'access.log.1' and 'main.py.orig'.
# Laundering is closed in is_precious_name instead, where the wider set can only
# ever ADD protection.
is_recoverable_precious_name() {
  local lname="$1"
  case "$lname" in
    *.suo|*.user) return 0 ;;
    *.bak)
      # Only a backup OF something ordinary is recoverable. Matching the '.bak'
      # suffix alone made the suffix a laundering trick: '.env.bak',
      # 'id_rsa.pem.bak', 'credentials.json.bak' and 'app.sqlite.bak' hold
      # exactly the secrets of the file they copy, yet each dropped out of the
      # hard list the moment the suffix was appended. Re-test the stem.
      is_precious_name "${lname%.bak}" && return 1
      return 0 ;;
  esac
  return 1
}

# --- Path normalization (cross-platform) ---
# Resolve '.' and '..' segments lexically, preserving a leading '/' or '//'.
# Pure bash (result in a global, no fork). `realpath -m` already does this, but a
# realpath that REJECTS '-m' (macOS/BSD) and the cd/pwd fallback both leave the
# segments in place — and a gate that cannot resolve '..' has to fail closed,
# which would turn an ordinary in-project 'a/../b' into an unapprovable deny.
_collapsed=""
collapse_dot_segments() {
  local p="$1" seg lead="" n
  case "$p" in
    //[!/]*) lead="//"; p="${p#//}" ;;
    /*)      lead="/";  p="${p#/}"  ;;
  esac
  local -a parts=()
  local IFS='/'
  # noglob around the split. `for seg in $p` is unquoted — it MUST be, that is
  # what splits on IFS — so without this every segment is also pathname-expanded
  # against the hook's CWD (the project root). A '*' segment then becomes N
  # segments here but stays ONE for the OS, and the extra segments absorb the
  # following '..', so '<proj>/*/../../../etc/evil' looks in-project to every
  # gate while the OS resolves it outside: a silent allow on the write AND an
  # escape from the rm hard-block. has_unresolved_traversal cannot backstop it,
  # since the '..' are gone by then. Restored only if we set it, so an outer
  # `set -f` survives.
  local _noglob_set=""
  [[ -o noglob ]] || { _noglob_set=1; set -f; }
  for seg in $p; do
    case "$seg" in
      ""|.) ;;
      ..)
        n=${#parts[@]}
        if [[ $n -gt 0 && "${parts[$((n-1))]}" != ".." ]]; then
          unset "parts[$((n-1))]"
          parts=(${parts[@]+"${parts[@]}"})
        elif [[ -z "$lead" ]]; then
          # A relative path may legitimately keep leading '..'; an absolute one
          # cannot go above its root (POSIX: '/..' is '/').
          parts+=("..")
        fi
        ;;
      *) parts+=("$seg") ;;
    esac
  done
  [[ -n "$_noglob_set" ]] && set +f
  _collapsed="$lead${parts[*]-}"
}

normalize() {
  local p="$1"
  # Convert Windows paths on MSYS/Cygwin. '--' so a path that looks like a flag
  # ('-n', '-e') is not eaten as one, which would hand the gates an empty string.
  command -v cygpath &>/dev/null && p="$(cygpath -u -- "$p" 2>/dev/null || printf '%s\n' "$p")"
  # How the OS itself spells the path, before any resolution. The UNC probe below
  # reads THIS, not "$1": cygpath is what turns '\\server\share' into
  # '//server/share', so probing the raw argument would miss every UNC path
  # spelled the native Windows way and collapse it onto an unrelated local path.
  local spelled="$p"
  # Resolve ../ traversal without requiring path to exist
  if command -v realpath &>/dev/null; then
    p="$(realpath -m -- "$p" 2>/dev/null || printf '%s\n' "$p")"
  elif [[ -d "$(dirname "$p")" ]]; then
    p="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"
  fi
  # Collapse repeated slashes, drop a trailing one (see header: PATH
  # NORMALIZATION). Requiring the UNC shape in BOTH the OS spelling and the
  # post-realpath string keeps the cd/pwd fallback's spliced '//tmp' from being
  # mistaken for a UNC root, while respecting a realpath that already collapsed a
  # genuine '//' per its platform's rule.
  local lead=""
  [[ "$spelled" == //[!/]* && "$p" == //[!/]* ]] && { lead="/"; p="${p#/}"; }
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  [[ "$p" == "/" ]] || p="${p%/}"
  p="$lead$p"
  # Resolve anything the steps above left behind. Skipped unless a dot-segment is
  # actually present, so the common path stays pure parameter expansion.
  case "$p" in
    */../*|*/..|../*|..|*/./*|*/.|./*|.) collapse_dot_segments "$p"; p="$_collapsed" ;;
  esac
  # Case-insensitive on Windows (NTFS)
  [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]] && p="${p,,}"
  # printf, not echo: a path of exactly '-n'/'-e'/'-E' is an echo FLAG and would
  # come back as the empty string, silently dropping the path from every gate.
  printf '%s\n' "$p"
}

# --- Shared path predicates (see header: PATH NORMALIZATION) ---
# Backstop, not the primary defence: normalize() now resolves '..' itself, so an
# absolute path reaching a gate has none left. What can still arrive is a
# RELATIVE path, which has no root to anchor '..' against. Kept on every gate
# that can auto-allow because it is free and fails in the safe direction.
has_unresolved_traversal() {
  case "$1" in */../*|*/..|../*|..) return 0 ;; esac
  return 1
}

# Rejects a RELATIVE temp root, which normalize() would resolve against this
# hook's working directory — turning an arbitrary sibling of the project into an
# auto-allowed subtree, exempt from the prompt AND from the rm hard-block.
# A bare leading backslash stays rejected: it is drive-RELATIVE on Windows.
is_absolute_path() {
  case "$1" in
    /*) return 0 ;;              # POSIX absolute, incl. //server/share
    '\\'?*) return 0 ;;          # UNC \\server\share (cygpath maps it to //...)
    [A-Za-z]:[/\\]*) return 0 ;; # drive-qualified C:\ or C:/
  esac
  return 1
}

# One path segment an exemption shape may match. Like has_unresolved_traversal
# this is now a backstop: normalize() drops '.' segments before any gate sees
# them. Kept because it is free and the shapes are meant to be exact.
is_single_segment() {
  case "$1" in
    ""|.|..) return 1 ;;
    */*|*\\*) return 1 ;;
  esac
  return 0
}

# --- Project root ---
# Resolved lazily: this hook fires on EVERY tool call, but only the write and rm
# branches consult the root, so reads/searches skip the normalize() forks.
_norm_root=""
_norm_root_resolved=""
resolve_norm_root() {
  [[ -n "$_norm_root_resolved" ]] && return
  _norm_root="$(normalize "$root")"
  # Trailing slash for prefix matching (avoids /project-other matching /project)
  [[ "$_norm_root" != */ ]] && _norm_root="${_norm_root}/"
  _norm_root_resolved=1
}

is_inside_project_n() {
  has_unresolved_traversal "$1" && return 1
  resolve_norm_root
  [[ "$1" == "$_norm_root"* || "$1" == "${_norm_root%/}" ]]
}

# --- Claude Code auto-memory store (see header: CLAUDE MEMORY STORE) ---
_norm_home=""
_norm_home_resolved=""
resolve_norm_home() {
  [[ -n "$_norm_home_resolved" ]] && return
  _norm_home_resolved=1
  # Fail closed on an unset home rather than normalizing "": on a realpath-less
  # platform that resolves to this hook's working directory, which would anchor
  # the memory-store exemption on an arbitrary cwd.
  local raw="${HOME:-${USERPROFILE:-}}"
  [[ -n "$raw" ]] || return
  _norm_home="$(normalize "$raw")"
}

# `${_norm_home%/}` so a home of "/" yields "/.claude", not "//.claude".
is_under_claude_config() {
  resolve_norm_home
  [[ -n "$_norm_home" ]] || return 1
  local home="${_norm_home%/}"
  [[ "$1" == "$home/.claude" || "$1" == "$home/.claude/"* ]]
}

is_claude_memory_n() {
  resolve_norm_home
  [[ -n "$_norm_home" ]] || return 1
  local norm_path="$1"
  has_unresolved_traversal "$norm_path" && return 1
  # Match exactly <home>/.claude/projects/<project>/memory[/...]. A bare case-glob
  # '*' also spans '/', so <project> goes through is_single_segment or the
  # exemption would stretch to a 'memory' dir nested arbitrarily deep.
  local prefix="${_norm_home%/}/.claude/projects/"
  [[ "$norm_path" == "$prefix"* ]] || return 1
  local rest="${norm_path#"$prefix"}"
  local seg="${rest%%/*}"
  is_single_segment "$seg" || return 1
  case "${rest#"$seg"}" in
    /memory|/memory/*) return 0 ;;
  esac
  return 1
}

# --- Claude Code session scratchpad (see header: CLAUDE SESSION SCRATCHPAD) ---
# Resolved lazily like the project root. The OS temp root varies (TMPDIR on
# macOS/Linux, TEMP/TMP on Windows, /tmp as a POSIX fallback), so each candidate
# is normalized once — a Windows temp mounted at /tmp then compares equal to a
# normalized file_path, and duplicate spellings collapse onto one base.
_scratch_bases_resolved=""
_scratch_bases=()
resolve_scratch_bases() {
  [[ -n "$_scratch_bases_resolved" ]] && return
  _scratch_bases_resolved=1
  local candidate norm_candidate entry seen
  local -a raws=()
  for candidate in "${TMPDIR:-}" "${TEMP:-}" "${TMP:-}" /tmp; do
    [[ -n "$candidate" ]] || continue
    is_absolute_path "$candidate" || continue
    # Dedup the RAW spelling before paying for normalize(): on Windows TEMP and
    # TMP are routinely the identical string, and each normalize() forks twice.
    seen=""
    for entry in ${raws[@]+"${raws[@]}"}; do [[ "$entry" == "$candidate" ]] && { seen=1; break; }; done
    [[ -n "$seen" ]] && continue
    raws+=("$candidate")
    norm_candidate="$(normalize "$candidate")"
    [[ -n "$norm_candidate" ]] || continue
    # A bare root is not a usable temp root — treating "/" (or the UNC namespace
    # root "//") as one would make every path "under the temp root".
    [[ "$norm_candidate" == "/" || "$norm_candidate" == "//" ]] && continue
    seen=""
    for entry in "${_scratch_bases[@]}"; do [[ "$entry" == "$norm_candidate" ]] && { seen=1; break; }; done
    [[ -n "$seen" ]] || _scratch_bases+=("$norm_candidate")
  done
}

is_under_temp_root() {
  resolve_scratch_bases
  local base
  for base in "${_scratch_bases[@]}"; do
    [[ "$1" == "$base/"* ]] && return 0
  done
  return 1
}

is_claude_scratchpad_n() {
  resolve_scratch_bases
  local norm_path="$1"
  has_unresolved_traversal "$norm_path" && return 1
  # Match exactly <temp>/claude/<project>/<session>/scratchpad[/...]; both slots
  # go through is_single_segment so the exemption can't stretch to a 'scratchpad'
  # dir nested arbitrarily deep under <temp>/claude/.
  local base prefix rest proj after sess
  for base in "${_scratch_bases[@]}"; do
    prefix="$base/claude/"
    [[ "$norm_path" == "$prefix"* ]] || continue
    rest="${norm_path#"$prefix"}"          # <project>/<session>/scratchpad/...
    proj="${rest%%/*}"
    after="${rest#"$proj"}"                 # /<session>/scratchpad/...
    is_single_segment "$proj" || continue
    [[ "$after" == /* ]] || continue
    after="${after#/}"                      # <session>/scratchpad/...
    sess="${after%%/*}"
    is_single_segment "$sess" || continue
    case "${after#"$sess"}" in
      /scratchpad|/scratchpad/*) return 0 ;;
    esac
  done
  return 1
}

# --- Temp-write nudge (see header: TEMP-WRITE NUDGE) ---
# Either prompts (exits via ask_permission) or returns 1 — never prints otherwise.
nudge_temp_write() {
  local filepath="$1" norm_path="$2" noun="$3" verb="$4"
  # Only a NEW file is nudged: an Edit of an existing temp file has nothing to do
  # with choosing a scratch location. Test the NORMALIZED path so a phantom
  # intermediate dir ('<temp>/a/../b.md') cannot make an existing file look new.
  # -L as well as -e, because -e follows symlinks and would call a dangling one new.
  [[ -e "$norm_path" || -L "$norm_path" ]] && return 1
  has_unresolved_traversal "$norm_path" && return 1
  is_under_claude_config "$norm_path" && return 1
  is_under_temp_root "$norm_path" || return 1
  ask_permission \
    "$noun '$filepath' is a new file outside the project, under the OS temp root. Allow this $verb?" \
    "This path is outside the exempt session scratchpad. Prefer the scratchpad directory given in your system prompt for throwaway files — writes there need no approval."
}

# --- JSON response helpers ---
# A reason can carry raw environment values (a temp root or directory name may
# legally contain a tab, CR or newline — a CRLF-sourced TEMP on Windows is the
# easy way to get one), and a bare control character makes the whole decision
# unparseable JSON, which the harness reads as "no decision" — silently dropping
# the deny or the ask. Every C0 code point JSON gives a short escape gets one;
# the rest are dropped. (DEL is legal raw in JSON, so it stays.)
# Writes to a global rather than stdout so the caller pays no subshell fork.
_json_escaped=""
json_escape() {
  # C locale pins the [$'\001'-$'\037'] range below to byte order: before bash
  # 4.3's globasciiranges default (stock macOS ships 3.2), bracket ranges follow
  # locale collation, which can let a control char through in a UTF-8 locale.
  local LC_ALL=C
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  s="${s//[$'\001'-$'\037']/}"
  _json_escaped="$s"
}

# $1 = decision, $2 = reason for the USER, $3 = optional context for CLAUDE.
# The two audiences are distinct — see header: TEMP-WRITE NUDGE. printf, not a
# `cat` heredoc, so emitting a decision costs no fork.
emit_decision() {
  json_escape "$2"
  local reason="$_json_escaped" extra=""
  if [[ -n "${3:-}" ]]; then
    json_escape "$3"
    extra=",\"additionalContext\":\"$_json_escaped\""
  fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"%s}}\n' \
    "$1" "$reason" "$extra"
  exit 0
}

ask_permission() { emit_decision ask "$1" "${2:-}"; }

# A deny already sends its reason to the model, so it needs no additionalContext.
deny_operation() { emit_decision deny "$1"; }

# --- Shared exemption ladder ---
# Locations that may be written/deleted without an out-of-project prompt. The
# structured-write branch and the Bash rm branch both consult THIS function, so
# the two can never disagree about what is exempt. Cheapest gate first: the
# project test is fork-free, the memory store costs one normalize, the scratchpad
# up to four. (Callers still run their own precious-file check afterwards, so
# this is not a blanket bypass.)
is_exempt_out_of_project_n() {
  is_inside_project_n "$1" && return 0
  is_claude_memory_n "$1" && return 0
  is_claude_scratchpad_n "$1" && return 0
  return 1
}

# --- Out-of-project gate for the structured write tools ---
# Returns 0 when the write may continue to the precious-file check;
# ask_permission exits the script.
guard_out_of_project_write() {
  local filepath="$1" noun="$2" verb="$3"
  local norm_path
  norm_path="$(normalize "$filepath")"
  is_exempt_out_of_project_n "$norm_path" && return 0
  # A new file under the temp root prompts with a scratchpad reminder for Claude;
  # the plain prompt below covers everything else. `|| true` so the expected
  # non-zero return cannot abort the script under an inherited errexit, which
  # would emit no decision at all.
  nudge_temp_write "$filepath" "$norm_path" "$noun" "$verb" || true
  ask_permission "$noun '$filepath' is outside project root. Allow this $verb?"
}

# --- Command-line word splitting (see header: COMMAND PARSING) ---
# Split a command fragment into shell words, honouring single quotes, double
# quotes and backslash escapes, then expand '~' and $VAR. Result in _words.
#
# `read -ra` is not a substitute: it splits on whitespace and hands back the
# characters verbatim, quote marks included. `rm "<abs path>"` then arrives as
# the single word '"<abs path>"', which normalize() resolves as a RELATIVE path
# under the project root — so the out-of-project hard block never fires. Claude
# Code quotes any path containing a space, so that was the common case, not an
# exotic one. Same story for '~/x' and '$HOME/x'.
_words=()
shell_split() {
  # Two statements on purpose: bash expands a whole `local` line BEFORE binding
  # any of its names, so `local s="$1" n=${#s}` reads the OUTER s and sets n=0 —
  # the loop below then never runs and every fragment splits to nothing.
  local s="$1"
  local n=${#s} i=0 c d q="" cur="" started=""
  _words=()
  while (( i < n )); do
    c="${s:i:1}"
    if [[ "$q" == "'" ]]; then
      if [[ "$c" == "'" ]]; then q=""; else cur+="$c"; fi
    elif [[ "$q" == '"' ]]; then
      if [[ "$c" == '"' ]]; then
        q=""
      elif [[ "$c" == '\' ]]; then
        # Inside double quotes a backslash escapes only these four.
        d="${s:i+1:1}"
        case "$d" in
          '"'|'\'|'$'|'`') cur+="$d"; (( ++i )) ;;
          *) cur+="$c" ;;
        esac
      else
        cur+="$c"
      fi
    else
      case "$c" in
        "'"|'"') q="$c"; started=1 ;;
        '\') cur+="${s:i+1:1}"; (( ++i )); started=1 ;;
        ' '|$'\t'|$'\n')
          if [[ -n "$started" ]]; then _words+=("$cur"); cur=""; started=""; fi
          ;;
        *) cur+="$c"; started=1 ;;
      esac
    fi
    # PRE-increment, throughout. `(( i++ ))` evaluates to the OLD value, so on
    # the first pass it evaluates to 0 — and an arithmetic command whose result
    # is 0 returns exit status 1. Under an inherited errexit that aborts the
    # hook on the very first character of the very first fragment, before any
    # decision is emitted: both Bash-side guards silently stop existing. `++i`
    # increments identically and can never evaluate to 0 here.
    (( ++i ))
  done
  [[ -n "$started" ]] && _words+=("$cur")
  local _i=0
  while (( _i < ${#_words[@]} )); do
    expand_word "${_words[_i]}"
    _words[_i]="$_expanded"
    (( ++_i ))
  done
  return 0
}

# Expand a leading '~' and every $VAR / ${VAR} in a word. No eval, no forks.
# Result in _expanded.
#
# Expansion is applied to every word, including single-quoted ones the shell
# would keep literal. That over-expands in exactly one direction: a file
# literally named '$HOME' would be judged by where the variable points, which
# errs toward asking or blocking. Under-expanding is the hole this closes —
# `rm $HOME/.ssh/id_rsa` used to read as an in-project relative path and sail
# straight through the out-of-project block.
_expanded=""
expand_word() {
  local w="$1" out="" rest name literal ch
  case "$w" in
    "~")   w="${HOME:-\~}" ;;
    "~/"*) w="${HOME:-\~}/${w#\~/}" ;;
  esac
  while [[ "$w" == *'$'* ]]; do
    out+="${w%%\$*}"
    rest="${w#*\$}"
    name=""
    if [[ "$rest" == '{'* && "$rest" == *'}'* ]]; then
      name="${rest%%\}*}"; name="${name#\{}"
      literal="\${$name}"
      rest="${rest#*\}}"
    else
      while [[ -n "$rest" ]]; do
        ch="${rest:0:1}"
        case "$ch" in
          [a-zA-Z0-9_]) name+="$ch"; rest="${rest:1}" ;;
          *) break ;;
        esac
      done
      literal="\$$name"
    fi
    # Only a plain identifier that is actually SET in this hook's environment is
    # resolved. '$(...)', '$1', '${x:-y}' and the like stay literal — reading
    # them needs an eval this hook will not run, and a word the hook leaves
    # literal is still checked, just as written.
    #
    # The set-test is load-bearing. A shell variable assigned in the CALLER
    # (`BUILD_DIR=build && rm -rf $BUILD_DIR/x`) is not exported, so the hook
    # never sees it — substituting "" collapsed the word to '/x', which every
    # gate then read as an absolute path outside the project and HARD DENIED.
    # A deny goes to the model with no prompt and no override, so ordinary
    # build-dir cleanup became impossible. Leaving the word literal instead
    # matches the file's fail-open rule (see header: FAIL-OPEN DESIGN): a name
    # this hook cannot resolve is a path it cannot judge. Exported and
    # environment variables — $HOME above all — are still expanded, so
    # `rm $HOME/.ssh/id_rsa` stays blocked.
    if [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && -n "${!name+set}" ]]; then
      out+="${!name}"
    else
      out+="$literal"
    fi
    w="$rest"
  done
  _expanded="$out$w"
}

# Locate the command word of an already-split fragment: sets _cmd_idx to the
# index of the first token whose basename matches one of the '|'-separated
# names in $1, and returns 1 when the fragment runs some other command.
#
# A guard anchored on the fragment's FIRST token misses every ordinary spelling
# of the same command — `sudo rm`, `command rm`, `env rm`, `/bin/rm`, `\rm`
# (which defeats an alias, not this hook), `xargs -n 1 rm`, `xargs -I {} rm`,
# `timeout 5 rm`. The walk steps over a wrapper, its flags, a flag's numeric or
# placeholder value, and VAR=val assignments, and it stops dead at the first
# token that is a real command, so `git commit -m "rm the old file"` can never
# be read as a delete.
#
# `sh -c <string>`, `bash -c <string>` and `eval <words>` are NOT wrappers in
# this sense and must not be added to the list below: their payload is a whole
# command string inside a single argument, not a token of this fragment, so no
# walk over these tokens can reach it. unwrap_shell_c() handles them instead, by
# handing the string back to the fragment splitter.
#
# Known limits, both pre-existing: a command reached through `find -exec` or a
# command substitution (`rm $(cat list)`) is not seen, because neither is a
# wrapper prefix — the fragment's command is `find` / the outer command.
_cmd_idx=-1
cmd_word_index() {
  local names="$1"; shift
  local -a t=("$@")
  local i tok base
  for ((i=0; i<${#t[@]}; i++)); do
    tok="${t[i]#\\}"
    base="${tok##*/}"
    case "|$names|" in
      *"|$base|"*) _cmd_idx=$i; return 0 ;;
    esac
    case "$tok" in
      sudo|doas|command|builtin|exec|env|nohup|nice|ionice|stdbuf|time|timeout|xargs) ;;
      -*|*=*|'{}'|'%'|[0-9]*) ;;
      *) return 1 ;;
    esac
  done
  return 1
}

# Recognize a redirection token. A redirection names a STREAM, never a path the
# command acts on or a refspec it pushes, and both spellings have to be caught:
# a lone operator ('rm x > /dev/null', 'git push > /dev/null') leaves its target
# in the NEXT word, while a glued one ('>/dev/null', '2>&1') carries it in the
# same word. Left unhandled, the first spelling made '/dev/null' look like a
# delete target — an unappealable deny on one of the most ordinary shell idioms
# there is — and made 'git push' look like it named an explicit refspec, which
# skipped the current-branch resolution and walked straight past the protected
# branch check. Sets _redir_takes_arg when the caller must also skip the next word.
_redir_takes_arg=""
is_redirection() {
  _redir_takes_arg=""
  local w="$1"
  # Drop a leading fd number ('2>', '10>&1') before matching the operator.
  w="${w#"${w%%[!0-9]*}"}"
  case "$w" in
    '>'|'>>'|'<'|'<<'|'<<<'|'>&'|'<&'|'<>'|'&>'|'&>>') _redir_takes_arg=1; return 0 ;;
    '>'*|'<'*|'&>'*) return 0 ;;
  esac
  return 1
}

# Extract the command string carried inside `sh -c <string>` / `bash -c <string>`
# (through any wrapper prefix) or concatenated after `eval`. Result in _unwrapped.
#
# Without this, one wrapper turned BOTH Bash-side guards off at once:
# `sh -c "rm -rf /etc"`, `eval rm /etc/passwd` and `bash -c "git push origin
# master"` all emitted nothing at all. The inner string is a single shell WORD to
# this fragment, so the only way to check it is to split it as a command in its
# own right — which is what the caller does with the result.
_unwrapped=""
unwrap_shell_c() {
  local -a t=("$@")
  cmd_word_index 'sh|bash|dash|ksh|zsh|eval' "${t[@]}" || return 1
  local base="${t[_cmd_idx]#\\}"; base="${base##*/}"
  local i _oldifs
  if [[ "$base" == eval ]]; then
    # `eval a b c` joins its words with a space and runs the result.
    (( ${#t[@]} > _cmd_idx + 1 )) || return 1
    _oldifs="$IFS"; IFS=' '; _unwrapped="${t[*]:$((_cmd_idx + 1))}"; IFS="$_oldifs"
    [[ -n "$_unwrapped" ]] || return 1
    return 0
  fi
  # A shell's command string is the argument after -c, which may be bundled with
  # other short flags ('sh -ec', 'bash -lc').
  for ((i=_cmd_idx + 1; i<${#t[@]}; i++)); do
    case "${t[i]}" in
      -*c) _unwrapped="${t[i+1]:-}"; [[ -n "$_unwrapped" ]] && return 0; return 1 ;;
      -*) ;;
      # A non-flag argument is a SCRIPT PATH ('bash scripts/build.sh'), not a
      # command string — nothing to unwrap.
      *) return 1 ;;
    esac
  done
  return 1
}

# --- Git branch protection ---
# Customize this list to match your project's protected branches.
# These branches are shielded from commits, pushes, rebases, resets,
# and deletions. All other branches are treated as feature branches
# where git operations are allowed without prompts.
PROTECTED_BRANCHES=("master" "main" "develop" "dev" "development" "staging" "stage" "prod" "production" "release")

is_protected_branch() {
  local branch="$1"
  for pb in "${PROTECTED_BRANCHES[@]}"; do
    [[ "$branch" == "$pb" ]] && return 0
  done
  return 1
}

get_current_branch() {
  git -C "${1:-$root}" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Resolve which git repo a git command targets.
# Uses -C <path> if present, otherwise tries the project root.
# Returns the repo directory suitable for get_current_branch, or empty if none.
resolve_git_context() {
  local dir="$1"  # from -C flag, or empty
  if [[ -n "$dir" ]]; then
    # Normalize Windows paths (d:/foo, D:\foo) to POSIX form (/d/foo)
    command -v cygpath &>/dev/null && dir="$(cygpath -u "$dir" 2>/dev/null || echo "$dir")"
    # -C was specified — resolve to an absolute path relative to project root
    if [[ "$dir" != /* ]]; then
      dir="$root/$dir"
    fi
    local repo_root
    repo_root="$(find_git_root "$dir")"
    if [[ -n "$repo_root" ]]; then
      echo "$repo_root"
      return
    fi
  fi
  # No -C or -C didn't resolve — try project root
  local root_repo
  root_repo="$(find_git_root "$root")"
  [[ -n "$root_repo" ]] && echo "$root_repo" && return
  # Multi-repo workspace: no git at root and no -C — can't determine context
  echo ""
}

# Parse git push arguments and deny if targeting a protected branch.
# Called with all tokens after "git push" as arguments.
# Calls deny_operation (which exits) if blocked; returns silently if allowed.
check_git_push() {
  local t
  for t in "$@"; do
    case "$t" in
      --all|--mirror) deny_operation "BLOCKED: 'git push $t' can affect protected branches." ;;
    esac
  done

  # Separate flags from positional args
  local -a positional=()
  local has_delete=false
  local i=1 skip_next=""
  while (( i <= $# )); do
    local arg="${!i}"
    if [[ -n "$skip_next" ]]; then skip_next=""; i=$(( i + 1 )); continue; fi
    # A redirection is not a refspec. Counted as one, `git push > /dev/null`
    # reached the branch resolution below with TWO positionals, so it took the
    # 'git push <remote> <refspec>' path and checked '/dev/null' against the
    # protected list instead of resolving the current branch — a push to master
    # one space away from unguarded.
    if is_redirection "$arg"; then
      skip_next="$_redir_takes_arg"
      i=$(( i + 1 )); continue
    fi
    case "$arg" in
      -d|--delete) has_delete=true ;;
      -f|--force|--force-with-lease*|--force-if-includes) ;;
      -u|--set-upstream|--no-verify|--dry-run|-n|--verbose|-v|--quiet|-q) ;;
      --atomic|--signed*|--no-signed|--thin|--no-thin|--tags|--prune) ;;
      --progress|--no-progress|--porcelain|--no-recurse-submodules) ;;
      --push-option|-o|--repo|--receive-pack|--exec) skip_next=1 ;;
      --push-option=*|-o*|--repo=*) ;;
      -*) ;; # unknown flag, skip (fail-open)
      *) positional+=("$arg") ;;
    esac
    i=$(( i + 1 ))
  done

  # Determine target branch(es)
  local -a targets=()
  if (( ${#positional[@]} <= 1 )); then
    # git push [remote] — pushes current branch
    local current
    current="$(get_current_branch "${git_repo_dir:-}")" || return 0
    [[ "$current" == "HEAD" ]] && return 0
    targets=("$current")
  else
    # git push <remote> <refspec>...
    local refspec target
    for refspec in "${positional[@]:1}"; do
      if [[ "$has_delete" == true ]]; then
        target="$refspec"
      elif [[ "$refspec" == *:* ]]; then
        target="${refspec#*:}"
      else
        target="${refspec#+}" # strip + force prefix
      fi
      target="${target#refs/heads/}" # strip refs/heads/ prefix
      # 'git push origin HEAD' (or '@') pushes the CURRENT branch — resolve it,
      # or a protected branch is reachable by naming it indirectly.
      if [[ "$target" == "HEAD" || "$target" == "@" ]]; then
        target="$(get_current_branch "${git_repo_dir:-}")" || continue
        [[ "$target" == "HEAD" ]] && continue # detached — no branch to protect
      fi
      [[ -n "$target" ]] && targets+=("$target")
    done
  fi

  # Check targets against protected branches
  local tgt
  for tgt in "${targets[@]}"; do
    if is_protected_branch "$tgt"; then
      deny_operation "BLOCKED: Cannot push to protected branch '$tgt'. Push to a feature branch instead."
    fi
  done
}

# Check one already-split command fragment for git branch protection violations.
# Called with an optional cd directory from a chained command, followed by the
# fragment's words as produced by shell_split.
# Calls deny_operation (exits the script) if blocked; returns 0 if allowed.
check_git_command() {
  local cd_dir="${1:-}"; shift
  local -a tokens=("$@")

  # Detect git through any wrapper prefix (sudo, env VAR=val, command, /usr/bin/git).
  cmd_word_index 'git' "${tokens[@]}" || return 0
  # Re-base the array on the git word so every index below still counts from 'git'.
  local -a _args=()
  (( ${#tokens[@]} > _cmd_idx + 1 )) && _args=("${tokens[@]:$((_cmd_idx + 1))}")
  tokens=(git ${_args[@]+"${_args[@]}"})

  # Rejoin for the two whole-string checks further down ('--hard', the branch
  # delete flags). IFS is restored immediately: the callees below run `read`.
  local git_portion _oldifs="$IFS"
  IFS=' '; git_portion="${tokens[*]}"; IFS="$_oldifs"

  # Find git subcommand (skip global flags between 'git' and subcommand)
  local git_subcmd="" git_subcmd_idx=0 git_dir=""
  local i
  for ((i=1; i<${#tokens[@]}; i++)); do
    case "${tokens[i]}" in
      -C) git_dir="${tokens[i+1]:-}"; (( ++i )) ;;          # capture -C target dir
      -c|--git-dir|--work-tree|--namespace) (( ++i )) ;;    # skip flag + its argument
      --git-dir=*|--work-tree=*|--namespace=*) ;;            # skip =form (no extra arg)
      -*) ;;                                                  # skip other flags
      *) git_subcmd="${tokens[i]}"; git_subcmd_idx=$i; break ;;
    esac
  done

  # Resolve which git repo this command targets
  # Priority: explicit -C flag > cd directory from chain > project root
  local git_repo_dir
  if [[ -n "$git_dir" ]]; then
    git_repo_dir="$(resolve_git_context "$git_dir")"
  elif [[ -n "$cd_dir" ]]; then
    git_repo_dir="$(resolve_git_context "$cd_dir")"
  else
    git_repo_dir="$(resolve_git_context "")"
  fi
  # Fail-open: if we can't determine a git repo, allow (no branches to protect)
  [[ -n "$git_repo_dir" ]] || return 0

  local current_branch
  case "$git_subcmd" in
    push)
      # Delegate to check_git_push with tokens after "git push"
      check_git_push "${tokens[@]:$((git_subcmd_idx+1))}"
      ;;
    commit|merge)
      current_branch="$(get_current_branch "$git_repo_dir")" || return 0
      [[ "$current_branch" == "HEAD" ]] && return 0
      if is_protected_branch "$current_branch"; then
        deny_operation "BLOCKED: Cannot '$git_subcmd' on protected branch '$current_branch'. Switch to a feature branch first."
      fi
      ;;
    reset)
      # Only block 'reset --hard' on protected branches
      [[ "$git_portion" == *--hard* ]] || return 0
      current_branch="$(get_current_branch "$git_repo_dir")" || return 0
      [[ "$current_branch" == "HEAD" ]] && return 0
      if is_protected_branch "$current_branch"; then
        deny_operation "BLOCKED: 'git reset --hard' on protected branch '$current_branch' is not allowed."
      fi
      ;;
    rebase)
      current_branch="$(get_current_branch "$git_repo_dir")" || return 0
      [[ "$current_branch" == "HEAD" ]] && return 0
      if is_protected_branch "$current_branch"; then
        deny_operation "BLOCKED: 'git rebase' on protected branch '$current_branch' is not allowed."
      fi
      ;;
    checkout)
      # Scan tokens after the subcommand for -b/-B flags (handles both "-b name" and "-bname")
      local co_flag="" co_target="" ci
      for ((ci=git_subcmd_idx+1; ci<${#tokens[@]}; ci++)); do
        case "${tokens[ci]}" in
          -b) co_flag="-b"; co_target="${tokens[ci+1]:-}"; break ;;
          -b*) co_flag="-b"; co_target="${tokens[ci]#-b}"; break ;;
          -B) co_flag="-B"; co_target="${tokens[ci+1]:-}"; break ;;
          -B*) co_flag="-B"; co_target="${tokens[ci]#-B}"; break ;;
        esac
      done
      # Allow 'git checkout -b' (create new branch, fails if exists — always safe)
      [[ "$co_flag" == "-b" ]] && return 0
      # 'git checkout -B <name>' force-resets a branch — block if target is protected
      if [[ "$co_flag" == "-B" ]]; then
        if [[ -n "$co_target" ]] && is_protected_branch "$co_target"; then
          deny_operation "BLOCKED: 'git checkout -B $co_target' would reset protected branch '$co_target'."
        fi
        return 0
      fi
      # Block 'git checkout -- <paths>' and 'git checkout .' on protected branches
      local has_discard=false
      for ((ci=git_subcmd_idx+1; ci<${#tokens[@]}; ci++)); do
        case "${tokens[ci]}" in
          --|.) has_discard=true; break ;;
        esac
      done
      [[ "$has_discard" == true ]] || return 0
      current_branch="$(get_current_branch "$git_repo_dir")" || return 0
      [[ "$current_branch" == "HEAD" ]] && return 0
      if is_protected_branch "$current_branch"; then
        deny_operation "BLOCKED: Discarding changes on protected branch '$current_branch' is not allowed."
      fi
      ;;
    restore)
      current_branch="$(get_current_branch "$git_repo_dir")" || return 0
      [[ "$current_branch" == "HEAD" ]] && return 0
      if is_protected_branch "$current_branch"; then
        deny_operation "BLOCKED: 'git restore' on protected branch '$current_branch' is not allowed."
      fi
      ;;
    switch)
      # Scan tokens after the subcommand for -c/-C flags (handles both "-c name" and "-cname")
      local sw_flag="" sw_target="" si
      for ((si=git_subcmd_idx+1; si<${#tokens[@]}; si++)); do
        case "${tokens[si]}" in
          -c) sw_flag="-c"; sw_target="${tokens[si+1]:-}"; break ;;
          -c*) sw_flag="-c"; sw_target="${tokens[si]#-c}"; break ;;
          -C) sw_flag="-C"; sw_target="${tokens[si+1]:-}"; break ;;
          -C*) sw_flag="-C"; sw_target="${tokens[si]#-C}"; break ;;
        esac
      done
      # Allow 'git switch -c' (create new branch, fails if exists — always safe)
      [[ "$sw_flag" == "-c" ]] && return 0
      # 'git switch -C <name>' force-resets a branch — block if target is protected
      if [[ "$sw_flag" == "-C" ]]; then
        if [[ -n "$sw_target" ]] && is_protected_branch "$sw_target"; then
          deny_operation "BLOCKED: 'git switch -C $sw_target' would reset protected branch '$sw_target'."
        fi
      fi
      return 0
      ;;
    branch)
      # Two destructive shapes, not one. Keying on the delete flags alone left
      # `git branch -f master HEAD~3` and `git branch -M feat master` free to
      # rewrite a protected branch's pointer — the same loss as a delete, and
      # the one way to do it that the Bash tool never had to ask about.
      #   delete:  -d/-D (also bundled with other short flags, e.g. -Df),
      #            --delete, --force-delete
      #   rewrite: -f/--force (force-create over an existing name), -m/-M/--move
      #            (rename onto one)
      local branch_op=""
      if [[ "$git_portion" =~ \ -[a-zA-Z]*[dD][a-zA-Z]*(\ |$)|\ --delete(\ |$)|\ --force-delete(\ |$) ]]; then
        branch_op=delete
      elif [[ "$git_portion" =~ \ -[a-zA-Z]*[fmM][a-zA-Z]*(\ |$)|\ --force(\ |$)|\ --move(\ |$) ]]; then
        branch_op=rewrite
      fi
      [[ -n "$branch_op" ]] || return 0
      # Check ALL non-flag arguments (git branch -d accepts multiple branch
      # names, and a rename's OLD name matters as much as its new one).
      local bi
      local -a bnames=()
      for ((bi=git_subcmd_idx+1; bi<${#tokens[@]}; bi++)); do
        [[ "${tokens[bi]}" == -* ]] && continue
        bnames+=("${tokens[bi]}")
      done
      # `git branch -f <name> <start-point>` writes only <name>; the start-point
      # is READ. Without this, creating an ordinary feature branch off master
      # ('git branch -f feature master') would be denied.
      if [[ "$branch_op" == rewrite && ! "$git_portion" =~ \ -[a-zA-Z]*[mM][a-zA-Z]*(\ |$)|\ --move(\ |$) ]]; then
        (( ${#bnames[@]} > 1 )) && bnames=("${bnames[0]}")
      fi
      local bname
      for bname in ${bnames[@]+"${bnames[@]}"}; do
        bname="${bname#refs/heads/}"
        if is_protected_branch "$bname"; then
          if [[ "$branch_op" == delete ]]; then
            deny_operation "BLOCKED: Cannot delete protected branch '$bname'."
          fi
          deny_operation "BLOCKED: 'git branch' would rewrite protected branch '$bname'. Use a feature branch instead."
        fi
      done
      ;;
    update-ref)
      # `git update-ref refs/heads/master <sha>` moves a branch pointer with no
      # branch subcommand in sight — and it works even on the CHECKED-OUT
      # branch, where 'git branch -f' refuses. Same destruction, different door.
      local ui uref=""
      for ((ui=git_subcmd_idx+1; ui<${#tokens[@]}; ui++)); do
        case "${tokens[ui]}" in
          # --stdin takes the refs on stdin, which this hook cannot read: nothing
          # to check, so fail open as everywhere else.
          --stdin) return 0 ;;
          -m) (( ++ui )) ;;   # reflog message + its argument
          -*) ;;
          *) uref="${tokens[ui]}"; break ;;
        esac
      done
      [[ -n "$uref" ]] || return 0
      if is_protected_branch "${uref#refs/heads/}"; then
        deny_operation "BLOCKED: 'git update-ref' would rewrite protected branch '${uref#refs/heads/}'."
      fi
      ;;
  esac
  return 0
}

# --- Command scanning (see header: COMMAND PARSING) ---
# Walk ONE command string: split it on the shell's operators, then run both
# Bash-side guards over every fragment. Recurses, depth-bounded, into the command
# string carried by `sh -c` / `bash -c` / `eval`.
#
# 'cd <dir>' targets are tracked here because two guards need them: git context
# in multi-repo workspaces, where Claude Code writes "cd <repo> && git ...", and
# the base a RELATIVE delete target resolves against. _cd_dir is deliberately a
# global — a cd persists across the operator that follows it, and into a nested
# `sh -c`, exactly as it does for the shell.
_cd_dir=""
_scan_depth=0
scan_command_string() {
  local _split="$1"
  local _subcmd _cd_tok word target nword skip_next
  local -a _frag

  # Pure bash, and '&' is one of the operators. The `sed 's/&&/\n/g; ...'` this
  # replaces emitted no newline for a LONE '&', so `true & rm <outside>` stayed
  # a single fragment that no anchored guard matched — both hard blocks were
  # one background operator away from being no-ops. (It also relied on GNU
  # sed's \n in a replacement, which inserts a literal 'n' on macOS/BSD, and
  # forked a process per command.)
  _split="${_split//&&/$'\n'}"
  _split="${_split//||/$'\n'}"
  _split="${_split//;/$'\n'}"
  _split="${_split//|/$'\n'}"
  _split="${_split//&/$'\n'}"

  while IFS= read -r _subcmd; do
    _subcmd="${_subcmd#"${_subcmd%%[![:space:]]*}"}"  # trim leading whitespace
    _subcmd="${_subcmd#\(}"                              # strip leading subshell paren
    _subcmd="${_subcmd%\)}"                              # strip trailing subshell paren

    # Peel leading shell keywords. `for f in *; do rm <outside>; done` splits
    # into a fragment beginning 'do rm ...' and `if x; then rm <outside>; fi`
    # into one beginning 'then rm ...' — neither of which the guards below saw,
    # so a loop or an if was enough to walk both of them past an unwanted delete
    # and past the protected-branch check.
    while :; do
      case "$_subcmd" in
        do|then|else|elif|fi|done|esac|in|'{'|'}'|'!') _subcmd="" ;;
        do\ *|then\ *|else\ *|elif\ *|if\ *|while\ *|until\ *|'{'\ *|'!'\ *)
          _subcmd="${_subcmd#* }" ;;
        *) break ;;
      esac
      _subcmd="${_subcmd#"${_subcmd%%[![:space:]]*}"}"
      [[ -n "$_subcmd" ]] || break
    done
    [[ -n "$_subcmd" ]] || continue

    # One quote-aware split per fragment, shared by all the gates below.
    shell_split "$_subcmd"
    (( ${#_words[@]} )) || continue
    _frag=("${_words[@]}")

    # Track 'cd <dir>' to resolve context for subsequent commands
    if [[ "${_frag[0]}" == cd ]]; then
      for _cd_tok in "${_frag[@]:1}"; do
        [[ "$_cd_tok" == -* ]] && continue
        _cd_dir="$_cd_tok"
        break
      done
      continue
    fi

    # `sh -c <string>` / `bash -c <string>` / `eval <words>` carry a whole
    # command inside ONE argument, which no walk over these tokens can reach —
    # so a single wrapper switched BOTH guards off at once. Hand the string back
    # to this function instead. Depth-bounded so a self-referential command
    # (`sh -c "sh -c ..."`) cannot spin, and shallow because real commands nest
    # once, if at all.
    if unwrap_shell_c "${_frag[@]}"; then
      if (( _scan_depth < 4 )); then
        _scan_depth=$(( _scan_depth + 1 ))
        scan_command_string "$_unwrapped"
        _scan_depth=$(( _scan_depth - 1 ))
      fi
      continue
    fi

    # Git branch protection (feature branches allowed, protected branches blocked)
    check_git_command "$_cd_dir" "${_frag[@]}"

    # Delete protection (rm/rmdir outside project or precious unversioned).
    # cmd_word_index sees through wrapper prefixes — a pipe hands the post-'|'
    # fragment here on its own, so `find ... | xargs -n 1 rm <path>` and
    # `sudo rm <path>` have to be recognized as deletes just like a bare `rm`.
    if cmd_word_index 'rm|rmdir' "${_frag[@]}"; then
      skip_next=""
      for word in "${_frag[@]:$((_cmd_idx + 1))}"; do
        if [[ -n "$skip_next" ]]; then skip_next=""; continue; fi
        # Flags, and the placeholder/terminator tokens of an xargs or find
        # invocation — none of them name a file.
        case "$word" in -*|'{}'|'+'|';'|'') continue ;; esac
        # Neither does a redirection: `rm <in-project> > /dev/null` was denied
        # for deleting '/dev/null', with no prompt and no way to override it.
        if is_redirection "$word"; then skip_next="$_redir_takes_arg"; continue; fi
        # Resolve a RELATIVE target against the chain's `cd`, not against this
        # hook's own working directory. `cd /etc && rm passwd` otherwise
        # normalized to <project>/passwd and read as an IN-project delete, while
        # the shell removed /etc/passwd — the tracked cd was right there, it
        # just never reached this gate. A relative cd resolves against the
        # project root, as it does in resolve_git_context.
        target="$word"
        if [[ -n "$_cd_dir" ]] && ! is_absolute_path "$target"; then
          if is_absolute_path "$_cd_dir"; then
            target="$_cd_dir/$target"
          else
            target="$root/$_cd_dir/$target"
          fi
        fi
        # Claude's own auto-memory store and session scratchpad are writable AND
        # prunable by design, so deletes there are allowed like writes — via the
        # SAME ladder the write gate uses. Everything else outside the project
        # root is hard-blocked. Normalize once and reuse: the two gates below
        # would otherwise resolve the same word twice, two forks apiece.
        nword="$(normalize "$target")"
        if ! is_exempt_out_of_project_n "$nword"; then
          deny_operation "BLOCKED: Cannot delete '$word' — outside project root."
        fi
        # Precious file protection: block deletion of sensitive unversioned files.
        # Recoverable ones (backups, IDE scratch) are excluded — see
        # is_recoverable_precious: a deny here could never be overridden.
        if [[ -e "$target" ]] && is_inside_project_n "$nword" \
           && is_precious "$target" && ! is_recoverable_precious "$target" \
           && ! is_git_tracked "$target"; then
          deny_operation "BLOCKED: '$(basename "$word")' is a precious file not tracked by git. Deletion denied."
        fi
      done
    fi
  done <<< "$_split"
  return 0
}

# --- Extract tool_name ---
# Fail-open: if tool_name cannot be extracted, allow rather than block
[[ "$input" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
tool_name="${BASH_REMATCH[1]}"

case "$tool_name" in
  Edit|MultiEdit|Write)
    # Fail-open: if file_path cannot be extracted, allow rather than block
    [[ "$input" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
    filepath="${BASH_REMATCH[1]}"
    guard_out_of_project_write "$filepath" "File" "write"
    # Precious file protection: prompt before modifying sensitive unversioned files
    if [[ -e "$filepath" ]] && is_precious "$filepath" && ! is_git_tracked "$filepath"; then
      ask_permission "File '$(basename "$filepath")' is a precious file not tracked by git. Changes may be permanent. Allow this write?"
    fi
    exit 0
    ;;
  NotebookEdit)
    # Fail-open: if notebook_path cannot be extracted, allow rather than block
    [[ "$input" =~ \"notebook_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
    filepath="${BASH_REMATCH[1]}"
    guard_out_of_project_write "$filepath" "Notebook" "edit"
    # Precious file protection: prompt before modifying sensitive unversioned notebooks
    if [[ -e "$filepath" ]] && is_precious "$filepath" && ! is_git_tracked "$filepath"; then
      ask_permission "File '$(basename "$filepath")' is a precious file not tracked by git. Changes may be permanent. Allow this edit?"
    fi
    exit 0
    ;;
  Bash)
    # Fail-open: if command cannot be extracted, allow rather than block.
    # The value is a JSON string, so the match must walk over escaped quotes
    # ([^"\]|\\.) — stopping at the first \" truncated the command and silently
    # skipped every guard for anything as ordinary as `git commit -m "msg"`.
    _bash_cmd_re='"command"[[:space:]]*:[[:space:]]*"(([^"\]|\\.)*)"'
    [[ "$input" =~ $_bash_cmd_re ]] || exit 0
    cmd="${BASH_REMATCH[1]}"
    # Undo the JSON escapes so the guards see what the shell will run. \001
    # shields literal backslashes from the later passes; cmd never reaches the
    # emitted JSON, so the sentinel cannot leak into output.
    cmd="${cmd//\\\\/$'\001'}"
    cmd="${cmd//\\\"/\"}"
    cmd="${cmd//\\\//\/}"
    cmd="${cmd//\\n/$'\n'}"
    cmd="${cmd//\\r/$'\r'}"
    cmd="${cmd//\\t/$'\t'}"
    cmd="${cmd//$'\001'/\\}"

    # --- Git branch protection + Delete protection ---
    # Both live in scan_command_string, which splits the string on the shell's
    # operators and checks each fragment — so chained commands like
    # "cd /repo && git commit" and "cd /tmp && rm file" are covered, as is a
    # command nested inside `sh -c`.
    scan_command_string "$cmd"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
