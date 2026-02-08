---
name: cost-estimate
description: >
  Estimates Anthropic API costs for operations in this repo.
  Analyzes execution paths, model usage, and suggests optimizations
  to reduce spend. Reports confidence levels for each estimate.
argument-hint: "[path, 'skills', 'hooks', or empty for full analysis]"
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(wc *), Bash(source *), Bash(python -c *)
---

# Cost Estimation Analysis

Analyze this repository for Anthropic API cost drivers and provide actionable estimates with confidence levels.

## Pricing Reference (USD per million tokens)

Use these rates for all calculations:

| Model | Input | Output | Prompt Cache Write | Prompt Cache Read |
|-------|-------|--------|--------------------|-------------------|
| Claude Opus 4 | $15.00 | $75.00 | $18.75 | $1.50 |
| Claude Sonnet 4 | $3.00 | $15.00 | $3.75 | $0.30 |
| Claude Haiku 3.5 | $0.80 | $4.00 | $1.00 | $0.08 |

**Extended thinking surcharges** (if applicable):
- Opus 4 extended thinking: $15.00 input / $75.00 output (same rate)
- Sonnet 4 extended thinking: $3.00 input / $15.00 output (same rate)

**Batch API discount**: 50% off all models (if applicable)

## Token Estimation Heuristics

Use these rules of thumb when estimating token counts:

- **1 token ≈ 4 characters** of English text or code
- **1 line of code ≈ 10-15 tokens** (average, including whitespace and syntax)
- **System prompts**: Claude Code system prompt ≈ 5,000-10,000 tokens
- **Tool definitions**: Each tool adds ~200-500 tokens to context
- **SKILL.md files**: Measure directly — these are injected as prompts
- **CLAUDE.md**: Measure directly — loaded into every conversation turn

## Confidence Levels

Assign one of these to every estimate:

| Level | Meaning | When to Use |
|-------|---------|-------------|
| **HIGH** | ±20% accuracy | Direct API calls with known parameters, measurable file sizes, fixed prompts |
| **MEDIUM** | ±50% accuracy | Estimated from patterns, variable-length inputs, typical usage assumptions |
| **LOW** | Order-of-magnitude | Rough estimates, user-behavior-dependent, highly variable workloads |

## Analysis Scope

Based on the argument provided:

- **No argument / full**: Run all analysis sections below
- **`skills`**: Focus only on skill cost analysis (Section 2)
- **`hooks`**: Focus only on hook cost analysis (Section 3)
- **A file or directory path**: Analyze that specific code for API call patterns (Section 1)

## Analysis Sections

### Section 1: Direct API Usage in Source Code

Search the codebase for direct Anthropic API calls:

```
Patterns to search for:
- import anthropic / from anthropic
- client.messages.create / client.completions.create
- anthropic.Anthropic() / anthropic.AsyncAnthropic()
- Any HTTP calls to api.anthropic.com
- Environment variables: ANTHROPIC_API_KEY
- Claude SDK agent patterns: Agent(), Runner.run()
```

For each API call site found:

1. **Identify the model** being used (or default)
2. **Measure input size**: Calculate tokens from prompt templates, system messages, injected context
3. **Measure expected output size**: Look at max_tokens parameter or estimate from usage
4. **Check for streaming**: Streaming doesn't change cost but affects perceived latency
5. **Check for caching**: Look for prompt caching headers or cache_control blocks
6. **Check for batching**: Look for batch API usage
7. **Estimate frequency**: How often is this call made per user action, per hour, per day?
8. **Calculate per-call cost**: `(input_tokens × input_rate + output_tokens × output_rate) / 1,000,000`

Report format for each call site:

```
[FILE:LINE] model=claude-sonnet-4-20250514 confidence=HIGH
  Input:  ~2,400 tokens (system: 800, user: 1,200, context: 400)
  Output: ~500 tokens (max_tokens=1024, typical ~500)
  Cost per call: $0.0147
  Caching: None detected → OPTIMIZATION OPPORTUNITY
  Frequency: ~10 calls/session → $0.147/session
```

### Section 2: Claude Code Skill Costs

For each skill defined in `.claude/skills/`:

1. **Read the SKILL.md file** and count its tokens (this becomes part of the prompt)
2. **Check `disable-model-invocation`**: If true, the skill runs without an API call — cost is $0
3. **Identify sub-skill calls**: Skills like `/check` invoke other skills — sum their costs
4. **Estimate tool call rounds**: Each tool call in a skill = 1 API round-trip
   - Simple skills (lint, test): 2-5 rounds typically
   - Complex skills (review, ship): 5-15 rounds typically
   - Orchestrating skills (check): Sum of sub-skills
5. **Estimate model tier**: Skills default to the conversation's model unless overridden
6. **Calculate CLAUDE.md overhead**: CLAUDE.md content is included in every API call

For each skill, produce:

```
/skill-name                           confidence=MEDIUM
  Skill prompt size: ~X tokens
  CLAUDE.md overhead: ~Y tokens per round
  Estimated rounds: N tool calls
  Model: [opus/sonnet/haiku] (conversation default)
  Est. cost per invocation: $X.XX
  Optimization potential: [HIGH/MEDIUM/LOW/NONE]
```

### Section 3: Hook Costs

Analyze `.claude/settings.json` for hooks that trigger model calls:

1. **PostToolUse hooks**: Check if any use `"type": "prompt"` (triggers a model call)
2. **Stop hooks**: Check for prompt-type hooks (these call a model at conversation end)
3. **PreToolUse hooks**: Check for prompt-type hooks
4. **Command hooks**: These run bash scripts — no API cost unless the script calls the API

For prompt-type hooks:
- Identify the model used (e.g., `"model": "haiku"`)
- Estimate the prompt size (the hook prompt + context passed to it)
- Estimate frequency (how often the triggering event occurs)

```
Hook: Stop → review prompt                confidence=MEDIUM
  Model: haiku
  Trigger: Every conversation end
  Est. tokens: ~1,500 input, ~200 output
  Cost per trigger: $0.002
  Frequency: ~1x per session → $0.002/session
```

### Section 4: Implicit Claude Code Costs

These are costs inherent to using Claude Code interactively:

1. **Conversation context growth**: Each message adds to the context window
   - Estimate: context grows ~500-2,000 tokens per exchange
   - After 20 exchanges: ~10,000-40,000 tokens of context per call
   - This means later calls in a session cost more than earlier ones

2. **Auto-summarization**: When context exceeds limits, Claude Code summarizes
   - This is an additional API call (typically sonnet-tier)
   - Triggered roughly every 50-100 exchanges

3. **File reads injected into context**: Each `Read` tool result adds file content as tokens
   - Large files (>500 lines) add 5,000-15,000+ tokens per read

4. **Agent/Task spawning**: Each `Task` tool call creates a sub-agent with its own context
   - Sub-agents inherit system prompt overhead
   - Parallel agents multiply costs

### Section 5: Workflow Cost Profiles

Estimate costs for common developer workflows in this project:

| Workflow | Description | Estimate |
|----------|-------------|----------|
| Quick fix | Edit 1 file, run tests | ~$X.XX |
| Feature development | Multi-file changes, review, test | ~$X.XX |
| Full validation (`/check`) | Lint + test + review + docs | ~$X.XX |
| Ship (`/ship`) | Commit + PR + merge | ~$X.XX |
| Code review (`/review`) | Review recent changes | ~$X.XX |
| Cost estimate (`/cost-estimate`) | This skill | ~$X.XX |

## Optimization Recommendations

After completing the analysis, provide specific recommendations grouped by impact:

### Model Tier Optimization

For each API call or skill, evaluate whether a cheaper model could handle it:

- **Downgrade candidates**: Tasks that are formulaic, low-creativity, or classification-based
  - Linting analysis → haiku
  - Commit message generation → haiku
  - Simple code generation from clear specs → sonnet
  - Hook prompts → haiku (already done for Stop hook — verify others)
- **Keep current tier**: Tasks requiring deep reasoning, complex refactoring, security analysis

Format:
```
RECOMMENDATION: Downgrade [operation] from [current] to [suggested]
  Savings: $X.XX per invocation (~XX% reduction)
  Risk: [LOW/MEDIUM/HIGH] — [brief justification]
```

### Caching Opportunities

Identify where prompt caching would help:

- **Static system prompts** reused across calls → cache_control: ephemeral
- **CLAUDE.md content** (same every call) → cacheable
- **Skill prompts** (same every invocation) → cacheable
- **Large code files** read repeatedly → cacheable

```
RECOMMENDATION: Enable prompt caching for [component]
  Cache-eligible tokens: ~X,XXX
  Savings per call: $X.XX (cache read vs. full input)
  Break-even: X calls (cache write cost amortized)
```

### Persistence / Memoization

Identify API calls whose results could be stored to avoid re-computation:

- **Code review results**: Cache review findings, invalidate on file change
- **Test analysis**: Don't re-analyze passing tests
- **Documentation checks**: Cache results per file hash
- **Repeated questions**: If the same context is queried multiple times

```
RECOMMENDATION: Persist results for [operation]
  Storage: [file/database/cache]
  Invalidation: [on file change / TTL / manual]
  Est. savings: $X.XX per duplicate avoided
```

### Batching Opportunities

Identify where the Batch API (50% discount) could be used:

- Non-interactive analysis tasks
- Bulk code review across many files
- Documentation generation
- Any operation where results aren't needed in real-time

### Work Unit Optimization

Suggest restructuring units of work to reduce total API costs:

- **Combine small operations**: Instead of N separate API calls, combine into 1 call with multiple instructions
- **Reduce round-trips**: Provide more context upfront to reduce back-and-forth
- **Limit file reads**: Read only necessary portions of large files (use offset/limit)
- **Scope narrowly**: Target specific files/functions instead of full-project operations

## Output Format

```
═══════════════════════════════════════════════════
            COST ESTIMATION REPORT
═══════════════════════════════════════════════════
Project: [project name from pyproject.toml]
Analysis scope: [full / skills / hooks / path]
Model rates as of: 2025 (verify at anthropic.com/pricing)

───────────────────────────────────────────────────
1. DIRECT API USAGE
───────────────────────────────────────────────────
[Results from Section 1, or "No direct API calls found"]

───────────────────────────────────────────────────
2. SKILL COSTS
───────────────────────────────────────────────────
[Table of skills with per-invocation estimates]

Total skill definitions: X
Model-invoking skills: Y (cost > $0)
Meta/orchestrating skills: Z

───────────────────────────────────────────────────
3. HOOK COSTS
───────────────────────────────────────────────────
[Results from Section 3]

───────────────────────────────────────────────────
4. IMPLICIT SESSION COSTS
───────────────────────────────────────────────────
[Results from Section 4]

Estimated cost per typical session (20 exchanges):
  Context growth overhead: ~$X.XX
  Tool call overhead: ~$X.XX

───────────────────────────────────────────────────
5. WORKFLOW PROFILES
───────────────────────────────────────────────────
[Table from Section 5]

───────────────────────────────────────────────────
6. OPTIMIZATION OPPORTUNITIES
───────────────────────────────────────────────────
Ranked by estimated monthly savings (assuming N sessions/day):

 #  Recommendation             Savings/mo  Confidence  Risk
 1  [description]              $XX.XX      HIGH        LOW
 2  [description]              $XX.XX      MEDIUM      LOW
 3  [description]              $X.XX       MEDIUM      MEDIUM
 ...

───────────────────────────────────────────────────
COST SUMMARY
───────────────────────────────────────────────────
                        Per Session    Per Day (est.)
Direct API calls:       $X.XX          $XX.XX
Skill invocations:      $X.XX          $XX.XX
Hooks:                  $X.XX          $XX.XX
Session overhead:       $X.XX          $XX.XX
                        ─────────      ──────────
TOTAL (before optim.):  $X.XX          $XX.XX
TOTAL (after optim.):   $X.XX          $XX.XX
Potential savings:       XX%

Assumptions:
  • Sessions per day: [N]
  • Average exchanges per session: [N]
  • Primary model: [model]
  • Prices from: anthropic.com/pricing (verify current rates)
═══════════════════════════════════════════════════

NOTE: These estimates carry the confidence levels stated
above. Actual costs depend on conversation length, model
selection, caching behavior, and usage patterns. Check your
Anthropic dashboard for actual spend.
```

## Important Notes

- Always remind the user to verify current pricing at anthropic.com/pricing
- Token counts are estimates — actual tokenization varies by content
- Session costs vary significantly based on conversation length and complexity
- Caching effectiveness depends on prompt stability between calls
- Extended thinking tokens (if enabled) can significantly increase output costs
- The cost of running THIS skill is itself an API cost — note it in the report
