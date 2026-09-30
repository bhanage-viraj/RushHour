---
name: Bug report for developers and AI
about: Describe one reproducible problem with evidence and a clear definition of done.
title: "bug(<screen>): <observable symptom>"
labels: bug
assignees: ''
---

<!-- One independently fixable problem per issue. Write "unknown" instead of guessing.
     Attach screenshots/videos to GitHub: local paths are not accessible to another AI. -->

**Classification:** `bug`

**PR description:** <One sentence describing the intended behavior after the fix.>

**PR Related:** <Links to related fixes, or none.>

---

## Problem

**Actual:**
<What the user sees, including exact labels or error text.>

**Expected:**
<What should happen for the same input and action.>

**Impact:**
<What the user cannot do, or what becomes confusing.>

**Evidence status:**
<User reported / screenshot confirmed / reproduced / code confirmed. Distinguish these.>

---

## Environment

- Device and iOS version: <...>
- App version and build: <...>
- Source commit, if known: <...>
- Screen, orientation, appearance and text size: <...>
- Relevant permissions or settings: <...>
- Frequency: <Always / X out of Y attempts / unknown>

---

## Reproduction

**Preconditions:**
<Session state, selected apps, camera, media orientation, or template needed.>

1. <Exact action.>

2. <Exact action. Include timing or pasted input when relevant.>

3. <Where the actual result appears.>

**Minimal example:**
<A reason string, sample media properties, or timer value. Use non-sensitive data.>

---

## Evidence

<Attach images/video/logs here. Explain what each attachment demonstrates.>

---

## Investigation leads

- Code entry points: <Verified paths and functions, preferably commit permalinks.>
- Confirmed facts: <What was actually inspected or tested.>
- Hypotheses: <Possible causes, explicitly unverified.>
- Related issue search: <Results and links; distinguish related issues from duplicates.>
- Time-complexity check: <Relevant loop/concurrency/collection shape, or no smell found.>
- Open questions: <Missing evidence or product decisions needed before implementation.>

---

## Scope

<Smallest behavior that must change, plus specific adjacent behavior to preserve.>

---

## Acceptance

- [ ] <Observable outcome for the original reproduction.>
- [ ] <Relevant edge case or sibling entry point.>
- [ ] Record the tested device, iOS version, build, and evidence of the result.

---

## Instructions for the implementing AI

Reproduce against the current branch before editing. Trace the entry point, all callers,
and the shared state involved. Treat hypotheses as leads, not established root causes.
Resolve open product questions before changing behavior. Make the smallest fix in the
shared path, verify the acceptance criteria, and report anything not verified.
