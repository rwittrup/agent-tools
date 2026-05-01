---
name: create-scenario-file
description: Create text-conversation scenario YAML files to test ANET agent behavior changes. Use when the user says they need a scenario file to test changes, wants to add test scenarios, or needs to validate agent behavior with text-conversation. Covers intent alignment, scenario YAML format, post_call_analysis assertions, and Engineering PD intent management.
---
# Create Scenario File
Create a `text-conversation` scenario YAML file to test ANET agent behavior changes. This skill ensures scenarios are aligned with configured intents in the target dispatch center.
## Quick Reference Checklist
- [ ] Read the changes being tested to understand what behaviors need scenarios
- [ ] **MANDATORY**: Run `list_intents.rb` and review the output (ask user to run if Docker access is needed)
- [ ] Decide per scenario: match existing intent, create new intent, or target `unconfigured_intent`
- [ ] **MANDATORY if intents missing**: Run `ensure_intent.rb` to create needed intents, then re-run `list_intents.rb` to verify
- [ ] Write scenario YAML with `post_call_analysis` assertions (only after intents are verified)
- [ ] Provide run command to the user (TUI requires interactive terminal)
---
## Step 1: Understand What to Test
Read the code changes and identify distinct behaviors that need validation. Each behavior maps to one or more scenarios. Common categories:
- **New constraint or prompt change** — scenario that triggers the specific condition
- **New tool added to a phase** — scenario where the caller invokes that tool during the relevant phase
- **Bug fix** — scenario that reproduces the original bug
- **Feature flag behavior** — scenarios for each flag state
---
## Step 2: Check Configured Intents (MANDATORY)
**You MUST run this step before writing any scenario.** Do not skip it. Do not assume intents exist based on other scenario files — intents can be added or removed at any time.
1. Create the helper script if it doesn't exist.
2. Run it with `just api rails runner tmp/scripts/list_intents.rb` using `required_permissions: ["all"]` (Docker access requires sandbox bypass).
3. Review the output before proceeding to Step 3 or Step 4.
### Create the helper script (if it doesn't exist)
Check if `apps/ruby/api/tmp/scripts/list_intents.rb` exists. If not, create it:
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Usage: just api rails runner tmp/scripts/list_intents.rb
# Lists all active, enabled intents for Engineering PD with descriptions.
DISPATCH_CENTER_ID = "24ae60ce-482f-45ac-9e31-2b83913d8d2a"
dc = DispatchCenter.find(DISPATCH_CENTER_ID)
config = dc.nonemergency_center_config
intents = Nonemergency::CenterIntent
  .where(nonemergency_center_config: config)
  .active
  .enabled_only
  .order(:intent_name)
parents = intents.where(parent_intent_id: nil)
children = intents.where.not(parent_intent_id: nil)
puts "=" * 80
puts "Configured Intents for #{dc.name} (#{DISPATCH_CENTER_ID})"
puts "=" * 80
puts ""
parents.each do |p|
  kids = children.select { |c| c.parent_intent_id == p.id }
  puts "#{p.intent_name} (#{p.id})"
  puts "  Description: #{p.description.to_s.truncate(100)}"
  puts "  Questions: #{p.additional_questions.present? ? 'yes' : 'none'}"
  kids.each do |c|
    puts "  └─ #{c.intent_name} (#{c.id})"
    puts "     Description: #{c.description.to_s.truncate(90)}"
  end
  puts ""
end
puts "Total: #{parents.count} parent intents, #{children.count} child intents"
```
### Run the script
Run the script directly (requires `required_permissions: ["all"]` for Docker access):
```bash
just api rails runner tmp/scripts/list_intents.rb
```
If the Rails API container is not running, start it first with `just api run` (backgrounded) and retry.
**STOP HERE** — do not proceed to Step 3 or Step 4 until you have reviewed the intent list output. Review the output and note which intents exist. For each scenario you plan to create, decide:
1. **Match existing intent** — the scenario describes something that maps to a configured intent
2. **Create new intent** — the scenario needs an intent that doesn't exist yet (Step 3). Use this when testing a feature that requires specific intent characteristics (e.g., child intents, specific question types) that no existing intent provides.
3. **Target `unconfigured_intent`** — the scenario intentionally does NOT match any intent (skip Step 3)
Prefer creating intents when the existing set does not cover the test case. Do not limit scenarios to only existing intents — create what you need to thoroughly test the feature.
---
## Step 3: Create or Update Intents (MANDATORY when intents are missing)
**Skip this step ONLY if every scenario either matches an existing intent (confirmed in Step 2 output) or is meant to trigger `unconfigured_intent`.**
If a scenario needs an intent that doesn't exist in the Step 2 output, you MUST create it before writing the scenario YAML. Do not write scenarios that reference intents you haven't verified exist.
1. Create the helper script if it doesn't exist.
2. Edit the `INTENTS` array with the needed intents.
3. Run: `just api rails runner tmp/scripts/ensure_intent.rb` (with `required_permissions: ["all"]`).
4. Re-run `list_intents.rb` to verify the intents were created.
### Create the helper script (if it doesn't exist)
Check if `apps/ruby/api/tmp/scripts/ensure_intent.rb` exists. If not, create it:
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Usage: just api rails runner tmp/scripts/ensure_intent.rb
# Creates or updates intents needed for scenario testing.
# Edit the INTENTS array below before running.
DISPATCH_CENTER_ID = "24ae60ce-482f-45ac-9e31-2b83913d8d2a"
INTENTS = [
  # Add intents here. Example:
  # {
  #   name: "My Intent Name",
  #   description: "Caller is reporting X situation.",
  #   additional_questions: "What is the address?\nWhen did this happen?",
  #   caller_information: "Information to share with the caller.",
  #   parent_name: nil,  # Set to parent intent_name for child intents
  # },
]
dc = DispatchCenter.find(DISPATCH_CENTER_ID)
config = dc.nonemergency_center_config
INTENTS.each do |spec|
  parent_id = nil
  if spec[:parent_name]
    parent = Nonemergency::CenterIntent.find_by!(
      nonemergency_center_config: config,
      intent_name: spec[:parent_name],
      deleted: false,
    )
    parent_id = parent.id
  end
  intent = Nonemergency::CenterIntent.find_or_initialize_by(
    nonemergency_center_config: config,
    intent_name: spec[:name],
  )
  intent.assign_attributes(
    description: spec[:description],
    additional_questions: spec[:additional_questions],
    caller_information: spec[:caller_information],
    parent_intent_id: parent_id,
    enabled: true,
    deleted: false,
  )
  was_new = intent.new_record?
  intent.save!
  puts "#{was_new ? 'CREATED' : 'UPDATED'} intent: #{intent.intent_name} (#{intent.id})"
end
```
### Usage
1. Edit the `INTENTS` array with the intents your scenarios need
2. Run: `just api rails runner tmp/scripts/ensure_intent.rb`
3. Verify: `just api rails runner tmp/scripts/list_intents.rb`
---
## Step 4: Write the Scenario YAML
Create the file at `apps/go/call-handler/cmd/text-conversation/feature_scenarios/<feature-name>.yaml`.
### Template
```yaml
# <Category/Feature>: <what this tests>
#
# <Brief explanation of the behavior being validated and why.>
#
# Usage: just call-handler scenario cmd/text-conversation/feature_scenarios/<feature-name>.yaml
dispatch_center_id: "24ae60ce-482f-45ac-9e31-2b83913d8d2a"
defaults:
  total: 1
  concurrent: 1
  language: "en"
  skip_send_call_ended_data: true  # set false if post-call scoring is needed
tests:
  - name: "Descriptive test name"
    scenario: |
      You are simulating a caller to a non-emergency IVR.
      Do not volunteer details unless asked.
      On your first turn, say: "<initial caller statement>"
      <additional instructions for caller behavior>
    post_call_analysis:
      pass_conditions:
        - <condition that must be true for the test to pass>
      fail_conditions:
        - <condition that indicates the test failed>
```
### Scenario Writing Rules
1. **Be explicit about caller behavior** — tell the simulated caller exactly what to say and when
2. **Use `On your first turn, say:` pattern** — establishes the opening statement
3. **Include `Do not volunteer details unless asked`** — prevents the caller from over-sharing
4. **Provide specific responses** — e.g., `When asked for your phone number, say: "555-123-4567"`
5. **Add `CRITICAL RULE` blocks** for behavior the caller must not deviate from
6. **Set `skip_send_call_ended_data: true`** for test scenarios that shouldn't affect Ruby state
### Post-Call Analysis Rules
- **`pass_conditions`**: What must be true in the conversation timeline for the test to pass
- **`fail_conditions`**: What indicates the agent behaved incorrectly
- Reference timeline events by type: `tool_call`, `agent_transcript`, `user_transcript`
- Reference tool names: `intent_discovered`, `unconfigured_intent`, `intent_end`, `change_language`, `call_complete_function`, etc.
### Language Testing
For multilingual scenarios, set `language` at the test level:
```yaml
  - name: "Spanish caller scenario"
    language: "es"
    scenario: |
      Eres un llamante que llama a la línea de no emergencia.
      En tu primer turno, di: "Quiero reportar un vehículo abandonado."
```
### Unconfigured Intent Scenarios
When testing that the agent correctly escalates to `unconfigured_intent`, the scenario should describe something that does NOT match any configured intent:
```yaml
  - name: "Caller request does not match any intent"
    scenario: |
      You are calling the non-emergency line.
      On your first turn, say: "<something that doesn't match configured intents>"
      If the agent asks clarifying questions, stay on topic but do not describe
      anything that matches a configured intent.
    post_call_analysis:
      pass_conditions:
        - The timeline contains a tool_call event with name "unconfigured_intent".
      fail_conditions:
        - The agent matched a configured intent via intent_discovered.
        - The agent asked more than four clarifying questions without escalating.
```
**Do NOT create or update intents for these scenarios.** The whole point is that no intent matches.
---
## Step 5: Run and Verify
**Important:** The text-conversation tool uses a TUI (terminal UI) that requires an interactive terminal. Provide the run command to the user:
```bash
# From repo root
just call-handler scenario cmd/text-conversation/feature_scenarios/<feature-name>.yaml
# Or from apps/go/call-handler/
just scenario cmd/text-conversation/feature_scenarios/<feature-name>.yaml
```
After the user runs it, check the output files in `apps/go/call-handler/cmd/text-conversation/output/` for:
   - `PASS` / `FAIL` from post_call_analysis
   - Timeline events showing expected tool calls
   - Agent transcripts showing expected behavior
---
## Common Mistakes to Avoid
1. **Writing a scenario without running `list_intents.rb` first** — this is the #1 mistake. The scenario might not match any intent, causing `unconfigured_intent` when you expected `intent_discovered`. You MUST run the script and review the output before writing any scenario YAML. Do not assume intents exist from other files or prior knowledge
2. **Creating intents for `unconfigured_intent` scenarios** — defeats the purpose
3. **Overly vague caller instructions** — the simulated caller will improvise unpredictably
4. **Missing `post_call_analysis`** — without assertions, there's no automated pass/fail
5. **High concurrency** — keep `concurrent: 1` to avoid API rate limiting
6. **Wrong `skip_send_call_ended_data` setting** — set to `true` for quick behavior validation where you only need timeline/post_call_analysis results; set to `false` (or omit) when you need post-call scoring via the Ruby API (e.g., Coval evaluation, `ScoreCall`). Ask the user if unclear
---
## File Quick Reference
| File | Purpose |
|------|---------|
| `apps/go/call-handler/cmd/text-conversation/README.md` | Full text-conversation tool documentation |
| `apps/go/call-handler/cmd/text-conversation/feature_scenarios/` | Feature-specific scenario files |
| `apps/go/call-handler/cmd/text-conversation/scenarios.example.yaml` | Example scenario format |
| `apps/ruby/api/tmp/scripts/list_intents.rb` | Helper: list configured intents |
| `apps/ruby/api/tmp/scripts/ensure_intent.rb` | Helper: create/update intents |
| `.agent/skills/rails-runner-data-access/SKILL.md` | Rails runner patterns and data model reference |
