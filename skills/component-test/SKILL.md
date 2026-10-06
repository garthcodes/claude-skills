---
name: component-test
description: Generate or review the RSpec spec for one ViewComponent, given its path. Thin command over viewcomponent-test-expert, which holds the patterns. Use when the user runs /component-test or hands over a single app/components or spec/components file to test.
argument-hint: '<app/components/... or spec/components/... path> [review|write]'
---

# Component Test

Write or review the spec for the component at `$ARGUMENTS`.

1. Read `.claude/skills/rspec-test-expert/test-quality.md` and
   `.claude/skills/viewcomponent-test-expert/SKILL.md`. Together they hold the yardstick, the app's
   component patterns, and the proof steps.
2. Resolve the paths: the component `.rb`, its `.html.erb` (or inline template, or sidecar
   directory), and `spec/components/<same path>_spec.rb`.
3. **Spec missing → write mode.** List what the template renders for each input and state, then
   write one example per state or decision as the expert skill describes.
   **Spec present → review mode.** Follow the review workflow in `test-quality.md`.
4. Prove it: the spec is green with `TEST_ENV_NUMBER=<n>`, coverage of `.rb` and `.html.erb` shows
   no `lost_lines`, and 2–5 probes on the template's conditionals are all KILLED. Lint with
   `bin/standardrb`.
5. Report what changed, lines and examples before→after, coverage, probes, and findings. Never edit
   the component itself; a suspected bug goes in findings.
