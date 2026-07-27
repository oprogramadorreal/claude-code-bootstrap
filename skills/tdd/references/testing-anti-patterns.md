# Testing Anti-Patterns

Read when writing or reviewing tests — especially before adding mocks.

**Test what the code does, not what the mocks do.** Mocks isolate; they are never the thing under test. Four questions catch nearly every violation.

### 1. "Am I asserting on the mock or on the code under test?"

- Bad: `expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument()` — proves the mock renders, not that the page works.
- Good: don't mock the sidebar — `expect(screen.getByRole('navigation')).toBeInTheDocument()`.

### 2. "Does this test depend on side effects I've mocked away?"

Before mocking, know what the real method does and whether the test depends on any of it. If it does, mock at a lower level or use the real implementation.

- Bad: mocking `ConfigManager.saveConfig` in a duplicate-server test — the duplicate check reads the config the mock never wrote, so the expected error never fires.
- Good: mock only the slow network client; let the config write happen for real.

### 3. "Can this test use the real implementation?"

Only mock what you must: external services (APIs, databases), non-deterministic behavior (time, randomness), and slow I/O. If the real code is fast and deterministic, use it.

Over-mocking shows up as mock setup longer than the test logic, tests that break when the mock changes while the real code is fine, mocks of internal modules rather than external services, mock data missing fields the real API returns, and mocks added "just to be safe" that nobody can justify.

### 4. "Am I verifying through the public interface or a backdoor?"

- Bad: `db.query('SELECT * FROM users WHERE name = ?', ['Alice'])` to check that `createUser` saved — couples the test to a storage decision; a schema change breaks it while the code still works.
- Good: `getUser(user.id)` — read the result back through the API the system exposes. If no interface exists to read it back, that is a design gap.

## Also

A method that exists only for tests to call (`destroy()`, `reset()`) belongs in test utilities, not on the production class — it pollutes the public API and is dangerous if something calls it for real.
