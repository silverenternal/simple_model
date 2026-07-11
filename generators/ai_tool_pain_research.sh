#!/usr/bin/env bash
set -euo pipefail

OUT="generated/research/ai-tool-pain-points.json"
MARKDOWN=""
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o) OUT="$2"; shift 2 ;;
    --markdown) MARKDOWN="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$MARKDOWN" ]] || MARKDOWN="${OUT%.json}.md"
mkdir -p "$(dirname "$OUT")" "$(dirname "$MARKDOWN")"

report=$(jq -n '
  def source($id;$title;$url;$kind;$claim): {id:$id,title:$title,url:$url,kind:$kind,claim:$claim};
  def pain($id;$name;$evidence;$response;$artifacts;$metric): {id:$id,name:$name,evidence:$evidence,macro_wisdom_response:$response,deterministic_artifacts:$artifacts,success_metric:$metric};
  {
    schema_version:"1.0", ok:true, as_of:"2026-07-10",
    method:{scope:"public product documentation plus primary empirical research",network_at_runtime:false,interpretation:"Product documentation is used to establish product behavior and recommended workflows; surveys and studies establish cross-product pain. Competitive gaps are explicit inferences, not vendor defect claims."},
    sources:[
      source("github-copilot-best-practices";"Best practices for using GitHub Copilot to work on tasks";"https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks/best-practices-for-using-copilot-to-work-on-tasks";"official-doc";"Complex broad refactors, legacy dependencies, deep domain tasks, and large design-consistent changes require caution; repository instructions and tests improve results."),
      source("cursor-rules";"Cursor Rules";"https://docs.cursor.com/context/rules";"official-doc";"Models do not retain memory between completions, so repository rules inject persistent context."),
      source("cursor-indexing";"Securely indexing large codebases";"https://cursor.com/blog/secure-codebase-indexing";"official-engineering";"Large repositories can take hours to index naively; semantic search availability depends on index progress."),
      source("devin-knowledge";"Devin Knowledge";"https://docs.devin.ai/product-guides/knowledge";"official-doc";"Repository onboarding needs an initial knowledge-transfer investment and continued maintenance of scoped knowledge."),
      source("replit-build-agent";"Build with Replit Agent";"https://docs.replit.com/learn/build-with-agent";"official-doc";"Users are advised to specify constraints, plan, add context, review/test, and use checkpoints when behavior breaks or changes exceed intent."),
      source("replit-testing";"Replit Agent App Testing";"https://docs.replit.com/references/agent/app-testing";"official-doc";"Automated browser testing is selective, may require human takeover, has framework limits, and incurs usage cost."),
      source("stackoverflow-2025";"2025 Stack Overflow Developer Survey - AI";"https://survey.stackoverflow.co/2025/ai";"survey";"46% distrust AI accuracy versus 33% who trust it; only 3% highly trust it."),
      source("metr-2025";"Measuring the Impact of Early-2025 AI on Experienced Open-Source Developer Productivity";"https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/";"randomized-controlled-trial";"Experienced maintainers took 19% longer with early-2025 AI tools in the studied setting."),
      source("dora-2025";"DORA 2025 State of AI-assisted Software Development";"https://research.google/pubs/dora-2025-state-of-ai-assisted-software-development-report/";"industry-research";"AI amplifies both strengths and dysfunctions in software organizations."),
      source("swe-evo";"SWE-EVO: Benchmarking Coding Agents in Long-Horizon Software Evolution Scenarios";"https://arxiv.org/abs/2512.18470";"primary-research";"Long-horizon multi-file evolution remains substantially harder than isolated issue solving."),
      source("swe-bench-pro";"SWE-Bench Pro";"https://arxiv.org/abs/2509.16941";"primary-research";"Enterprise-scale long-horizon tasks remain below 25% Pass@1 in the reported evaluation."),
      source("anthropic-harness";"Harness design for long-running application development";"https://www.anthropic.com/engineering/harness-design-long-running-apps";"official-engineering";"Generator-evaluator loops and harness design materially affect long-running agent reliability.")
    ],
    tools:[
      {name:"GitHub Copilot",strengths:["IDE and GitHub integration","semantic code search","coding agent and review"],operational_dependency:["well-scoped issues","repository instructions","human review and tests"],sources:["github-copilot-best-practices"]},
      {name:"Cursor",strengths:["AI-native editor","semantic repository index","rules and memories"],operational_dependency:["index freshness","rule quality","context selection"],sources:["cursor-rules","cursor-indexing"]},
      {name:"Devin",strengths:["autonomous workspace","organizational knowledge","repeatable prompt macros"],operational_dependency:["knowledge onboarding","trigger quality","knowledge maintenance"],sources:["devin-knowledge"]},
      {name:"Replit Agent",strengths:["integrated build/deploy","browser testing","checkpoints"],operational_dependency:["clear constraints","supported test surface","human takeover and usage budget"],sources:["replit-build-agent","replit-testing"]},
      {name:"Claude Code",strengths:["repository agent","tool execution","long-running harness support"],operational_dependency:["test oracle","persistent memory","orchestration quality"],sources:["anthropic-harness"]},
      {name:"Windsurf",strengths:["agentic IDE","repository context","workflow automation"],operational_dependency:["context and trust calibration","verification workflow"],sources:["stackoverflow-2025","dora-2025"]},
      {name:"Codex",strengths:["terminal and repository agent","parallel task execution","skill/plugin extensibility"],operational_dependency:["repository instructions","testable acceptance criteria","tool permissions and verification"],sources:["swe-evo","swe-bench-pro"]}
    ],
    pain_points:[
      pain("context-decay";"Repository context decays or becomes stale";["cursor-rules","cursor-indexing","devin-knowledge"];"Build content-addressed structural facts, semantic graph deltas, scoped context packs, and drift gates; regenerate facts from code instead of relying on conversational memory.";["symbol index","semantic graph","graph diff","multi-file struct","CBOM"];"same input yields identical context hash and stale facts are detected"),
      pain("long-horizon-coherence";"Long multi-file evolution loses global coherence";["swe-evo","swe-bench-pro"];"Compile intent into typed macro operators, search bounded compositions, execute transactionally, and prove postconditions after every stage.";["Macro Operator IR","composition analyzer","plan search","transaction log","proof bundle"];"zero undeclared writes and all stage invariants pass"),
      pain("trust-gap";"Developers cannot cheaply trust generated changes";["stackoverflow-2025","github-copilot-best-practices"];"Replace confidence prose with evidence classes, false-safe-apply gates, affected-test selection, replay hashes, and explicit deny states.";["precondition report","accuracy scorecard","gauntlet","proof bundle","release SLO"];"false-safe-apply count equals zero"),
      pain("half-built-onboarding";"Existing large projects require costly knowledge transfer";["devin-knowledge","github-copilot-best-practices"];"Automatically ingest structure, tier parsers, reconstruct static and dynamic interfaces, classify evidence gaps, and emit an ordered takeover protocol.";["takeover init","parser tiers","semantic graph","dynamic edges","interface stability commitment"];"bounded AI clarifications and complete deterministic phase evidence"),
      pain("interface-regression";"Broad changes can silently violate public contracts";["github-copilot-best-practices","dora-2025"];"Issue versioned interface stability commitments, map affected tests and owners, deny unsupported breaking changes, and generate compatibility macros.";["interface scan","stability commitment","release contract","PR gate"];"all public interfaces have status, policy, owner requirement, and test evidence"),
      pain("verification-cost";"Full validation is slow and agents may choose tests heuristically";["replit-testing","metr-2025"];"Use semantic test-impact DAGs, content-addressed caches, deterministic concurrency scheduling, and escalation from affected to full checks by risk.";["test impact DAG","test cache","worker pool","performance SLO"];"no missed impacted tests in benchmark corpus and warm checks meet SLO"),
      pain("rollback-ambiguity";"Recovery depends on coarse checkpoints or human judgment";["replit-build-agent"];"Record exact read/write sets, pre/post hashes, inverse operations, resume tokens, and rollback verification per macro transaction.";["transaction log","rollback metadata","outcome ledger"];"rollback restores all recorded hashes"),
      pain("prompt-governance";"Natural-language instructions are incomplete, oversized, or inconsistently retrieved";["cursor-rules","github-copilot-best-practices"];"Compile machine-decidable intent into predicates and policies; send only unresolved leaf questions to AI with typed inputs and outputs.";["intent model","policy evaluation","bounded AI queue"];"structural decisions made by AI equals zero"),
      pain("productivity-variance";"AI can amplify weak process and increase rework";["metr-2025","dora-2025"];"Measure outcome deltas by macro family, promote only repeatably beneficial operators, and automatically demote regressions.";["outcome ledger","family ranker","promotion gate","benchmark gauntlet"];"promoted macros pass value, safety, generality, and rollback thresholds")
    ],
    macro_wisdom_bets:[
      {id:"deterministic-takeover",moat:"Turn undocumented repositories into versioned structural evidence and interface commitments before AI edits."},
      {id:"structural-memory",moat:"Use hashes and graph deltas as durable project memory independent of model, session, or IDE."},
      {id:"proof-carrying-codemods",moat:"Every optimization ships with preconditions, write set, affected tests, postconditions, and rollback proof."},
      {id:"macro-generating-macros",moat:"Mine repeated graph motifs into review-only templates and promote them through observed outcomes."},
      {id:"dynamic-code-governance",moat:"Fuse static structure, framework resolvers, configuration, and runtime observations into explicit trust states."},
      {id:"interface-stability-ledger",moat:"Make compatibility promises machine-readable and gate changes against them."},
      {id:"risk-proportional-validation",moat:"Select and parallelize tests deterministically while retaining a provable escalation path to full validation."},
      {id:"model-portable-control-plane",moat:"Expose the same deterministic decisions to Codex, Claude Code, Cursor, Copilot, CI, and humans through JSON/CLI/MCP."}
    ],
    strategic_conclusion:"The defensible category is not another code-generating agent. It is a model-portable deterministic control plane that converts a half-built repository into structural memory, bounded transformations, interface promises, and replayable evidence.",
    automation_model:{macro_dominant:true, ai_role:"summarize evidence and answer bounded domain-intent questions", ai_decides_structure:false, ai_may_promote_or_apply_macros:false}
  }
  | .summary={tools:(.tools|length),sources:(.sources|length),pain_points:(.pain_points|length),macro_wisdom_bets:(.macro_wisdom_bets|length),all_pains_mapped:all(.pain_points[];.macro_wisdom_response!="" and (.deterministic_artifacts|length)>0),all_sources_linked:all(.sources[];(.url|startswith("https://")))}')

printf '%s\n' "$report" > "$OUT"
jq -r '
  "# AI Coding Tools: Pain Points and Macro Wisdom", "",
  "Research snapshot: " + .as_of, "",
  .strategic_conclusion, "",
  "## Cross-product Pain Points", "",
  (.pain_points[] | "### " + .name, "", .macro_wisdom_response, "", "Evidence: " + (.evidence|join(", ")), ""),
  "## Product Bets", "", (.macro_wisdom_bets[] | "- **" + .id + "**: " + .moat), "",
  "## Sources", "", (.sources[] | "- [" + .title + "](" + .url + ") - " + .claim)
' "$OUT" > "$MARKDOWN"

if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"AI tool research tools=" + (.summary.tools|tostring) + " pain_points=" + (.summary.pain_points|tostring)' <<<"$report"; fi

