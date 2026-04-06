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
const itemIdPattern = /<!-- Item-ID: ([^>]+) -->/;
const deliveryStates = new Set(["open", "done"]);

function usage() {
  console.error("Usage: node scripts/sync-ai-docs.mjs --dry-run | --sync | --self-check");
  process.exit(1);
}

const argv = new Set(process.argv.slice(2));
const dryRun = argv.has("--dry-run");
const sync = argv.has("--sync");
const selfCheck = argv.has("--self-check");

if ([dryRun, sync, selfCheck].filter(Boolean).length !== 1) {
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

function ghPaginatedArray(endpoint) {
  const pages = ghJson([endpoint, "--paginate", "--slurp"]) ?? [];
  return flattenPages(pages);
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

function flattenPages(pages) {
  if (!Array.isArray(pages)) {
    return [];
  }
  return pages.flatMap((page) => (Array.isArray(page) ? page : [page]));
}

function relativeDocUrl(repo, branch, docPath) {
  return `https://github.com/${repo}/blob/${branch}/${docPath}`;
}

function issueTitle(item) {
  return `[${item.id}] ${item.title}`;
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

function deliveryStateFor(item) {
  return item.delivery_state ?? "open";
}

function githubStateFor(item) {
  return deliveryStateFor(item) === "done" ? "closed" : "open";
}

function itemIdFromBody(body) {
  if (!body || !body.includes(marker)) {
    return null;
  }
  const match = body.match(itemIdPattern);
  return match?.[1] ?? null;
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
    const suffix = deliveryStateFor(task) === "done" ? " (done)" : "";
    return `- ${ref} — ${task.title}${suffix}`;
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
    `Delivery state: **${deliveryStateFor(epic)}**`,
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
    `Delivery state: **${deliveryStateFor(task)}**`,
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
    labels: ghPaginatedArray(`repos/${repo}/labels?per_page=100`),
    milestones: ghPaginatedArray(`repos/${repo}/milestones?state=all&per_page=100`),
    issues: ghPaginatedArray(`repos/${repo}/issues?state=all&per_page=100`).filter(
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

function findExistingMilestone(milestone, existingMap) {
  if (milestone.github?.number) {
    for (const existing of existingMap.values()) {
      if (existing.number === milestone.github.number) {
        return existing;
      }
    }
  }
  return existingMap.get(milestone.title) ?? null;
}

function syncMilestone(repo, milestone, existingMap) {
  const existing = findExistingMilestone(milestone, existingMap);
  const payload = {
    title: milestone.title,
    description: milestoneBody(milestone),
    state: githubStateFor(milestone),
  };

  if (!existing) {
    const created = requestJson("POST", `repos/${repo}/milestones`, payload);
    if (created) {
      milestone.github = {
        number: created.number,
        url: created.html_url,
      };
      existingMap.set(created.title, created);
    } else if (dryRun) {
      const synthetic = synthesizeMilestone(repo, nextSyntheticNumber([...existingMap.values()]), payload);
      milestone.github = {
        number: synthetic.number,
        url: synthetic.html_url,
      };
      existingMap.set(synthetic.title, synthetic);
    }
    return;
  }

  milestone.github = {
    number: existing.number,
    url: existing.html_url,
  };

  const stateEqual = (existing.state ?? "open") === payload.state;
  if ((existing.description ?? "") === payload.description && existing.title === payload.title && stateEqual) {
    return;
  }

  const updated = requestJson("PATCH", `repos/${repo}/milestones/${existing.number}`, payload);
  if (updated) {
    existingMap.set(updated.title, updated);
  } else if (dryRun) {
    existingMap.set(payload.title, {
      ...existing,
      title: payload.title,
      description: payload.description,
      state: payload.state,
    });
  }
}

function findExistingIssue(item, existingIssues) {
  if (item.github?.issue_number) {
    return existingIssues.find((issue) => issue.number === item.github.issue_number) ?? null;
  }

  const byManagedId = existingIssues.find((issue) => itemIdFromBody(issue.body ?? "") === item.id);
  if (byManagedId) {
    return byManagedId;
  }

  return existingIssues.find((issue) => issue.title === issueTitle(item)) ?? null;
}

function nextSyntheticNumber(items) {
  const numbers = items
    .map((item) => item.number)
    .filter((value) => Number.isInteger(value));
  return (numbers.length ? Math.max(...numbers) : 0) + 1;
}

function synthesizeIssue(repo, number, payload) {
  return {
    number,
    html_url: `https://github.com/${repo}/issues/${number}`,
    title: payload.title,
    body: payload.body,
    labels: (payload.labels ?? []).map((name) => ({ name })),
    milestone: payload.milestone == null ? null : { number: payload.milestone },
    state: payload.state ?? "open",
  };
}

function synthesizeMilestone(repo, number, payload) {
  return {
    number,
    html_url: `https://github.com/${repo}/milestone/${number}`,
    title: payload.title,
    description: payload.description,
    state: payload.state ?? "open",
  };
}

function desiredTaskLabels(task) {
  const labels = ["type:task"];
  if (deliveryStateFor(task) === "open") {
    labels.push(task.state);
  }
  labels.push(task.priority, ...task.area_labels);
  return labels;
}

function desiredEpicLabels(epic) {
  return ["type:epic", epic.priority, ...epic.area_labels];
}

function syncIssue(repo, item, existingIssues, body, labels, milestoneNumber) {
  const existing = findExistingIssue(item, existingIssues);
  const desiredState = githubStateFor(item);
  const basePayload = {
    title: issueTitle(item),
    body,
    labels,
    milestone: milestoneNumber,
  };

  if (!existing) {
    const created = requestJson("POST", `repos/${repo}/issues`, basePayload);
    if (created) {
      item.github = {
        issue_number: created.number,
        url: created.html_url,
      };
      existingIssues.push(created);

      if (desiredState === "closed") {
        const closed = requestJson("PATCH", `repos/${repo}/issues/${created.number}`, {
          state: "closed",
        });
        if (closed) {
          const index = existingIssues.findIndex((issue) => issue.number === created.number);
          existingIssues[index] = closed;
        }
      }
    } else if (dryRun) {
      existingIssues.push(
        synthesizeIssue(repo, nextSyntheticNumber(existingIssues), {
          ...basePayload,
          state: desiredState,
        })
      );
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
  const stateEqual = (existing.state ?? "open") === desiredState;

  if (labelsEqual && bodyEqual && milestoneEqual && stateEqual && existing.title === basePayload.title) {
    return;
  }

  const updated = requestJson("PATCH", `repos/${repo}/issues/${existing.number}`, {
    ...basePayload,
    state: desiredState,
  });
  if (updated) {
    const index = existingIssues.findIndex((issue) => issue.number === existing.number);
    existingIssues[index] = updated;
  } else if (dryRun) {
    const index = existingIssues.findIndex((issue) => issue.number === existing.number);
    existingIssues[index] = synthesizeIssue(repo, existing.number, {
      ...basePayload,
      state: desiredState,
    });
  }
}

function validateDeliveryState(item, label) {
  const state = deliveryStateFor(item);
  assert(deliveryStates.has(state), `${label} must declare delivery_state as open or done`);
}

function validateBacklog(backlog) {
  assert(backlog.meta?.repo, "backlog.meta.repo is required");
  assert(Array.isArray(backlog.labels), "backlog.labels must be an array");
  assert(Array.isArray(backlog.milestones), "backlog.milestones must be an array");
  assert(Array.isArray(backlog.epics), "backlog.epics must be an array");
  assert(Array.isArray(backlog.stories), "backlog.stories must be an array");
  assert(Array.isArray(backlog.tasks), "backlog.tasks must be an array");

  for (const milestone of backlog.milestones) {
    validateDeliveryState(milestone, milestone.id);
    assert(milestone.doc, `${milestone.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, milestone.doc)), `${milestone.id} doc is missing: ${milestone.doc}`);
  }

  for (const epic of backlog.epics) {
    validateDeliveryState(epic, epic.id);
    assert(epic.doc, `${epic.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, epic.doc)), `${epic.id} doc is missing: ${epic.doc}`);
  }

  for (const story of backlog.stories) {
    assert(story.doc, `${story.id} must declare doc`);
    assert(fs.existsSync(path.join(repoRoot, story.doc)), `${story.id} doc is missing: ${story.doc}`);
  }

  const readinessLabels = new Set(
    backlog.labels
      .map((label) => label.name)
      .filter((name) => name.startsWith("state:"))
  );
  const milestoneIds = new Set(backlog.milestones.map((item) => item.id));
  const epicIds = new Set(backlog.epics.map((item) => item.id));
  const storyIds = new Set(backlog.stories.map((item) => item.id));
  const taskIds = new Set(backlog.tasks.map((item) => item.id));
  const taskById = new Map(backlog.tasks.map((item) => [item.id, item]));
  const epicById = new Map(backlog.epics.map((item) => [item.id, item]));

  for (const epic of backlog.epics) {
    assert(milestoneIds.has(epic.milestone), `${epic.id} references unknown milestone ${epic.milestone}`);
    for (const storyId of epic.story_refs) {
      assert(storyIds.has(storyId), `${epic.id} references unknown story ${storyId}`);
      const story = backlog.stories.find((item) => item.id === storyId);
      assert(story.epic_refs.includes(epic.id), `${epic.id} must be listed in ${storyId}.epic_refs`);
    }
    for (const taskId of epic.task_refs) {
      assert(taskIds.has(taskId), `${epic.id} references unknown task ${taskId}`);
      const task = taskById.get(taskId);
      assert(task.epic === epic.id, `${epic.id} must own ${taskId}`);
    }
    if (deliveryStateFor(epic) === "done") {
      const openTasks = epic.task_refs.filter((taskId) => deliveryStateFor(taskById.get(taskId)) !== "done");
      assert(openTasks.length === 0, `${epic.id} is done but still has open tasks: ${openTasks.join(", ")}`);
    }
  }

  for (const story of backlog.stories) {
    for (const epicId of story.epic_refs) {
      assert(epicIds.has(epicId), `${story.id} references unknown epic ${epicId}`);
    }
    for (const taskId of story.task_refs) {
      assert(taskIds.has(taskId), `${story.id} references unknown task ${taskId}`);
      const task = taskById.get(taskId);
      assert(task.story_refs.includes(story.id), `${story.id} must be listed in ${taskId}.story_refs`);
    }
    assert(story.task_refs.length > 0, `${story.id} must link to at least one task`);
  }

  for (const task of backlog.tasks) {
    validateDeliveryState(task, task.id);
    assert(milestoneIds.has(task.milestone), `${task.id} references unknown milestone ${task.milestone}`);
    assert(epicIds.has(task.epic), `${task.id} references unknown epic ${task.epic}`);
    assert(task.story_refs.length > 0, `${task.id} must link to at least one story`);
    for (const storyId of task.story_refs) {
      assert(storyIds.has(storyId), `${task.id} references unknown story ${storyId}`);
    }
    for (const dependency of task.depends_on) {
      assert(taskIds.has(dependency), `${task.id} references unknown dependency ${dependency}`);
    }

    if (deliveryStateFor(task) === "open") {
      assert(task.state, `${task.id} must declare a readiness state while open`);
      assert(readinessLabels.has(task.state), `${task.id} uses unknown readiness state ${task.state}`);
    } else {
      assert(!task.state, `${task.id} must omit readiness state when delivery_state is done`);
    }
  }

  for (const story of backlog.stories) {
    const linkedTasks = backlog.tasks.filter((task) => task.story_refs.includes(story.id));
    assert(linkedTasks.length > 0, `${story.id} is orphaned; no task references it`);
  }

  for (const milestone of backlog.milestones) {
    const linkedEpics = backlog.epics.filter((epic) => epic.milestone === milestone.id);
    assert(linkedEpics.length > 0, `${milestone.id} is orphaned; no epic references it`);
    if (deliveryStateFor(milestone) === "done") {
      const openEpics = linkedEpics.filter((epic) => deliveryStateFor(epic) !== "done");
      assert(openEpics.length === 0, `${milestone.id} is done but still has open epics`);
    }
  }

  for (const epic of backlog.epics) {
    const parentMilestone = backlog.milestones.find((milestone) => milestone.id === epic.milestone);
    assert(parentMilestone, `${epic.id} references missing milestone ${epic.milestone}`);
    if (deliveryStateFor(parentMilestone) === "done") {
      assert(deliveryStateFor(epic) === "done", `${epic.id} cannot stay open inside done milestone ${parentMilestone.id}`);
    }
  }
}

function runSelfCheck() {
  const flattened = flattenPages([[{ number: 1 }], [{ number: 2 }, { number: 3 }]]);
  assert(flattened.length === 3, "flattenPages should combine multiple GitHub pages");

  const secondPageIssue = {
    number: 42,
    title: "[TASK-999] Placeholder",
    body: `${marker}\n<!-- Item-ID: TASK-999 -->\nBody`,
    labels: [],
    state: "open",
    milestone: null,
  };
  const found = findExistingIssue({ id: "TASK-999" }, [{ number: 1, body: "" }, secondPageIssue]);
  assert(found?.number === 42, "findExistingIssue should match managed items by Item-ID even when not first");

  const openLabels = desiredTaskLabels({
    delivery_state: "open",
    state: "state:agent-ready",
    priority: "priority:p0",
    area_labels: ["area:fork"],
  });
  assert(openLabels.includes("state:agent-ready"), "open tasks should keep readiness labels");

  const doneLabels = desiredTaskLabels({
    delivery_state: "done",
    priority: "priority:p0",
    area_labels: ["area:fork"],
  });
  assert(!doneLabels.some((label) => label.startsWith("state:")), "done tasks should drop readiness labels");

  const backlog = readJsonLikeYaml(backlogPath);
  validateBacklog(backlog);
  console.log("Self-check passed for sync-ai-docs.mjs");
}

function main() {
  if (selfCheck) {
    runSelfCheck();
    return;
  }

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
    syncIssue(repo, epic, githubState.issues, body, desiredEpicLabels(epic), milestone.github?.number ?? null);
  }

  for (const task of backlog.tasks) {
    const milestone = context.milestoneById.get(task.milestone);
    const existing = findExistingIssue(task, githubState.issues);
    const body = taskBody(task, context, existing?.body ?? "");
    syncIssue(repo, task, githubState.issues, body, desiredTaskLabels(task), milestone.github?.number ?? null);
  }

  for (const epic of backlog.epics) {
    const milestone = context.milestoneById.get(epic.milestone);
    const existing = findExistingIssue(epic, githubState.issues);
    const body = epicBody(epic, backlog, context, existing?.body ?? "");
    syncIssue(repo, epic, githubState.issues, body, desiredEpicLabels(epic), milestone.github?.number ?? null);
  }

  if (sync) {
    writeJsonLikeYaml(backlogPath, backlog);
    console.log(`Synced ai_docs backlog to ${repo}`);
  } else {
    console.log(`Dry run complete for ${repo}`);
  }
}

main();
