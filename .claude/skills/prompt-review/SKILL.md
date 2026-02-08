---
name: prompt-review
description: >
  Reviews all AI prompts in the application source code and suggests
  improvements for accuracy, quality, and cost-efficiency. Excludes
  .claude/ configuration. Grades each prompt and provides rewrites.
argument-hint: "[path or empty for full project]"
allowed-tools: Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(wc *), Bash(python -c *)
---

# AI Prompt Review

Scan the application source code for AI prompts, evaluate their quality, and suggest concrete improvements. Does NOT review anything under `.claude/` (skills, hooks, config).

## What Counts as a Prompt

Search for these patterns in source code:

```
# String arguments to AI API calls
- system=, system_prompt=, system_message=
- messages=[{...}], messages.append(
- prompt=, user_prompt=, instruction=
- .format(, f"...{, Template(

# Prompt construction patterns
- """...""" or '''...''' multi-line strings near API calls
- SYSTEM_PROMPT =, USER_TEMPLATE =, PROMPT =  (constant assignments)
- .txt or .md files loaded as prompts (open("prompts/..."))
- Jinja/string templates used for prompt assembly

# Framework-specific
- @tool, @prompt, tool_description=  (function calling / tool definitions)
- few_shot_examples, example_input, example_output
- ChatPromptTemplate, PromptTemplate, SystemMessage, HumanMessage
- Agent(instructions=...), system_prompt=...
```

Exclude from review:
- Everything under `.claude/` (skills, hooks, settings)
- Test fixtures and mock prompts (unless they mirror production prompts)
- Comments and docstrings that aren't used as prompts
- Logging/debugging strings

## Prompt Quality Framework

Grade each prompt on these dimensions. Each scores 1-5.

### 1. Clarity (Is the task unambiguous?)

| Score | Criteria |
|-------|----------|
| 5 | Single clear objective, no room for misinterpretation |
| 4 | Clear objective with minor ambiguity in edge cases |
| 3 | Objective is understandable but leaves room for interpretation |
| 2 | Multiple possible interpretations of what's being asked |
| 1 | Vague, unclear what the model should actually do |

**Common clarity issues:**
- "Analyze this" without specifying what to look for or how to structure output
- Implicit assumptions the model can't know (domain jargon without definition)
- Mixing multiple tasks in one prompt without clear separation
- Using "good" or "appropriate" without defining what that means

### 2. Specificity (Does it constrain the output?)

| Score | Criteria |
|-------|----------|
| 5 | Output format, length, style, and edge case handling all specified |
| 4 | Output format and key constraints specified |
| 3 | Some constraints but important dimensions left open |
| 2 | Minimal constraints, model decides most output characteristics |
| 1 | No constraints, completely open-ended |

**Common specificity issues:**
- No output format specified (JSON? plain text? markdown?)
- No length guidance (one word? one paragraph? unlimited?)
- No handling instructions for edge cases or empty inputs
- No examples of desired vs undesired output

### 3. Context (Does the model have what it needs?)

| Score | Criteria |
|-------|----------|
| 5 | All necessary context provided, nothing extraneous |
| 4 | Sufficient context with minor gaps |
| 3 | Key context present but some important details missing |
| 2 | Significant context gaps that will hurt quality |
| 1 | Critical context missing, model is guessing |

**Common context issues:**
- Referencing entities/concepts not defined in the prompt
- Missing schema or type information for structured output
- No domain context for specialized tasks
- Too much irrelevant context (dilutes attention)
- Variable injection without explaining what the variable represents

### 4. Structure (Is it well-organized for the model?)

| Score | Criteria |
|-------|----------|
| 5 | Clear sections, role assignment, task → constraints → examples flow |
| 4 | Good organization with minor structural issues |
| 3 | Readable but could be better organized |
| 2 | Disorganized, instructions scattered |
| 1 | Wall of text, no structure |

**Best practices for structure:**
- Role/persona first (if applicable)
- Task description next
- Constraints and rules
- Output format specification
- Examples (few-shot) last — these anchor the model's behavior
- XML tags or markdown headers to separate sections

### 5. Robustness (Will it work across input variations?)

| Score | Criteria |
|-------|----------|
| 5 | Handles edge cases, adversarial inputs, and empty/malformed data |
| 4 | Handles common variations, most edge cases covered |
| 3 | Works for happy path, some edge cases unhandled |
| 2 | Fragile, breaks on common input variations |
| 1 | Only works for a narrow set of inputs |

**Common robustness issues:**
- No instructions for empty, null, or malformed input
- No guidance when the model is uncertain or input is ambiguous
- Prompt injection vulnerability (user input injected without sanitization)
- No fallback behavior defined
- Assumes input language, format, or encoding

### 6. Efficiency (Does it minimize tokens without losing quality?)

| Score | Criteria |
|-------|----------|
| 5 | Concise, every token earns its place, optimal for the task |
| 4 | Mostly efficient with minor verbosity |
| 3 | Some unnecessary repetition or padding |
| 2 | Significantly verbose, could be cut by 30%+ |
| 1 | Extremely wasteful, redundant instructions, unnecessary preamble |

**Common efficiency issues:**
- Repeating the same instruction in different words
- Unnecessary politeness or preamble ("I would like you to please...")
- Including context the model already knows (e.g., explaining what JSON is)
- System prompt that could be shorter with the same effect
- Few-shot examples that are too long or too numerous

## Anti-Patterns to Flag

Flag these specific issues with HIGH priority:

### Prompt Injection Vulnerabilities

```python
# DANGEROUS: User input directly in prompt
prompt = f"Summarize this text: {user_input}"

# SAFER: Delimited user input
prompt = f"""Summarize the text between <input> tags.
<input>{user_input}</input>
Respond only with the summary."""
```

### Hallucination Encouragement

```python
# BAD: Encourages fabrication
prompt = "Tell me about the company's Q3 earnings"  # No data provided

# BETTER: Grounds in provided data
prompt = """Based ONLY on the following financial data, summarize Q3 earnings.
If data is missing, say "Not available in provided data."

Data:
{financial_data}"""
```

### Lost-in-the-Middle

```python
# BAD: Critical instruction buried in a wall of context
prompt = f"{long_context}\n\nBy the way, output as JSON.\n\n{more_context}"

# BETTER: Key instructions at start and end (primacy/recency)
prompt = f"""Output your response as JSON matching this schema: {schema}

Context:
{long_context}

Remember: respond ONLY with valid JSON matching the schema above."""
```

### Overloaded Prompts

```python
# BAD: Too many tasks in one prompt
prompt = """Analyze this code for bugs, suggest refactors, write tests,
update documentation, and estimate complexity."""

# BETTER: One task per prompt, or explicit task separation
prompt = """Perform these tasks IN ORDER. Output each under its own heading.

## Task 1: Bug Analysis
[instructions]

## Task 2: Refactoring Suggestions
[instructions]"""
```

### Missing Output Anchoring

```python
# BAD: No format constraint
prompt = "Classify this support ticket"

# BETTER: Anchored output
prompt = """Classify this support ticket into exactly one category.

Categories: bug, feature_request, question, billing, other

Respond with ONLY the category name, nothing else.

Ticket: {ticket_text}"""
```

### Needless Chain-of-Thought

```python
# WASTEFUL: CoT for a simple lookup/classification task
prompt = "Think step by step about what category this belongs to..."

# BETTER: Direct classification (saves output tokens)
prompt = "Classify into one of: [A, B, C]. Respond with the letter only."
```

### Missing Few-Shot Examples

```python
# WEAK: No examples for a nuanced task
prompt = "Extract entities from this text"

# STRONGER: Few-shot with edge cases
prompt = """Extract named entities from text. Return as JSON array.

Example 1:
Input: "Apple released the iPhone 15 in Cupertino"
Output: [{"name": "Apple", "type": "ORG"}, {"name": "iPhone 15", "type": "PRODUCT"}, {"name": "Cupertino", "type": "LOC"}]

Example 2:
Input: "No entities here, just a plain sentence."
Output: []

Now extract from:
Input: {text}
Output:"""
```

## Process

### Step 1: Discover All Prompts

Search the codebase (excluding `.claude/`) for AI prompt patterns:

1. Find all files that import AI client libraries
2. Trace from API call sites back to prompt construction
3. Find prompt template files (`.txt`, `.md`, `.jinja2` loaded as prompts)
4. Find constant string assignments used as prompts
5. Find prompt builder patterns (concatenation, formatting, template rendering)

For each prompt found, record:
- **Location**: file:line
- **Type**: system prompt, user template, few-shot examples, tool description
- **Construction**: static string, f-string, template, concatenation
- **Variables injected**: what runtime data is interpolated
- **API call it feeds**: which model, what parameters
- **Output handling**: how the response is parsed downstream

### Step 2: Grade Each Prompt

Apply the 6-dimension framework. For each prompt produce:

```
──────────────────────────────────────
PROMPT: src/classifier.py:42
Type: system prompt (static)
Model: claude-sonnet-4
Tokens: ~340
──────────────────────────────────────

  Clarity:      ████░  4/5  Clear task, minor ambiguity on edge cases
  Specificity:  ██░░░  2/5  No output format specified
  Context:      ███░░  3/5  Missing category definitions
  Structure:    ████░  4/5  Good separation of concerns
  Robustness:   ██░░░  2/5  No empty input handling
  Efficiency:   ███░░  3/5  Some redundant phrasing

  OVERALL: C+ (18/30)

  Issues:
  [P1] SPECIFICITY: No output format — model may return prose, JSON, or
       just the label. Downstream code does .strip() which is fragile.
  [P1] ROBUSTNESS: No handling for empty or malformed input. If ticket_text
       is empty, model will hallucinate a classification.
  [P2] CONTEXT: Categories listed but not defined. "other" is ambiguous —
       when should the model choose it vs. "question"?
  [P3] EFFICIENCY: "Please carefully analyze" adds 3 tokens with no effect.
```

### Step 3: Generate Improvement Suggestions

For each prompt, provide a concrete rewrite addressing all flagged issues. Show the diff clearly:

```
BEFORE (src/classifier.py:42):
────────────────────────────────────────
You are a support ticket classifier. Please carefully analyze the
following support ticket and classify it into the appropriate category.

Categories: bug, feature_request, question, billing, other

{ticket_text}
────────────────────────────────────────

AFTER (suggested rewrite):
────────────────────────────────────────
Classify this support ticket into exactly one category.

Categories:
- bug: Something is broken or not working as documented
- feature_request: A request for new functionality
- question: User asking how to do something
- billing: Payment, subscription, or pricing issues
- other: Does not fit any above category

Rules:
- If the ticket is empty or unintelligible, respond with: other
- If multiple categories apply, choose the primary intent
- Respond with ONLY the category name, no explanation

Ticket:
<ticket>{ticket_text}</ticket>

Category:
────────────────────────────────────────

Changes:
  +  Added category definitions (specificity)
  +  Added empty input handling (robustness)
  +  Added output anchoring with "Category:" (specificity)
  +  Delimited user input with XML tags (robustness/injection)
  +  Removed "Please carefully analyze" (efficiency, -3 tokens)
  +  Added multi-category tiebreaker rule (robustness)
  ~  Est. quality improvement: +15-25% on edge cases
  ~  Token change: 340 → 295 (-13%)
```

### Step 4: Prioritize Recommendations

Rank all prompt improvements by impact:

**Impact scoring:**
- How often is this prompt called? (frequency × improvement = total impact)
- How severe are the issues? (P1 issues on high-frequency prompts first)
- How much quality uplift is expected?
- Does the fix also save tokens (cost reduction)?

### Step 5: Cross-Cutting Recommendations

After reviewing all prompts individually, identify patterns across the codebase:

- **Shared system prompt fragments** that could be standardized
- **Inconsistent output formats** across similar prompts
- **Missing prompt versioning** (prompts should be tracked, not buried in code)
- **Prompt/code coupling** — prompts hardcoded in business logic vs. external template files
- **Prompt testing** — are prompts covered by tests? Do tests assert on output format?

## Output Format

```
═══════════════════════════════════════════════════
          PROMPT REVIEW REPORT
═══════════════════════════════════════════════════
Project: [project name]
Scope: [path or "full project (excluding .claude/)"]
Prompts found: N across M files
Total prompt tokens: ~X,XXX

───────────────────────────────────────────────────
SUMMARY GRADES
───────────────────────────────────────────────────

 #  Location                Grade  Issues   Type
 1  src/classifier.py:42    C+     3 (1×P1) system prompt
 2  src/summarize.py:88     B      1 (0×P1) user template
 3  src/extract.py:15       D+     5 (2×P1) system + few-shot
 4  src/chat.py:102         A-     1 (0×P1) system prompt
 ...

Average grade: [letter]
Prompts with P1 issues: X of N

Grade distribution:
  A  (25-30): ██       X prompts — production ready
  B  (20-24): ████     X prompts — good, minor improvements
  C  (15-19): ██████   X prompts — functional, significant room to improve
  D  (10-14): ███      X prompts — needs work, quality risk
  F  ( 0-9):  █        X prompts — rewrite recommended

───────────────────────────────────────────────────
P1 ISSUES (fix these first)
───────────────────────────────────────────────────

[Prompt injection vulnerabilities]
[Missing output format specifications]
[Hallucination risks from missing grounding]
[No empty/malformed input handling]

───────────────────────────────────────────────────
DETAILED REVIEWS
───────────────────────────────────────────────────

[Per-prompt grades, issues, and rewrites from Step 2-3]

───────────────────────────────────────────────────
CROSS-CUTTING RECOMMENDATIONS
───────────────────────────────────────────────────

[Patterns from Step 5]

───────────────────────────────────────────────────
IMPACT SUMMARY
───────────────────────────────────────────────────
                        Before      After (est.)
Average prompt grade:   C+          B+
Prompt injection risks: X           0
Token efficiency:       X,XXX tok   Y,YYY tok (-Z%)
Expected quality lift:  baseline    +15-25% on edge cases

Top 3 highest-impact fixes:
 1. [prompt] — [expected improvement] — [effort: LOW/MED/HIGH]
 2. [prompt] — [expected improvement] — [effort: LOW/MED/HIGH]
 3. [prompt] — [expected improvement] — [effort: LOW/MED/HIGH]

═══════════════════════════════════════════════════

Say "rewrite [N]" to get the full suggested rewrite for prompt #N.
Say "rewrite all" to get all suggested rewrites.
Say "apply [N]" to apply a rewrite directly to the source file.
```

## Notes

- This skill is read-only by default; rewrites are suggestions until explicitly applied
- Prompt quality is subjective — grades are based on established best practices, not absolute truth
- The "best" prompt depends on the model being used; a prompt tuned for Claude may need adjustment for GPT or open-source models
- Some prompts are intentionally minimal (e.g., creative writing) — flag but don't penalize open-endedness when it's deliberate
- When prompts use variables, evaluate both the template and representative filled examples
- If prompt templates are in external files (`.txt`, `.md`), review those files too
