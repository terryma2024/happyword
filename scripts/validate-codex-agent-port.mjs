#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const expectedAgentCount = 29;
const requiredSubagents = [
  "cocos_explorer.toml",
  "cocos_worker.toml",
  "cocos_reviewer.toml",
  "cocos_docs_researcher.toml",
  "cocos_playable_auditor.toml",
];

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function assertExists(path, label) {
  if (!existsSync(path)) {
    fail(`${label} missing at ${path}`);
    return false;
  }
  return true;
}

const skillsRoot = join(repoRoot, ".agents", "skills");
const pluginRoot = join(repoRoot, "plugins", "the1-cocos-codex-agent");
const pluginSkillsRoot = join(pluginRoot, "skills");

assertExists(skillsRoot, "repo-local skills root");
assertExists(pluginSkillsRoot, "plugin skills root");
assertExists(join(pluginRoot, ".codex-plugin", "plugin.json"), "plugin manifest");
assertExists(join(pluginRoot, "templates", "AGENTS.md"), "Cocos AGENTS template");
assertExists(join(repoRoot, ".agents", "plugins", "marketplace.json"), "marketplace file");

const skillFiles = existsSync(skillsRoot)
  ? walk(skillsRoot).filter((file) => file.endsWith("SKILL.md"))
  : [];
const pluginSkillFiles = existsSync(pluginSkillsRoot)
  ? walk(pluginSkillsRoot).filter((file) => file.endsWith("SKILL.md"))
  : [];

const expectedSkillCount = expectedAgentCount + 1;
if (skillFiles.length !== expectedSkillCount) {
  fail(`expected ${expectedSkillCount} repo-local skills, found ${skillFiles.length}`);
}
if (pluginSkillFiles.length !== expectedSkillCount) {
  fail(`expected ${expectedSkillCount} plugin skills, found ${pluginSkillFiles.length}`);
}

for (const file of skillFiles) {
  const content = readFileSync(file, "utf8");
  if (!/^---\nname: [a-z0-9-]+\ndescription: .+\n---\n/m.test(content)) {
    fail(`invalid skill frontmatter: ${file}`);
  }
  if (/^## Tools$/m.test(content)) {
    fail(`Claude Tools section still present: ${file}`);
  }
  if (/MUST BE USED/.test(content)) {
    fail(`Claude MUST BE USED wording still present: ${file}`);
  }
}

for (const file of requiredSubagents) {
  assertExists(join(repoRoot, ".codex", "agents", file), `subagent ${file}`);
}

const plugin = JSON.parse(readFileSync(join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"));
if (plugin.name !== "the1-cocos-codex-agent") {
  fail("plugin manifest name mismatch");
}
if (plugin.skills !== "./skills") {
  fail("plugin manifest skills path mismatch");
}

if (!process.exitCode) {
  console.log(`OK: ${skillFiles.length} skills, ${requiredSubagents.length} subagents, plugin manifest, marketplace, and template validated.`);
}
