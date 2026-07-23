# Open-Source Model Reference

Candidate models by task type for `/model-alternatives`. Benchmarks
change rapidly — verify current scores at open-llm-leaderboard before
relying on them.

## Code Generation / Editing

| Model | Params | HumanEval | Strengths | Run With |
|-------|--------|-----------|-----------|----------|
| DeepSeek-Coder-V2 | 236B (MoE) | 90.2% | Near-frontier coding, strong reasoning | vLLM, together.ai |
| Qwen2.5-Coder | 32B | 85.1% | Strong code completion, instruction following | Ollama, vLLM |
| CodeLlama | 70B | 67.8% | Code infilling, long context | Ollama, vLLM |
| StarCoder2 | 15B | 52.7% | 600+ languages, code completion | Ollama, HuggingFace |
| DeepSeek-R1-Distill | 70B | ~85% | Reasoning-heavy coding, chain-of-thought | Ollama, vLLM |
| Phi-4 | 14B | 82.6% | Small footprint, strong for size | Ollama, Cloudflare |

## General Text / Summarization / Classification

| Model | Params | MMLU | Strengths | Run With |
|-------|--------|------|-----------|----------|
| Llama 3.3 | 70B | 86.0% | General purpose, strong instruction following | Ollama, Groq, vLLM |
| Qwen2.5 | 72B | 85.3% | Multilingual, long context (128k) | Ollama, vLLM |
| Mistral Large | 123B | 84.0% | Strong reasoning, function calling | vLLM, Mistral API (free tier) |
| Mixtral 8x22B | 176B MoE | 77.8% | Fast inference (MoE), good general | Ollama, together.ai |
| Gemma 2 | 27B | 75.2% | Small, Google quality | Ollama, Cloudflare |
| Phi-4 | 14B | 84.8% | Tiny footprint, punches above weight | Ollama, Cloudflare |
| Llama 3.2 | 3B | 63.4% | Runs on CPU, edge deployment | Ollama, phone/laptop |

## Structured Extraction / JSON Output

| Model | Params | Notes | Run With |
|-------|--------|-------|----------|
| Qwen2.5 | 7B-72B | Native JSON mode, function calling | Ollama, vLLM |
| Llama 3.3 | 70B | Tool use trained, structured output | Ollama, Groq |
| Hermes 3 (Nous) | 70B | Fine-tuned for function calling and JSON | Ollama, vLLM |
| Mistral Nemo | 12B | Built-in function calling | Ollama, Mistral free tier |

## Embeddings / Search

| Model | Dims | MTEB Avg | Run With |
|-------|------|----------|----------|
| Nomic Embed v1.5 | 768 | 62.3% | Ollama, HuggingFace |
| BGE-large-en-v1.5 | 1024 | 64.2% | HuggingFace, local |
| GTE-Qwen2 | 1536 | 67.2% | HuggingFace, local |
| Snowflake Arctic Embed | 1024 | 66.7% | HuggingFace, Replicate |
| mxbai-embed-large | 1024 | 64.6% | Ollama |

## Free Hosting Options

| Provider | Free Tier | Models Available | Limits |
|----------|-----------|-----------------|--------|
| **Ollama** (local) | Unlimited | All open-source | Limited by hardware |
| **Groq** | Yes | Llama 3.3 70B, Mixtral, Gemma 2 | ~30 req/min, 14.4k tokens/min |
| **HuggingFace Inference** | Yes | Most popular models | Rate limited, queue-based |
| **Cloudflare Workers AI** | 10k tokens/day | Llama, Phi, Gemma | Low limits but $0 |
| **OpenRouter** | Some free models | Varies | Per-model limits |
| **Google AI Studio** | Yes | Gemma 2 | Generous free tier |
