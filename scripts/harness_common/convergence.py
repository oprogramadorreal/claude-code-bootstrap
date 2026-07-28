"""Convergence detection for the coverage-paired orchestrator (unit-test + refactor)."""


def _flag(output, key):
    """Read one convergence flag out of untrusted subagent JSON.

    These flags decide whether the run STOPS, so they are read strictly: only a
    real boolean, or a string spelling one, can converge. Nothing coerces types
    at the parse boundary — ``parse_harness_output`` checks that the payload is
    a dict and no more — and a subagent emits the string ``"false"`` as readily
    as the literal. Read raw, ``"false"`` is truthy in Python, so the run
    terminated on cycle 1 reporting a coverage plateau that never happened.

    Anything unrecognized means "keep going", which the cycle cap already
    bounds. This is the same untrusted-scalar class ``_finite_number`` guards
    for the coverage numbers, applied to the flags that end the run.
    """
    value = output.get(key, False)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("true", "yes")
    return False


def check_unit_test_convergence(unit_test_output):
    """Check if the unit-test phase signals convergence.

    Returns (converged: bool, reason: str or None).
    """
    no_new_tests = _flag(unit_test_output, "no_new_tests")
    no_untestable = _flag(unit_test_output, "no_untestable_code")
    no_coverage = _flag(unit_test_output, "no_coverage_gained")

    if no_new_tests and no_untestable:
        return True, "No new tests and no untestable code — coverage plateau"
    if no_new_tests and no_coverage:
        return True, "No new tests and no coverage gained"
    return False, None


def check_refactor_convergence(refactor_output):
    """Check if the refactor phase signals convergence.

    Returns (converged: bool, reason: str or None).
    """
    no_findings = _flag(refactor_output, "no_new_findings")
    no_actionable = _flag(refactor_output, "no_actionable_fixes")

    if no_findings:
        return True, "Refactor found no testability issues"
    if no_actionable:
        return True, "Refactor found issues but none had actionable fixes"
    return False, None


def check_coverage_plateau(coverage_history, min_consecutive=2):
    """Check if coverage has plateaued (zero delta for consecutive cycles).

    Returns (plateaued: bool, reason: str or None).
    """
    if len(coverage_history) < min_consecutive:
        return False, None

    recent = coverage_history[-min_consecutive:]
    if all(entry.get("delta") == 0 for entry in recent):
        return True, (f"Zero coverage gain for {min_consecutive} consecutive cycles")
    return False, None
