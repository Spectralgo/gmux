#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const backlogPath = path.join(repoRoot, "ai_docs", "backlog.yaml");
const marker = "<!-- Managed-by: ai_docs -->";
const freeformHeading = "## Freeform notes";

function usage() {
  console.error("Usage: node scripts/sync-ai-docs.mjs --dry-run | --sync");
  process.exit(1);
}

const argv = new Set(process.argv.slice(2));
const dryRun = argv.has("--dry-run");
const sync = argv.has("--sync");

if ((dryRun && sync) || (!dryRun && !sync)) {
  usage();
}

function readJsonLikeYaml(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(
      `${path.relative(repoRoot, filePath)} must be JSON-compatible YAML. ${error.message}`
    );
  }
}

function writeJsonLikeYaml(filePath, data) {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function runGhApi(args, options = {}) {
  const output = execFileSync("gh", ["api", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    input: options.input,
    stdio: options.capture === false ? "inherit" : ["pipe", "pipe", "pipe"],
  });
  return output;
}

function ghJson(args) {
  const output = runGhApi(args);
  return output.trim() ? JSON.parse(output) : null;
}

function requestJson(method, endpoint, payload) {
  if (dryRun) {
    logAction(`${method} ${endpoint}`, payload);
    return null;
  }

  const output = runGhApi([endpoint, "--method", method, "--input", "-"], {
    input: JSON.stringify(payload),
  });
  return output.trim() ? JSON.parse(output) : null;
}

function logAction(label, payload) {
  console.log(`DRY-RUN ${label}`);
  if (payload) {
    console.log(JSON.stringify(payload, null, 2));
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function relativeDocUrl(repo, branch, docPath) {
  return `https://github.com/${repo}/blob/${branch}/${docPath}`;
}

function issueTitle(item) {
  return `[${item.id}] ${item.title}`;
}

function issueRef(item, kind) {
  const number = item.github?.issue_number;
  if (number) {
    return `#${number}`;
  }
  return `[${kind} ${item.id}]`;
}

function listSection(items) {
  if (!items || items.length === 0) {
    return "- None";
  }
  return items.map((item) => `- ${item}`).join("\n");
}

function preserveFreeformNotes(existingBody) {
  if (!existingBody || !existingBody.includes(freeformHeading)) {
    return "";
  }

  const [, tail] = existingBody.split(freeformHeading, 2);
  return `${freeformHeading}${tail}`;
}

function normalizeBody(body) {
  return body.trim().replace(/\r\n/g, "\n");
}

function milestoneBody(milestone) {
  return [
    marker,
    `<!-- Item-ID: ${milestone.id} -->`,
    `# ${milestone.title}`,
    "",
    milestone.description,
    "",
    "## Exit criteria",
    listSection(milestone.exit_criteria),
  ].join("\n");
}

function epicBody(epic, backlog, context, existingBody) {
  const milestone = context.milestoneById.get(epic.milestone);
  const stories = epic.story_refs.map((storyId) => context.storyById.get(storyId));
  const tasks = epic.task_refs.map((taskId) => context.taskById.get(taskId));
  const freeform = preserveFreeformNotes(existingBody);

  const storyLines = stories.map((story) => {
    const url = relativeDocUrl(context.repo, context.branch, story.doc);
    return `- [${story.id} - ${story.title}](${url})`;
  });

  const taskLines = tasks.map((task) => {
    const ref = task.github?.issue_number ? `#${task.github.issue_number}` : task.id;
    return `- ${ref} — ${task.title}`;
  });

  const referenceLines = [
    `[Milestone doc](${relativeDocUrl(context.repo, context.branch, milestone.doc)})`,
    `[Epic doc](${relativeDocUrl(context.repo, context.branch, epic.doc)})`,
    ...epic.references.map((ref) =>
      ref.startsWith("http") ? ref : `[${ref}](${relativeDocUrl(context.repo, context.branch, ref)})`
    ),
  ];

  const sections = [
    marker,
    `<!-- Item-ID: ${epic.id} -->`,
    `# ${issueTitle(epic)}`,
    "",
    `Milestone: **${milestone.id} — ${milestone.title}**`,
    "",
    "## Summary",
    epic.summary,
    "",
    "## Stories",
    storyLines.join("\n"),
    "",
    "## Deliverables",
    listSection(epic.acceptance_criteria),
    "",
    "## Task breakdown",
    taskLines.join("\n"),
    "",
    "## References",
    listSection(referenceLines),
  ];

  if (freeform) {
    sections.push("", freeform.trim());
  } else {
    sections.push("", freeformHeading, "- Add non-canonical notes here. The sync tool preserves this section.");
  }

  return sections.join("\n");
}

function taskBody(task, context, existingBody) {
  const milestone = context.milestoneById.get(task.milestone);
  const epic = context.epicById.get(task.epic);
  const agentContractUrl = relativeDocUrl(context.repo, context.branch, "ai_docs/agent-contract.md");
  const storyLines = task.story_refs.map((storyId) => {
    const story = context.storyById.get(storyId);
    const url = relativeDocUrl(context.repo, context.branch, story.doc);
    return `- [${story.id} - ${story.title}](${url})`;
  });

  const dependencyLines = task.depends_on.map((taskId) => {
    const dependency = context.taskById.get(taskId);
    const ref = dependency.github?.issue_number ? `#${dependency.github.issue_number}` : dependency.id;
    return `${ref} — ${dependency.title}`;
  });

  const referenceLines = [
    `[Agent contract](${agentContractUrl})`,
    `[Milestone doc](${relativeDocUrl(context.repo, context.branch, milestone.doc)})`,
    `[Epic doc](${relativeDocUrl(context.repo, context.branch, epic.doc)})`,
    ...task.story_refs.map((storyId) => {
      const story = context.storyById.get(storyId);
      return `[${story.id}](${relativeDocUrl(context.repo, context.branch, story.doc)})`;
    }),
    ...task.references.map((ref) =>
      ref.startsWith("http") ? ref : `[${ref}](${relativeDocUrl(context.repo, context.branch, ref)})`
    ),
  ];

  const freeform = preserveFreeformNotes(existingBody);
  const epicRef = epic.github?.issue_number ? `#${epic.github.issue_number}` : epic.id;

  const sections = [
    marker,
    `<!-- Item-ID: ${task.id} -->`,
    `Milestone: **${milestone.id} — ${milestone.title}**`,
    `Epic: **${epicRef} — ${epic.title}**`,
    "",
    "## Story refs",
    storyLines.join("\n"),
    "",
    "## Outcome",
    task.outcome,
    "",
    "## Problem",
    task.problem,
    "",
    "## In scope",
    listSection(task.scope),
    "",
    "## Out of scope",
    listSection(task.non_goals),
    "",
    "## Dependencies",
    listSection(dependencyLines),
    "",
    "## Implementation notes",
    listSection(task.implementation_notes),
    "",
    "## Acceptance criteria",
    listSection(task.acceptance_criteria),
    "",
    "## Verification",
    listSection(task.verification),
    "",
    "## Repo constraints",
    listSection(task.repo_constraints),
    "",
    "## References",
    listSection(referenceLines),
  ];

  if (freeform) {
    sections.push("", freeform.trim());
  } else {
    sections.push("", freeformHeading, "- Add non-canonical notes here. The sync tool preserves this section.");
  }

  return sections.join("\n");
}

function fetchGithubState(repo) {
  return {
    labels: ghJson([`repos/${repo}/labels?per_page=100`]) ?? [],
    milestones: ghJson([`repos/${repo}/milestones?state=all&per_page=100`]) ?? [],
    issues: (ghJson([`repos/${repo}/issues?state=all&per_page=100`]) ?? []).filter(
      (issue) => !issue.pull_request
    ),
  };
}

function syncLabel(repo, desired, existingMap) {
  const existing = existingMap.get(desired.name);
  if (!existing) {
    requestJson("POST", `repos/${repo}/labels`, desired);
    return;
  }

  if (existing.color === desired.color && (existing.description ?? "") === desired.description) {
    return;
  }

  requestJson("PATCH", `repos/${repo}/labels/${encodeURIComponent(desired.name)}`, desired);
}

function syncMilestone(repo, milestone, existingMap) {
  const existing = existingMap.get(milestone.title);
  const payload = {
    title: milestone.title,
    description: milestoneBody(milestone),
    state: "open",
  };

  if (!existing) {
    const created = requestJson("POST", `repos/${repo}/milestones`, payload);
    if (created) {
      milestone.github = {
        number: created.number,
        url: created.html_url,
      };
    }
    return;
  }

  milestone.github = {
    number: existing.number,
    url: existing.html_url,
  };

  if ((existing.description ?? "") === payload.description && existing.title === payload.title) {
    return;
  }

  requestJson("PATCH", `repos/${repo}/milestones/${existing.number}`, payload);
}

function findExistingIssue(item, existingIssues) {
  if (item.github?.issue_number) {
    return existingIssues.find((issue) => issue.number === item.github.issue_number) ?? null;
  }
  return existingIssues.find((issue) => issue.title === issueTitle(item)) ?? null;
}

function syncIssue(repo, item, existingIssues, body, labels, milestoneNumber) {
  const existing = findExistingIssue(item, existingIssues);
  const payload = {
    title: issueTitle(item),
    body,
    labels,
    milestone: milestoneNumber,
  };

  if (!existing) {
    const created = requestJson("POST", `repos/${repo}/issues`, payload);
    if (created) {
      item.github = {
        issue_number: created.number,
        url: created.html_url,
      };
      existingIssues.push(created);
    }
    return;
  }

  item.github = {
    issue_number: existing.number,
    url: existing.html_url,
  };

  const existingLabels = (existing.labels ?? []).map((label) => label.name).sort();
  const desiredLabels = [...labels].sort();
  const labelsEqual = JSON.stringify(existingLabels) === JSON.stringify(desiredLabels);
  const bodyEqual = normalizeBody(existing.body ?? "") === normalizeBody(body);
  const milestoneEqual = (existing.milestone?.number ?? null) === milestoneNumber;

  if (labelsEqual && bodyEqual && milestoneEqual && existing.title === payload.title) {
    return;
  }

  const updated = requestJson("PATCH", `repos/${repo}/issues/${existing.number}`, payload);
  if (updated) {
    const index = existingIssues.findIndex((issue) => issue.number === existing.number);
    existingIssues[index] = updated;
  }
}

function validateBacklog(backlog) {
  assert(backlog.meta?.repo, "backlog.meta.repo is required");
  assert(Array.isArray(backlog.labels), "backlog.labels must be an array");
  assert(Array.isArray(backlog.milestones), "backlog.milestones must be an array");
  assert(Array.isArray(backlog.epics), "backlog.epics must be an array");
  assert(Array.isArray(backlog.stories), "backlog.stories must be an array");
  assert(Array.isArray(backlog.tasks), "backlog.tasks must be an array");

  for (const milestone of backlog.milestones) {
    assert(milestone.doc, `${milestone.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, milestone.doc)), `${milestone.id} doc is missing: ${milestone.doc}`);
  }

  for (const epic of backlog.epics) {
    assert(epic.doc, `${epic.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, epic.doc)), `${epic.id} doc is missing: ${epic.doc}`);
  }

  for (const story of backlog.stories) {
    assert(story.doc, `${story.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, story.doc)), `${story.id} doc is missing: ${story.doc}`);
  }

  const milestoneIds = new Set(backlog.milestones.map((item) => item.id));
  const epicIds = new Set(backlog.epics.map((item) => item.id));
  const storyIds = new Set(backlog.stories.map((item) => item.id));
  const taskIds = new Set(backlog.tasks.map((item) => item.id));

  for (const epic of backlog.epics) {
    assert(milestoneIds.has(epic.milestone), `${epic.id} references unknown milestone ${epic.milestone}`);
    for (const storyId of epic.story_refs) {
      assert(storyIds.has(storyId), `${epic.id} references unknown story ${storyId}`);
    }
    for (const taskId of epic.task_refs) {
      assert(taskIds.has(taskId), `${epic.id} references unknown task ${taskId}`);
    }
  }

  for (const story of backlog.stories) {
    for (const epicId of story.epic_refs) {
      assert(epicIds.has(epicId), `${story.id} references unknown epic ${epicId}`);
    }
    for (const taskId of story.task_refs) {
      assert(taskIds.has(taskId), `${story.id} references unknown task ${taskId}`);
    }
    assert(story.task_refs.length > 0, `${story.id} must link to at least one task`);
  }

  for (const task of backlog.tasks) {
    assert(milestoneIds.has(task.milestone), `${task.id} references unknown milestone ${task.milestone}`);
    assert(epicIds.has(task.epic), `${task.id} references unknown epic ${task.epic}`);
    assert(task.story_refs.length > 0, `${task.id} must link to at least one story`);
    for (const storyId of task.story_refs) {
      assert(storyIds.has(storyId), `${task.id} references unknown story ${storyId}`);
    }
    for (const dependency of task.depends_on) {
      assert(taskIds.has(dependency), `${task.id} references unknown dependency ${dependency}`);
    }
  }

  for (const story of backlog.stories) {
    const linkedTasks = backlog.tasks.filter((task) => task.story_refs.includes(story.id));
    assert(linkedTasks.length > 0, `${story.id} is orphaned; no task references it`);
  }

  for (const milestone of backlog.milestones) {
    const linkedEpics = backlog.epics.filter((epic) => epic.milestone === milestone.id);
    assert(linkedEpics.length > 0, `${milestone.id} is orphaned; no epic references it`);
  }
}

function main() {
  const backlog = readJsonLikeYaml(backlogPath);
  validateBacklog(backlog);

  const repo = backlog.meta.repo;
  const branch = backlog.meta.default_branch ?? "main";
  const githubState = fetchGithubState(repo);
  const labelMap = new Map(githubState.labels.map((label) => [label.name, label]));
  const milestoneMap = new Map(githubState.milestones.map((milestone) => [milestone.title, milestone]));

  for (const label of backlog.labels) {
    syncLabel(repo, label, labelMap);
  }

  for (const milestone of backlog.milestones) {
    syncMilestone(repo, milestone, milestoneMap);
  }

  const context = {
    repo,
    branch,
    milestoneById: new Map(backlog.milestones.map((item) => [item.id, item])),
    epicById: new Map(backlog.epics.map((item) => [item.id, item])),
    storyById: new Map(backlog.stories.map((item) => [item.id, item])),
    taskById: new Map(backlog.tasks.map((item) => [item.id, item])),
  };

  for (const epic of backlog.epics) {
    const milestone = context.milestoneById.get(epic.milestone);
    const existing = findExistingIssue(epic, githubState.issues);
    const body = epicBody(epic, backlog, context, existing?.body ?? "");
    const labels = ["type:epic", epic.priority, ...epic.area_labels];
    syncIssue(repo, epic, githubState.issues, body, labels, milestone.github?.number ?? null);
  }

  for (const task of backlog.tasks) {
    const milestone = context.milestoneById.get(task.milestone);
    const existing = findExistingIssue(task, githubState.issues);
    const body = taskBody(task, context, existing?.body ?? "");
    const labels = ["type:task", task.state, task.priority, ...task.area_labels];
    syncIssue(repo, task, githubState.issues, body, labels, milestone.github?.number ?? null);
  }

  for (const epic of backlog.epics) {
    const milestone = context.milestoneById.get(epic.milestone);
    const existing = findExistingIssue(epic, githubState.issues);
    const body = epicBody(epic, backlog, context, existing?.body ?? "");
    const labels = ["type:epic", epic.priority, ...epic.area_labels];
    syncIssue(repo, epic, githubState.issues, body, labels, milestone.github?.number ?? null);
  }

  if (sync) {
    writeJsonLikeYaml(backlogPath, backlog);
    console.log(`Synced ai_docs backlog to ${repo}`);
  } else {
    console.log(`Dry run complete for ${repo}`);
  }
}

main();
