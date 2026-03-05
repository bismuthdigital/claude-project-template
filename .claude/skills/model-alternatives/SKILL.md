---
name: model-alternatives
version: 1.0.0
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

### Code Generation / Editing

| Model | Params | HumanEval | Strengths | Run With |
|-------|--------|-----------|-----------|----------|
| DeepSeek-Coder-V2 | 236B (MoE) | 90.2% | Near-frontier coding, strong reasoning | vLLM, together.ai |
| Qwen2.5-Coder | 32B | 85.1% | Strong code completion, instruction following | Ollama, vLLM |
| CodeLlama | 70B | 67.8% | Code infilling, long context | Ollama, vLLM |
| StarCoder2 | 15B | 52.7% | 600+ languages, code completion | Ollama, HuggingFace |
| DeepSeek-R1-Distill | 70B | ~85% | Reasoning-heavy coding, chain-of-thought | Ollama, vLLM |
| Phi-4 | 14B | 82.6% | Small footprint, strong for size | Ollama, Cloudflare |

### General Text / Summarization / Classification

| Model | Params | MMLU | Strengths | Run With |
|-------|--------|------|-----------|----------|
| Llama 3.3 | 70B | 86.0% | General purpose, strong instruction following | Ollama, Groq, vLLM |
| Qwen2.5 | 72B | 85.3% | Multilingual, long context (128k) | Ollama, vLLM |
| Mistral Large | 123B | 84.0% | Strong reasoning, function calling | vLLM, Mistral API (free tier) |
| Mixtral 8x22B | 176B MoE | 77.8% | Fast inference (MoE), good general | Ollama, together.ai |
| Gemma 2 | 27B | 75.2% | Small, Google quality | Ollama, Cloudflare |
| Phi-4 | 14B | 84.8% | Tiny footprint, punches above weight | Ollama, Cloudflare |
| Llama 3.2 | 3B | 63.4% | Runs on CPU, edge deployment | Ollama, phone/laptop |

### Structured Extraction / JSON Output

| Model | Params | Notes | Run With |
|-------|--------|-------|----------|
| Qwen2.5 | 7B-72B | Native JSON mode, function calling | Ollama, vLLM |
| Llama 3.3 | 70B | Tool use trained, structured output | Ollama, Groq |
| Hermes 3 (Nous) | 70B | Fine-tuned for function calling and JSON | Ollama, vLLM |
| Mistral Nemo | 12B | Built-in function calling | Ollama, Mistral free tier |

### Embeddings / Search

| Model | Dims | MTEB Avg | Run With |
|-------|------|----------|----------|
| Nomic Embed v1.5 | 768 | 62.3% | Ollama, HuggingFace |
| BGE-large-en-v1.5 | 1024 | 64.2% | HuggingFace, local |
| GTE-Qwen2 | 1536 | 67.2% | HuggingFace, local |
| Snowflake Arctic Embed | 1024 | 66.7% | HuggingFace, Replicate |
| mxbai-embed-large | 1024 | 64.6% | Ollama |

### Free Hosting Options

| Provider | Free Tier | Models Available | Limits |
|----------|-----------|-----------------|--------|
| **Ollama** (local) | Unlimited | All open-source | Limited by hardware |
| **Groq** | Yes | Llama 3.3 70B, Mixtral, Gemma 2 | ~30 req/min, 14.4k tokens/min |
| **HuggingFace Inference** | Yes | Most popular models | Rate limited, queue-based |
| **Cloudflare Workers AI** | 10k tokens/day | Llama, Phi, Gemma | Low limits but $0 |
| **OpenRouter** | Some free models | Varies | Per-model limits |
| **Google AI Studio** | Yes | Gemma 2 | Generous free tier |

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
[FILE:LINE] provider=anthropic model=claude-sonnet-4-20250514
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

This is the core deliverable. For each API call site, generate a runnable test that:

1. **Captures real prompts** from the codebase
2. **Calls both paid and free models** with the same input
3. **Scores outputs** against each other
4. **Produces a comparison report**

#### 4a: Extract Eval Cases

For each API call site, extract test cases:

```python
# From the actual prompts in the codebase, generate eval cases
# Each case has: input (system + user prompt), expected output pattern, scoring criteria

eval_cases = [
    {
        "name": "classify_support_ticket_bug",
        "source": "src/classifier.py:42",
        "system_prompt": "<extracted from code>",
        "user_prompt": "<representative example>",
        "expected_output_pattern": r"(bug|feature|question|other)",
        "scoring": {
            "format_compliance": "output matches expected enum",
            "accuracy": "matches human-labeled ground truth if available",
            "latency_budget_ms": 1000,
        },
    },
    # ... more cases per call site
]
```

**How to build eval cases:**

1. Read the system prompt and user prompt templates from the code
2. Find any test files that exercise this code path — extract test inputs
3. Find any hardcoded examples, few-shot examples, or docstring examples
4. If no examples exist, generate 5-10 representative inputs based on the prompt template
5. For expected outputs: use type hints, response_format schemas, regex patterns, or downstream assertions

#### 4b: Generate the Eval Harness

Write a Python file `eval_model_alternatives.py` in the project root:

```python
"""
Model Alternatives Eval Suite
Generated by /model-alternatives skill

Compares paid AI API calls against free open-source alternatives.
Run with: python eval_model_alternatives.py

Requirements:
  pip install anthropic openai ollama groq httpx tabulate
"""

import json
import time
import re
import statistics
from dataclasses import dataclass, field
from pathlib import Path

# --- Configuration ---

PAID_MODELS = {
    # Populated from discovered API calls
    "anthropic/claude-sonnet-4-20250514": {
        "provider": "anthropic",
        "cost_per_1k_input": 0.003,
        "cost_per_1k_output": 0.015,
    },
}

FREE_MODELS = {
    # Populated from candidate matching
    "ollama/llama3.3:70b": {
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        "cost_per_1k_input": 0.0,
        "cost_per_1k_output": 0.0,
    },
    "groq/llama-3.3-70b-versatile": {
        "provider": "groq",
        "cost_per_1k_input": 0.0,
        "cost_per_1k_output": 0.0,
    },
}

# --- Eval Cases ---
# (populated per-call-site from Section 4a)

EVAL_CASES = []  # Filled by the skill

# --- Scoring Functions ---

@dataclass
class EvalResult:
    model: str
    case_name: str
    output: str
    latency_ms: float
    input_tokens: int
    output_tokens: int
    cost: float
    scores: dict = field(default_factory=dict)

def score_format_compliance(output: str, pattern: str) -> float:
    """Score 0.0-1.0 based on whether output matches expected format."""
    if re.fullmatch(pattern, output.strip(), re.DOTALL):
        return 1.0
    if re.search(pattern, output.strip()):
        return 0.7
    return 0.0

def score_semantic_similarity(reference: str, candidate: str) -> float:
    """Score 0.0-1.0 based on content overlap with reference output."""
    ref_tokens = set(reference.lower().split())
    cand_tokens = set(candidate.lower().split())
    if not ref_tokens:
        return 0.0
    intersection = ref_tokens & cand_tokens
    union = ref_tokens | cand_tokens
    return len(intersection) / len(union) if union else 0.0

def score_json_validity(output: str) -> float:
    """Score 1.0 if output is valid JSON, 0.0 otherwise."""
    try:
        json.loads(output)
        return 1.0
    except (json.JSONDecodeError, TypeError):
        # Try extracting JSON from markdown code blocks
        match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", output, re.DOTALL)
        if match:
            try:
                json.loads(match.group(1))
                return 0.8  # Valid but needed extraction
            except (json.JSONDecodeError, TypeError):
                pass
        return 0.0

def score_length_ratio(reference: str, candidate: str) -> float:
    """Score based on output length similarity (1.0 = same length)."""
    if not reference:
        return 1.0
    ratio = len(candidate) / len(reference)
    if 0.5 <= ratio <= 2.0:
        return 1.0 - abs(1.0 - ratio) * 0.5
    return 0.2

# --- Runner ---

def call_model(model_config: dict, system_prompt: str, user_prompt: str,
               max_tokens: int = 1024) -> tuple[str, float, int, int]:
    """
    Call a model and return (output, latency_ms, input_tokens, output_tokens).
    Supports: anthropic, openai, ollama, groq, huggingface.
    """
    provider = model_config["provider"]
    start = time.perf_counter()

    if provider == "anthropic":
        import anthropic
        client = anthropic.Anthropic()
        resp = client.messages.create(
            model=model_config.get("model_id", "claude-sonnet-4-20250514"),
            max_tokens=max_tokens,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
        )
        output = resp.content[0].text
        latency = (time.perf_counter() - start) * 1000
        return output, latency, resp.usage.input_tokens, resp.usage.output_tokens

    elif provider == "openai":
        import openai
        client = openai.OpenAI()
        resp = client.chat.completions.create(
            model=model_config.get("model_id", "gpt-4o"),
            max_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        )
        output = resp.choices[0].message.content or ""
        latency = (time.perf_counter() - start) * 1000
        return (output, latency,
                resp.usage.prompt_tokens, resp.usage.completion_tokens)

    elif provider == "ollama":
        import ollama as ollama_client
        resp = ollama_client.chat(
            model=model_config.get("model_id", "llama3.3:70b"),
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            options={"num_predict": max_tokens},
        )
        output = resp["message"]["content"]
        latency = (time.perf_counter() - start) * 1000
        tokens_in = resp.get("prompt_eval_count", 0)
        tokens_out = resp.get("eval_count", 0)
        return output, latency, tokens_in, tokens_out

    elif provider == "groq":
        from groq import Groq
        client = Groq()
        resp = client.chat.completions.create(
            model=model_config.get("model_id", "llama-3.3-70b-versatile"),
            max_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        )
        output = resp.choices[0].message.content or ""
        latency = (time.perf_counter() - start) * 1000
        return (output, latency,
                resp.usage.prompt_tokens, resp.usage.completion_tokens)

    elif provider == "huggingface":
        import httpx
        resp = httpx.post(
            f"https://api-inference.huggingface.co/models/{model_config['model_id']}",
            headers={"Authorization": f"Bearer {model_config.get('token', '')}"},
            json={"inputs": f"{system_prompt}\n\n{user_prompt}",
                  "parameters": {"max_new_tokens": max_tokens}},
            timeout=60,
        )
        output = resp.json()[0].get("generated_text", "")
        latency = (time.perf_counter() - start) * 1000
        return output, latency, 0, 0  # HF doesn't report tokens

    else:
        raise ValueError(f"Unknown provider: {provider}")


def run_eval(cases: list[dict], paid_models: dict, free_models: dict,
             runs_per_case: int = 3) -> list[EvalResult]:
    """Run all eval cases against all models, return results."""
    results = []
    all_models = {**paid_models, **free_models}

    for case in cases:
        print(f"\n  Evaluating: {case['name']}")
        for model_name, model_config in all_models.items():
            case_results = []
            for run in range(runs_per_case):
                try:
                    output, latency, tok_in, tok_out = call_model(
                        model_config,
                        case.get("system_prompt", ""),
                        case["user_prompt"],
                        case.get("max_tokens", 1024),
                    )

                    cost_in = tok_in * model_config["cost_per_1k_input"] / 1000
                    cost_out = tok_out * model_config["cost_per_1k_output"] / 1000

                    result = EvalResult(
                        model=model_name,
                        case_name=case["name"],
                        output=output,
                        latency_ms=latency,
                        input_tokens=tok_in,
                        output_tokens=tok_out,
                        cost=cost_in + cost_out,
                    )

                    # Apply scoring functions
                    if "expected_output_pattern" in case:
                        result.scores["format"] = score_format_compliance(
                            output, case["expected_output_pattern"]
                        )
                    if "expected_json" in case and case["expected_json"]:
                        result.scores["json_valid"] = score_json_validity(output)

                    case_results.append(result)

                except Exception as e:
                    print(f"    {model_name}: ERROR - {e}")
                    case_results.append(EvalResult(
                        model=model_name, case_name=case["name"],
                        output=f"ERROR: {e}", latency_ms=0,
                        input_tokens=0, output_tokens=0, cost=0,
                        scores={"error": 0.0},
                    ))

            results.extend(case_results)

    return results


def compare_to_reference(results: list[EvalResult],
                         paid_models: dict) -> dict:
    """
    For each case, compute quality ratio of free models vs the paid reference.
    Returns {model: {case: quality_ratio}} where 1.0 = same as paid.
    """
    # Group results by case and model
    by_case_model: dict[str, dict[str, list[EvalResult]]] = {}
    for r in results:
        by_case_model.setdefault(r.case_name, {}).setdefault(r.model, []).append(r)

    comparisons = {}
    for case_name, models in by_case_model.items():
        # Find reference (paid model) scores
        ref_scores = {}
        for model_name in paid_models:
            if model_name in models:
                ref_results = models[model_name]
                for score_key in ref_results[0].scores:
                    ref_scores[score_key] = statistics.mean(
                        r.scores.get(score_key, 0) for r in ref_results
                    )

        # Compare free models against reference
        for model_name, model_results in models.items():
            if model_name in paid_models:
                continue
            avg_scores = {}
            for score_key in model_results[0].scores:
                model_avg = statistics.mean(
                    r.scores.get(score_key, 0) for r in model_results
                )
                ref_val = ref_scores.get(score_key, 1.0)
                avg_scores[score_key] = model_avg / ref_val if ref_val > 0 else 0

            comparisons.setdefault(model_name, {})[case_name] = {
                "quality_ratio": statistics.mean(avg_scores.values())
                    if avg_scores else 0,
                "avg_latency_ms": statistics.mean(
                    r.latency_ms for r in model_results
                ),
                "avg_cost": statistics.mean(r.cost for r in model_results),
                "scores": avg_scores,
            }

    return comparisons


def print_report(comparisons: dict, paid_models: dict,
                 results: list[EvalResult]) -> None:
    """Print formatted comparison report."""
    print("\n" + "=" * 60)
    print("     MODEL ALTERNATIVES EVAL REPORT")
    print("=" * 60)

    # Paid model baseline costs
    paid_results = [r for r in results if r.model in paid_models]
    if paid_results:
        avg_paid_cost = statistics.mean(r.cost for r in paid_results)
        avg_paid_latency = statistics.mean(r.latency_ms for r in paid_results)
        print(f"\nPaid baseline: avg ${avg_paid_cost:.4f}/call, "
              f"{avg_paid_latency:.0f}ms latency")

    print("\n" + "-" * 60)
    print(f"{'Model':<35} {'Quality':>8} {'Cost':>8} {'Latency':>10}")
    print("-" * 60)

    for model_name, cases in sorted(
        comparisons.items(),
        key=lambda x: statistics.mean(
            c["quality_ratio"] for c in x[1].values()
        ),
        reverse=True,
    ):
        avg_quality = statistics.mean(
            c["quality_ratio"] for c in cases.values()
        )
        avg_cost = statistics.mean(c["avg_cost"] for c in cases.values())
        avg_latency = statistics.mean(
            c["avg_latency_ms"] for c in cases.values()
        )
        savings = "FREE" if avg_cost == 0 else f"${avg_cost:.4f}"

        grade = "A" if avg_quality >= 0.9 else \
                "B" if avg_quality >= 0.8 else \
                "C" if avg_quality >= 0.7 else \
                "D" if avg_quality >= 0.6 else "F"

        print(f"{model_name:<35} {grade} {avg_quality:>5.0%}  "
              f"{savings:>8} {avg_latency:>8.0f}ms")

    print("-" * 60)
    print("\nGrade scale: A (>=90%) B (>=80%) C (>=70%) D (>=60%) F (<60%)")
    print("Quality = % of paid model's output quality on your actual prompts")
    print("\nRun this eval regularly as models improve and your prompts change.")


if __name__ == "__main__":
    print("Starting model alternatives eval...")
    print(f"Paid models: {list(PAID_MODELS.keys())}")
    print(f"Free models: {list(FREE_MODELS.keys())}")
    print(f"Eval cases: {len(EVAL_CASES)}")

    results = run_eval(EVAL_CASES, PAID_MODELS, FREE_MODELS)
    comparisons = compare_to_reference(results, PAID_MODELS)
    print_report(comparisons, PAID_MODELS, results)

    # Save raw results for further analysis
    output_path = Path("eval_results.json")
    raw = [
        {
            "model": r.model,
            "case": r.case_name,
            "output": r.output[:500],
            "latency_ms": r.latency_ms,
            "cost": r.cost,
            "scores": r.scores,
        }
        for r in results
    ]
    output_path.write_text(json.dumps(raw, indent=2))
    print(f"\nRaw results saved to {output_path}")
```

**Important**: The skill generates this file with EVAL_CASES, PAID_MODELS, and FREE_MODELS populated from the actual codebase analysis. The template above shows the structure — the skill fills in the specifics.

#### 4c: Scoring Criteria by Task Type

The eval harness applies different scoring functions depending on the task type:

| Task Type | Scoring Functions |
|-----------|------------------|
| **classification** | `format_compliance` (output matches enum), exact match vs reference |
| **extraction** | `json_validity`, field-level comparison, `format_compliance` |
| **summarization** | `semantic_similarity` vs reference, `length_ratio` |
| **code-generation** | `format_compliance` (valid syntax), test pass rate if tests exist |
| **code-review** | `semantic_similarity` vs reference, issue detection overlap |
| **embedding** | cosine similarity vs reference embeddings |
| **conversation** | `semantic_similarity`, `length_ratio`, tone consistency |
| **reasoning** | exact answer match, step-validity if chain-of-thought |

#### 4d: Reference Output Collection

To score free models, we need reference outputs from the paid model. The eval harness handles this automatically:

1. First run calls the paid model and stores outputs as references
2. Subsequent runs compare free model outputs against stored references
3. References are saved to `eval_references.json` and can be human-reviewed
4. Stale references (>30 days) are flagged for refresh

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
/model-alternatives v1.0.0
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
 1  src/classify.py:42    anthropic  sonnet-4       classification  $0.012
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
