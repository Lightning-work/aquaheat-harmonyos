// github-ops.mjs —— 通过 GitHub API 代操作（建仓库/批量上传/变量/触发/日志）
// 用法示例（<token> 为用户的 Personal Access Token）：
//   node github-ops.mjs create-repo <token> aquaheat-harmonyos
//   node github-ops.mjs push-dir   <token> <owner>/aquaheat-harmonyos <本地目录> [分支=main]
//   node github-ops.mjs set-var    <token> <owner>/aquaheat-harmonyos COMMANDLINE_TOOLS_URL <url>
//   node github-ops.mjs dispatch   <token> <owner>/aquaheat-harmonyos
//   node github-ops.mjs runs       <token> <owner>/aquaheat-harmonyos
//   node github-ops.mjs logs       <token> <owner>/aquaheat-harmonyos <runId> <输出目录>
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const [, , cmd, token, repo, ...rest] = process.argv;
if (!cmd || !token) {
  console.log('用法: node github-ops.mjs <create-repo|push-dir|set-var|dispatch|runs|logs> <token> ...');
  process.exit(1);
}
const API = 'https://api.github.com';

async function gh(method, path, body, rawOut) {
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'aquaheat-ops',
  };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  const res = await fetch(`${API}${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (rawOut) {
    if (!res.ok) {
      throw new Error(`${method} ${path} -> ${res.status}: ${await res.text()}`);
    }
    return Buffer.from(await res.arrayBuffer());
  }
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 400)}`);
  }
  return json;
}

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) {
      out.push(...walk(p));
    } else {
      out.push(p);
    }
  }
  return out;
}

async function main() {
  if (cmd === 'create-repo') {
    const name = repo;
    const r = await gh('POST', '/user/repos', {
      name: name,
      description: 'AquaHeat Console 热水器蓝牙上位机 · 鸿蒙 NEXT 原生版',
      private: false,
      has_issues: false,
      has_wiki: false,
      auto_init: false,
    });
    console.log('repo created:', r.full_name);
  } else if (cmd === 'push-dir') {
    const localDir = rest[0];
    const branch = rest[1] ?? 'main';
    const files = walk(localDir);
    console.log(`uploading ${files.length} files to ${repo}@${branch} ...`);
    let i = 0;
    for (const abs of files) {
      i++;
      const rel = relative(localDir, abs).split(sep).join('/');
      const content = readFileSync(abs).toString('base64');
      // 先查是否已存在（决定 create / update）
      let sha = undefined;
      try {
        const existing = await gh('GET', `/repos/${repo}/contents/${encodeURI(rel)}?ref=${branch}`);
        sha = existing.sha;
      } catch (e) {
        // 404 = 新文件
      }
      await gh('PUT', `/repos/${repo}/contents/${encodeURI(rel)}`, {
        message: `add ${rel}`,
        content: content,
        branch: branch,
        sha: sha,
      });
      console.log(`  [${i}/${files.length}] ${rel}`);
      await new Promise((r2) => setTimeout(r2, 300)); // 避免触发次级限流
    }
    console.log('done.');
  } else if (cmd === 'set-var') {
    const varName = rest[0];
    const value = rest[1];
    try {
      await gh('GET', `/repos/${repo}/actions/variables/${varName}`);
      await gh('PATCH', `/repos/${repo}/actions/variables/${varName}`, { name: varName, value: value });
      console.log(`variable ${varName} updated`);
    } catch (e) {
      await gh('POST', `/repos/${repo}/actions/variables`, { name: varName, value: value });
      console.log(`variable ${varName} created`);
    }
  } else if (cmd === 'dispatch') {
    await gh('POST', `/repos/${repo}/actions/workflows/build.yml/dispatches`, { ref: 'main' });
    console.log('workflow dispatched');
  } else if (cmd === 'runs') {
    const r = await gh('GET', `/repos/${repo}/actions/runs?per_page=3`);
    for (const run of r.workflow_runs) {
      console.log(`#${run.run_id ?? run.id}  ${run.status}  ${run.conclusion ?? ''}  ${run.created_at}  ${run.html_url}`);
    }
    if (!r.workflow_runs?.length) {
      console.log('no runs yet');
    }
  } else if (cmd === 'logs') {
    const runId = rest[0];
    const outDir = rest[1] ?? '.github-logs';
    const buf = await gh('GET', `/repos/${repo}/actions/runs/${runId}/logs`, undefined, true);
    mkdirSync(outDir, { recursive: true });
    const p = join(outDir, `run-${runId}-logs.zip`);
    writeFileSync(p, buf);
    console.log(`logs saved: ${p} (${(buf.length / 1024).toFixed(0)} KB)`);
  } else {
    console.log('unknown command:', cmd);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
