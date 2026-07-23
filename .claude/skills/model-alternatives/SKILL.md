---
name: model-alternatives
description: >
  Finds paid AI API calls in the codebase and recommends free open-source
  replacements. Generates a project-specific eval suite to grade free models
  against paid ones. Aggressive risk/reward assessment for maximum savings.
argument-hint: "[path or empty for full analysis]"
allowed-tools: Read, Glob, Grep, Write, Bash(python *), Bash(python3 *), Bash(pip install *), Bash(source *), Bash(git diff *), Bash(git log *), Bash(wc *)
---

# Open-Source Model Alternatives Analysis

Scan the codebase for paid AI API calls, recommend free open-source replacements, and generate a runnable eval suite to validate quality before switching.

**Scope**: Source code API calls only. Does NOT analyze Claude Code's own skills, hooks, or internal operations.

## Open-Source Model Reference

Candidate models by task type live in `models-reference.md` in this
skill directory — read it when matching candidates in Section 3.

## Analysis Process

### Preliminary: Activate Virtual Environment

Before running any Python commands, activate the project's virtual environment:

```bash
# Activate virtual environment (supports venv, poetry, conda, uv, pipenv, pyenv)
source .claude/hooks/venv-activate.sh 2>/dev/null || true
```

### Section 1: Discover Paid API Calls

Search the codebase for paid AI API usage. Ignore anything under `.claude/` (skills, hooks, config).

```
Patterns to search for:

# Anthropic
- import anthropic / from anthropic
- client.messages.create
- anthropic.Anthropic() / anthropic.AsyncAnthropic()
- api.anthropic.com
- Agent() / Runner.run() (Claude Agent SDK)

# OpenAI
- import openai / from openai
- client.chat.completions.create
- client.embeddings.create
- openai.OpenAI() / openai.AsyncOpenAI()
- api.openai.com

# Other paid APIs
- import cohere / cohere.Client
- import google.generativeai
- replicate.run (paid models)
- together.ai API calls (paid models)

# Generic patterns
- ANTHROPIC_API_KEY / OPENAI_API_KEY / API_KEY
- "model": "claude- / "model": "gpt-
- model="claude- / model="gpt-
```

For each call site found, extract:

1. **File and line number**
2. **Provider** (Anthropic, OpenAI, Cohere, etc.)
3. **Model** being used (or default)
4. **Task type** — classify based on context (see Section 2)
5. **Input pattern** — system prompt, user template, injected context
6. **Output expectations** — max_tokens, response_format, structured output
7. **Frequency** — how often called (from control flow analysis)
8. **Current estimated cost** — from `/cost-estimate` pricing tables

### Section 2: Classify Task Type

For each API call, classify into one of these categories by analyzing the surrounding code:

| Task Type | Signals |
|-----------|---------|
| **code-generation** | Prompt mentions code, function, class; output parsed as code; used in code editing flow |
| **code-review** | Prompt asks to review/analyze code; output is feedback/issues |
| **classification** | Output is a label, category, boolean, or enum; short output; routing logic downstream |
| **summarization** | Long input, short output; prompt says "summarize", "tl;dr", "brief" |
| **extraction** | Input is unstructured, output is JSON/structured; parsing downstream |
| **embedding** | Uses embedding endpoint; output is vector/array of floats |
| **conversation** | Multi-turn chat; user-facing; requires personality/tone |
| **reasoning** | Chain-of-thought; complex logic; math; planning |
| **translation** | Input in one language, output in another |
| **generation** | Creative content; long-form output; no strict format |

### Section 3: Match Candidates

For each discovered call, recommend 2-3 open-source alternatives ranked by fit:

```
[FILE:LINE] provider=anthropic model=claude-sonnet-5
  Task type: classification
  Current cost: ~$0.012/call

  CANDIDATE 1: Llama 3.3 70B via Groq (FREE)
    Fit: HIGH — classification is well within 70B capability
    Expected quality: ~92% of Claude Sonnet on classification tasks
    Latency: ~200ms (Groq is optimized for speed)
    Risk: LOW — classification tasks are deterministic, easy to validate
    Savings: 100% ($0.012/call → $0.00/call)

  CANDIDATE 2: Phi-4 14B via Ollama (FREE, local)
    Fit: MEDIUM — smaller model, may struggle with nuanced categories
    Expected quality: ~78% of Claude Sonnet on classification tasks
    Latency: ~500ms (depends on hardware)
    Risk: MEDIUM — may need prompt tuning for edge cases
    Savings: 100% ($0.012/call → $0.00/call)

  CANDIDATE 3: Qwen2.5 7B via Cloudflare (FREE)
    Fit: MEDIUM — good JSON output, but smallest model
    Expected quality: ~70% of Claude Sonnet
    Latency: ~300ms
    Risk: MEDIUM-HIGH — limited reasoning for complex classification
    Savings: 100%
```

**Quality estimation heuristics** (when no eval data exists yet):

| Task Type | 70B OSS vs Claude Sonnet | 14B OSS vs Claude Sonnet | 7B OSS vs Claude Sonnet |
|-----------|--------------------------|--------------------------|-------------------------|
| classification | 88-95% | 75-85% | 65-78% |
| summarization | 85-92% | 72-82% | 60-75% |
| extraction | 82-90% | 70-80% | 55-70% |
| embedding | 90-98%* | 85-95%* | 80-90%* |
| code-generation | 75-88% | 60-75% | 45-60% |
| code-review | 70-82% | 55-68% | 40-55% |
| reasoning | 65-80% | 45-60% | 30-45% |
| conversation | 80-90% | 65-78% | 55-68% |

*Embedding models are specialized; quality depends on the specific model, not just size.

These are starting estimates. The eval suite (Section 4) produces real numbers.

### Section 4: Generate Eval Suite

This is the core deliverable. For each API call site, generate a runnable
test that captures real prompts from the codebase, calls both paid and
free models with the same input, scores outputs against each other, and
produces a comparison report.

The full generation reference — eval-case extraction (4a), the
`eval_model_alternatives.py` harness template (4b), scoring criteria by
task type (4c), and reference-output collection (4d) — lives in
`eval-suite.md` in this skill directory. Read it when you reach this
section.

### Section 5: Risk/Reward Assessment

For EVERY discovered API call, produce an aggressive risk/reward assessment:

```
═══════════════════════════════════════════════════
  RISK/REWARD: src/classifier.py:42
═══════════════════════════════════════════════════

Task: classification (support ticket routing)
Current: anthropic/claude-sonnet → $0.012/call × ~500/day = $6.00/day
Best free alternative: Llama 3.3 70B via Groq

  REWARD                          RISK
  ───────────────────────         ───────────────────────
  $6.00/day saved ($180/mo)       Quality drop: ~5-10%
  Lower latency (Groq ~200ms)     Groq free tier limits
  No vendor lock-in                Need fallback if Groq down
  Privacy (if using Ollama)        Prompt tuning may be needed

  Quality estimate: 92% of Claude (BEFORE eval)
  Recommendation: STRONG REPLACE ← run eval to confirm

  Migration effort: LOW
    - Swap API client (anthropic → groq/ollama)
    - Same prompt format works
    - Add retry/fallback logic
```

Use these recommendation levels:

| Recommendation | Criteria |
|----------------|----------|
| **STRONG REPLACE** | Estimated quality >85%, task is well-suited to OSS, high cost savings |
| **LIKELY REPLACE** | Estimated quality 75-85%, moderate risk, significant savings |
| **EVAL FIRST** | Estimated quality 60-75%, or task is nuanced — run eval before deciding |
| **KEEP PAID** | Estimated quality <60%, or task requires frontier reasoning/safety |
| **HYBRID** | Use free model for most cases, fall back to paid for edge cases or low confidence |

The **HYBRID** pattern deserves special attention — it often captures 80%+ of savings with minimal quality risk:

```python
# Hybrid pattern: free model first, paid fallback
def classify_with_fallback(text: str) -> str:
    result = call_free_model(text)
    confidence = extract_confidence(result)

    if confidence < 0.8:  # Low confidence → escalate to paid
        result = call_paid_model(text)

    return result
```

### Section 6: Persistence Recommendations

For each API call that produces deterministic or cacheable results, recommend persistence:

1. **Cache layer**: Store results keyed by input hash, skip API call on cache hit
2. **Result database**: For classification/extraction, build a lookup table from historical results
3. **Fine-tuning data**: Collect paid model outputs as training data for fine-tuning a smaller open-source model on your specific task
4. **Distillation path**: Use paid model outputs to distill a task-specific small model

```
PERSISTENCE: src/classifier.py:42
  Cacheability: HIGH (same input → same output for classification)
  Suggested: Redis/SQLite cache keyed by sha256(input)
  Est. cache hit rate: 60-80% (many repeated ticket patterns)
  Additional savings: $3.60-4.80/day on top of model switch
```

## Output Format

```
/model-alternatives
═══════════════════════════════════════════════════
      MODEL ALTERNATIVES REPORT
═══════════════════════════════════════════════════
Project: [project name]
Scope: [path or "full project (excluding .claude/)"]
Paid API calls found: N across M files

───────────────────────────────────────────────────
1. DISCOVERED API CALLS
───────────────────────────────────────────────────

 #  Location              Provider   Model          Task Type       Cost/call
 1  src/classify.py:42    anthropic  sonnet-5       classification  $0.012
 2  src/summarize.py:88   openai     gpt-4o         summarization   $0.034
 3  src/embed.py:15       openai     embed-3-small  embedding       $0.002
 ...

───────────────────────────────────────────────────
2. RECOMMENDATIONS (aggressive — all calls assessed)
───────────────────────────────────────────────────

 #  Call Site             Verdict         Free Alternative         Savings/mo  Quality
 1  src/classify.py:42    STRONG REPLACE  Llama 3.3 70B / Groq    $180        ~92%
 2  src/summarize.py:88   LIKELY REPLACE  Qwen2.5 72B / Ollama    $510        ~87%
 3  src/embed.py:15       STRONG REPLACE  Nomic Embed v1.5        $30         ~95%
 ...

───────────────────────────────────────────────────
3. EVAL SUITE GENERATED
───────────────────────────────────────────────────

File: eval_model_alternatives.py
Cases: X eval cases across Y call sites
Models: Z free models configured

To run:
  pip install anthropic openai ollama groq httpx tabulate
  python eval_model_alternatives.py

The eval will:
  1. Call your paid models to establish reference outputs
  2. Call each free alternative with the same inputs
  3. Score outputs on format, accuracy, and similarity
  4. Print a graded comparison report (A/B/C/D/F)

───────────────────────────────────────────────────
4. MIGRATION PATHS
───────────────────────────────────────────────────

For each STRONG REPLACE / LIKELY REPLACE:
  - Provider swap code snippet
  - Prompt adjustments needed (if any)
  - Fallback/hybrid pattern recommendation
  - Cache layer suggestion

───────────────────────────────────────────────────
5. COST IMPACT SUMMARY
───────────────────────────────────────────────────
                       Current    After Migration
Paid API calls/day:    N          M (only KEEP PAID + fallbacks)
Daily spend:           $XX.XX     $X.XX
Monthly spend:         $XXX.XX    $XX.XX
Savings:               $XXX.XX/month (XX%)

Confidence: MEDIUM (run eval suite for HIGH confidence)

Assumptions:
  • Savings assume free tiers / self-hosted at $0
  • Quality estimates are pre-eval heuristics
  • Run eval_model_alternatives.py for actual measurements
  • Free tier rate limits may require Ollama fallback for high volume
═══════════════════════════════════════════════════
```

## Important Notes

- Model benchmarks change rapidly — verify current scores at open-llm-leaderboard
- Free tier rate limits vary; high-volume calls may need self-hosted Ollama/vLLM
- The eval harness requires API keys for paid models to generate reference outputs
- Fine-tuning a small model on your specific task often beats a larger general model
- The HYBRID pattern (free + paid fallback) is often the best risk-adjusted approach
- Always run the generated eval suite before migrating production calls
- This skill does NOT analyze Claude Code internals (skills, hooks, config)
