---
name: aws-manifest
version: 1.0.0
description: >
  Generates an AWS application manifest (docs/aws-manifest.md) declaring the
  project's infrastructure needs for provisioning by bismuth-aws-org.
argument-hint: "[application type, e.g. static-site, api, fullstack]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(git remote *), AskUserQuestion
---

# AWS Application Manifest Generator

Generate a `docs/aws-manifest.md` file that declares this project's AWS infrastructure needs, following the [AWS Manifest Spec v1](https://github.com/janewilkin/bismuth-aws-org/blob/main/docs/aws-manifest-spec.md).

**First**, print the version banner:
```
/aws-manifest v1.0.0
```

## Purpose

The manifest is consumed by [bismuth-aws-org](https://github.com/janewilkin/bismuth-aws-org) to provision Terraform/Terragrunt infrastructure. It must be accurate, complete, and follow the spec exactly.

## Process

### 1. Gather Project Context

Read these files to understand the project:
- `CLAUDE.md` — project overview, architecture, conventions
- `pyproject.toml` or `setup.py` or `package.json` — project metadata
- `README.md` — if it exists
- Any existing `docs/aws-manifest.md` — if updating an existing manifest
- Source code structure — `ls src/` or equivalent

Determine from git remote:
```bash
git remote get-url origin 2>/dev/null || echo "no remote"
```

### 2. Determine Application Type

If `$ARGUMENTS` provides an application type, use it. Otherwise infer from the codebase:

| Codebase signals | Application type |
|------------------|-----------------|
| Static HTML/CSS/JS output, SSG framework | `static-site` |
| FastAPI, Flask, Express, API routes | `api` |
| Frontend + backend in same repo | `fullstack` |
| Background jobs, queue consumers, cron | `worker` |
| ETL, data processing, pipelines | `data-pipeline` |

If the type cannot be determined, ask the user.

### 3. Gather Infrastructure Details

Ask the user the following questions (skip any that are already answered by the codebase or arguments):

**Required information:**
- Project name (human-readable)
- Project tag (short kebab-case, used in resource naming like `bismuth-{tag}-{env}-{region}`)
- Environments needed (QA, Production, Staging — comma-separated)
- Primary AWS region (default: `us-east-1`)
- Deployment method (CLI tool, CI/CD, manual)
- Domains (if any, per environment)

**Per application type, also ask about:**

**static-site:**
- Custom domains per environment
- Auth requirements (public, basic auth, Cognito)
- Expected content size and traffic

**api:**
- API Gateway vs ALB
- Lambda vs ECS/Fargate
- Database needs (RDS, DynamoDB, none)
- Expected request volume

**fullstack:**
- Frontend hosting (S3+CloudFront or same server)
- Backend runtime (Lambda, ECS)
- Database needs
- Auth method

**worker:**
- Queue type (SQS, SNS, EventBridge)
- Runtime (Lambda, ECS)
- Trigger mechanism

**data-pipeline:**
- Data sources and sinks
- Processing runtime (Lambda, Glue, Step Functions)
- Schedule/trigger

### 4. Generate the Manifest

Create `docs/aws-manifest.md` with ALL required sections from the spec.

#### File Header

```markdown
<!-- manifest-spec: v1 -->
# AWS Application Manifest — {Project Name}

> For use by [bismuth-aws-org](https://github.com/janewilkin/bismuth-aws-org) to provision infrastructure.
```

#### Required Sections

**All manifests must include these sections in order:**

1. **Application Overview** — metadata table with all 7 required fields
2. **Hosting Requirements** — service categories with per-environment resource tables
3. **Deployment Integration** — config mapping, publisher behavior, IAM permissions
4. **Dependencies** — status tracking table (use ❌ Not built for new infrastructure)
5. **Cost Estimate** — per-resource costs with per-environment and grand totals
6. **Non-Requirements** — explicitly state what is NOT needed

#### Recommended Optional Sections (include when relevant)

- **Proposed Terragrunt Layout** — where infra lives in bismuth-aws-org
- **Expected Module Outputs** — Terraform outputs the app needs
- **Auth Progression Plan** — if auth evolves over time

### 5. Apply Conventions

These conventions are mandatory:

| Convention | Rule |
|-----------|------|
| Bucket naming | `bismuth-{project-tag}-{env}-{region}` |
| Resource tagging | `Project = "bismuth-{project-tag}"` |
| Environment names | `qa` and `prod` (lowercase) in resource names |
| DNS zone references | Use bismuth-aws-org paths if zones exist |
| Design principles | No cross-account access; workload isolation; minimize costs |

### 6. Validate and Report

After writing the manifest, verify:
- [ ] All 6 required sections are present
- [ ] Application Overview table has all 7 fields
- [ ] Bucket names follow naming convention
- [ ] Every service has per-environment resource tables
- [ ] Dependencies table uses correct status indicators (✅ ⏳ ❌ ❓)
- [ ] Cost estimate includes per-environment and grand total
- [ ] Non-Requirements section explicitly states what's excluded
- [ ] `<!-- manifest-spec: v1 -->` version tag is at the top
- [ ] No cross-account access patterns (Design Principle #1)

## Output

Report:

### Manifest Generated
- **Location**: `docs/aws-manifest.md`
- **Application type**: {type}
- **Environments**: {list}
- **Services**: {list of AWS service categories used}

### Cost Summary
- Per environment: ~${X}/mo
- Total: ~${Y}/mo

### Next Steps
1. Review the manifest for accuracy
2. Commit and push to the project repo
3. Open an issue or PR in bismuth-aws-org referencing this manifest

If any information was assumed or estimated, call it out explicitly so the user can verify.
