#!/usr/bin/env node
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative } from "node:path";

const repoRoot = process.cwd();
const sourceRoot = process.argv[2] || "/tmp/the1-cocos-claude-agent";
const skillsRoot = join(repoRoot, ".agents", "skills");
const pluginRoot = join(repoRoot, "plugins", "the1-cocos-codex-agent");
const pluginSkillsRoot = join(pluginRoot, "skills");

const workflowBySkill = new Map([
  ["cocos-playable-architect", "playable-ad-development.md"],
  ["cocos-playable-optimizer", "playable-ad-development.md"],
  ["cocos-rapid-prototyper", "playable-ad-development.md"],
  ["cocos-tutorial-designer", "playable-ad-development.md"],
  ["cocos-conversion-optimizer", "playable-ad-development.md"],
  ["cocos-mobile-optimizer", "mobile-game-development.md"],
  ["cocos-multiplayer-architect", "multiplayer-game-development.md"],
  ["cocos-backend-integrator", "multiplayer-game-development.md"],
]);

function ensureDir(path) {
  mkdirSync(path, { recursive: true });
}

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

function slugFromPath(file) {
  return basename(file, ".md").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function titleFromMarkdown(markdown, fallback) {
  const match = markdown.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : fallback;
}

function firstParagraph(markdown) {
  const withoutTitle = markdown.replace(/^#\s+.+\n+/, "");
  const paragraph = withoutTitle.split(/\n##\s+/)[0].trim();
  return paragraph.replace(/\s+/g, " ");
}

function sanitizeDescription(text, name) {
  const mustUseMatch = text.match(/\bMUST BE USED\s+(for|when|to)\s+([^.;]+)[.;]?/i);
  if (mustUseMatch) {
    const preposition = mustUseMatch[1].toLowerCase();
    const trigger = mustUseMatch[2]
      .replace(/\bClaude\b/g, "Codex")
      .replace(/\bagent\b/gi, "skill")
      .replace(/\s+/g, " ")
      .trim();
    if (preposition === "for") {
      return `Use when working on ${trigger.charAt(0).toLowerCase()}${trigger.slice(1)}.`;
    }
    if (preposition === "to") {
      return `Use when needing to ${trigger.charAt(0).toLowerCase()}${trigger.slice(1)}.`;
    }
    return `Use when ${trigger.charAt(0).toLowerCase()}${trigger.slice(1)}.`;
  }

  let desc = text
    .replace(/\bMUST BE USED\b\s+for\b/gi, "Use when the task involves")
    .replace(/\bMUST BE USED\b/gi, "Use when")
    .replace(/\bClaude\b/g, "Codex")
    .replace(/\bagent\b/gi, "skill")
    .replace(/\s+/g, " ")
    .trim();

  if (!desc.toLowerCase().startsWith("use when")) {
    desc = `Use when Cocos Creator work needs ${name.replace(/^cocos-/, "").replace(/-/g, " ")} expertise. ${desc}`;
  }

  if (desc.length > 500) {
    desc = `${desc.slice(0, 497).replace(/\s+\S*$/, "")}...`;
  }
  return desc;
}

function normalizeBody(markdown, skillName, title) {
  let body = markdown
    .replace(/^#\s+.+\n+/, "")
    .replace(/^## Tools\n(?:- .+|.+)\n+/m, "")
    .replace(/MUST BE USED/g, "Use this skill")
    .replace(/\bClaude agents\b/g, "Codex skills")
    .replace(/\bClaude agent\b/g, "Codex skill")
    .replace(/\bClaude\b/g, "Codex")
    .replace(/Assistant: "I'll use the ([^"]+)"/g, `Assistant: "I will use $${skillName}"`)
    .replace(/Assistant: "Let me use the ([^"]+)"/g, `Assistant: "I will use $${skillName}"`)
    .replace(/^## Delegations$/gm, "## Handoff Guidance");

  const reference = workflowBySkill.get(skillName);
  const referenceSection = reference
    ? `\n## References\nRead \`references/${reference}\` when the task needs the full workflow.\n`
    : "";

  return `# ${title}

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

${body.trim()}
${referenceSection}
## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
`;
}

function skillMarkdownFromAgent(file) {
  const raw = readFileSync(file, "utf8");
  const name = slugFromPath(file);
  const title = titleFromMarkdown(raw, name);
  const description = sanitizeDescription(firstParagraph(raw), name);
  const body = normalizeBody(raw, name, title);

  return {
    name,
    title,
    content: `---\nname: ${name}\ndescription: ${description}\n---\n\n${body}`,
  };
}

function writeBothSkill(skill) {
  for (const root of [skillsRoot, pluginSkillsRoot]) {
    const skillDir = join(root, skill.name);
    ensureDir(skillDir);
    writeFileSync(join(skillDir, "SKILL.md"), skill.content);

    const workflow = workflowBySkill.get(skill.name);
    if (workflow) {
      const workflowSource = join(sourceRoot, "workflows", workflow);
      const referenceDir = join(skillDir, "references");
      ensureDir(referenceDir);
      writeFileSync(join(referenceDir, workflow), readFileSync(workflowSource, "utf8"));
    }
  }
}

function writeCoreSkill() {
  const claude = readFileSync(join(sourceRoot, "CLAUDE.md"), "utf8")
    .replace(/^# .+$/m, "# Cocos Creator Codex Defaults")
    .replace(/\bClaude\b/g, "Codex")
    .replace(/`code-reviewer`/g, "`$cocos-reviewer`");

  const content = `---\nname: cocos-core\ndescription: Use when working in a Cocos Creator project and general Cocos Creator conventions, project structure, TypeScript defaults, or performance expectations should apply.\n---\n\n${claude}\n\n## Codex Usage\n- Use this skill as the baseline context for Cocos Creator work.\n- Use specialist skills for architecture, playable ads, UI, gameplay, networking, build, analytics, security, or optimization tasks.\n`;

  for (const root of [skillsRoot, pluginSkillsRoot]) {
    const dir = join(root, "cocos-core");
    ensureDir(dir);
    writeFileSync(join(dir, "SKILL.md"), content);
  }
}

function writePluginManifest() {
  ensureDir(join(pluginRoot, ".codex-plugin"));
  writeFileSync(
    join(pluginRoot, ".codex-plugin", "plugin.json"),
    JSON.stringify(
      {
        name: "the1-cocos-codex-agent",
        version: "0.1.0",
        description: "Cocos Creator development skills and agent workflows for Codex.",
        skills: "./skills",
        interface: {
          displayName: "The1 Cocos Codex Agent",
          shortDescription: "Cocos Creator expert skills for Codex.",
          developerName: "The1Studio",
          category: "Development",
          capabilities: ["Read", "Write"],
          defaultPrompt: [
            "Use Cocos skills to analyze this Cocos Creator project.",
            "Use playable ad skills when creating or optimizing playable ads.",
          ],
        },
      },
      null,
      2,
    ) + "\n",
  );

  const marketplace = {
    name: "happyword-local-marketplace",
    interface: {
      displayName: "Happyword Local Codex Plugins",
    },
    plugins: [
      {
        name: "the1-cocos-codex-agent",
        source: {
          source: "local",
          path: "./plugins/the1-cocos-codex-agent",
        },
        policy: {
          installation: "AVAILABLE",
          authentication: "ON_INSTALL",
        },
        category: "Development",
      },
    ],
  };
  ensureDir(join(repoRoot, ".agents", "plugins"));
  writeFileSync(join(repoRoot, ".agents", "plugins", "marketplace.json"), JSON.stringify(marketplace, null, 2) + "\n");
}

function writeSubagents() {
  const agents = {
    "cocos_explorer.toml": `name = "cocos_explorer"
description = "Read-only Cocos Creator project explorer for scenes, scripts, assets, dependencies, and build settings."
model_reasoning_effort = "medium"
sandbox_mode = "read-only"

developer_instructions = """
Stay read-only. Map the actual Cocos Creator project before proposing changes.
Inspect package.json, project settings, assets/scripts, scenes, prefabs, build configs, and relevant TypeScript entry points.
Return concise findings with file paths and recommended next skills.
"""
`,
    "cocos_worker.toml": `name = "cocos_worker"
description = "Implementation worker for bounded Cocos Creator tasks after a plan exists."
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"

developer_instructions = """
You are not alone in the codebase. Do not revert edits made by others.
Own only the files assigned in the parent prompt. Follow Cocos Creator 3.x TypeScript and component patterns.
Run available focused verification before returning changed paths and results.
"""
`,
    "cocos_reviewer.toml": `name = "cocos_reviewer"
description = "Read-only reviewer for Cocos Creator correctness, lifecycle, performance, mobile compatibility, security, and validation gaps."
model_reasoning_effort = "high"
sandbox_mode = "read-only"

developer_instructions = """
Review like a Cocos Creator technical lead.
Prioritize runtime bugs, lifecycle misuse, memory leaks, draw-call or asset risks, mobile/platform issues, and missing verification.
Lead with concrete findings and file references. If no issues are found, say so and name residual risk.
"""
`,
    "cocos_docs_researcher.toml": `name = "cocos_docs_researcher"
description = "Researcher for current Cocos Creator, platform, ad-network, and TypeScript documentation."
model_reasoning_effort = "medium"
sandbox_mode = "read-only"

developer_instructions = """
Use official primary sources whenever possible.
Return concise source-backed guidance, exact version assumptions, and links or paths used.
Separate documented facts from implementation recommendations.
"""
`,
    "cocos_playable_auditor.toml": `name = "cocos_playable_auditor"
description = "Read-only auditor for Cocos Creator playable ad package size, load path, CTA flow, and ad-network compliance."
model_reasoning_effort = "high"
sandbox_mode = "read-only"

developer_instructions = """
Audit playable ads for single-HTML readiness, no external resources, size targets, first interaction timing, tutorial clarity, CTA behavior, and network compliance.
Return prioritized findings and concrete validation steps.
"""
`,
  };

  ensureDir(join(repoRoot, ".codex", "agents"));
  for (const [file, content] of Object.entries(agents)) {
    writeFileSync(join(repoRoot, ".codex", "agents", file), content);
  }

  writeFileSync(
    join(repoRoot, ".codex", "config.toml"),
    `[agents]\nmax_threads = 6\nmax_depth = 1\n`,
  );
}

function writeTemplatesAndDocs(skills) {
  ensureDir(join(pluginRoot, "templates"));
  writeFileSync(
    join(pluginRoot, "templates", "AGENTS.md"),
    `# Cocos Creator Codex Instructions

## Project Defaults
- Target Cocos Creator 3.8.x unless the project proves otherwise.
- Prefer TypeScript for all Cocos Creator 3.x work.
- Use component-based architecture with small focused components.
- Consider mobile performance for every gameplay, UI, asset, and animation change.

## Common Flow
- For new projects, start with \`$cocos-team-coordinator\` or \`$cocos-project-architect\`.
- For playable ads, use \`$cocos-playable-architect\` first, then optimizer, tutorial, conversion, and size skills as needed.
- For performance issues, inspect before optimizing and measure after changes.

## Verification
- Run available TypeScript, lint, build, or Cocos export checks after code changes.
- For playable ads, verify package size, no external resources, load time, and FPS.
`,
  );

  ensureDir(join(repoRoot, "docs", "codex-migration"));
  const names = skills.map((skill) => `- \`${skill.name}\`: ${skill.title}`).join("\n");
  writeFileSync(
    join(repoRoot, "docs", "codex-migration", "the1-cocos-codex-agent.md"),
    `# The1 Cocos Claude Agents to Codex Migration

Source: https://github.com/The1Studio/the1-cocos-claude-agent

## Output
- Repo-local skills: \`.agents/skills/cocos-*/SKILL.md\`
- Distributable plugin: \`plugins/the1-cocos-codex-agent\`
- Custom subagents: \`.codex/agents/*.toml\`
- Cocos project instruction template: \`plugins/the1-cocos-codex-agent/templates/AGENTS.md\`

## Design
The upstream Claude agents are expert prompt documents. In Codex, they map best to Skills rather than one subagent per expert. Skills are lightweight, discoverable by name and description, and can be invoked with \`$skill-name\`. A small set of custom subagents handles read-only exploration, implementation, review, documentation research, and playable auditing.

## Skills
${names}

## Recommended Usage
\`\`\`text
Use $cocos-team-coordinator to inspect this Cocos Creator project and recommend the skill stack.
Use $cocos-playable-architect to plan a match-3 playable ad.
Use $cocos-performance-optimizer to analyze frame drops and recommend measurable fixes.
Spawn cocos_explorer to inspect the project, then use $cocos-project-architect for the plan.
\`\`\`

## Validation
Run:
\`\`\`bash
node scripts/validate-codex-agent-port.mjs
\`\`\`
`,
  );
}

const agentFiles = walk(join(sourceRoot, "agents")).filter((file) => file.endsWith(".md"));
const skills = agentFiles.map(skillMarkdownFromAgent).sort((a, b) => a.name.localeCompare(b.name));

for (const skill of skills) {
  writeBothSkill(skill);
}
writeCoreSkill();
writePluginManifest();
writeSubagents();
writeTemplatesAndDocs(skills);

console.log(`Generated ${skills.length} Cocos skills plus cocos-core from ${relative(repoRoot, sourceRoot) || sourceRoot}.`);
