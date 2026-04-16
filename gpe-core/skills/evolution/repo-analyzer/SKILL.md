# SKILL: repo-analyzer
# GPE Domain: Evolution
# Purpose: Deep-analyze a single GitHub repo and extract GPE improvements.
# Trigger: "analyze repo", "repo analysieren", "extract from repo", "what can we learn from X"

## Mission

Perform a surgical analysis of one GitHub repository.
Not a summary. A teardown for extractable value.
Output: Ranked insights + pre-formatted LEARNING_QUEUE entries.

## Execution Steps

1. **Load Context**
   - Read: `gpe-core/briefs/templates/brief_repo_analysis.yaml` (the analysis brief)
   - Read: `gpe-core/evolution/REPO_WATCHLIST.yaml` (find the repo's listed focus areas)
   - Read: `gpe-core/SKILL_INDEX.md` (what GPE skills could be improved)
   - Identify: Target domain and which GPE skill this repo targets

2. **Build Analysis Brief**
   - Fill out `brief_repo_analysis.yaml` for this specific repo
   - Set `gpe_target_skill` based on REPO_WATCHLIST focus areas
   - Set `repo_files_to_read` to the most architecturally significant files

3. **Read Repo Files (Priority Order)**
   - README.md → Understand purpose and key features
   - Core architecture file (ARCHITECTURE.md, docs/design.md, etc.)
   - Top 3 implementation files (identify via file size + naming)
   - Any YAML/JSON config or schema files
   - CHANGELOG or RELEASES (shows evolution trajectory)

4. **Extraction Framework**
   Apply these lenses to the repo:

   | Lens | Question |
   |------|----------|
   | Architecture | What structural pattern could improve GPE's layout? |
   | Skill Pattern | What execution pattern could improve a GPE skill? |
   | Brief/Template | What prompt/config structure could improve GPE briefs? |
   | Failure Handling | How does this repo handle errors? Better than FAILURE_REGISTRY? |
   | Review/QA | Does it have a quality gate better than GPE's current gates? |
   | Self-Improvement | Does it have any self-learning or auto-patching mechanisms? |

5. **Generate Output**
   - Complete the brief_repo_analysis.yaml output format
   - Pre-format LEARNING_QUEUE.yaml entries for each insight
   - Tag each insight: [IMMEDIATE WIN] or [FUTURE] or [SKIP]

## Review Gate

Before delivering output:
- [ ] At least 1 IMMEDIATE WIN identified (LOW effort + HIGH impact)
- [ ] Every insight has a specific GPE target file
- [ ] LEARNING_QUEUE entries are paste-ready
- [ ] Skip list explains WHY (not just what to skip)
- [ ] No insight is vague or generic
