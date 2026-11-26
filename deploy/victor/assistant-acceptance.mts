import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

interface State { kbId: string }
interface Envelope<T> { success: boolean; data: T }
interface StreamEvent {
  response_type: string;
  content?: string;
  data?: { tool_name?: string; success?: boolean; replace?: boolean };
}
const home = process.env.VICTOR_HOME ?? '/home/lenovo/victor_wiki';
const state = JSON.parse(readFileSync(`${home}/secrets/acceptance-state.json`, 'utf8')) as State;
const key = readFileSync(`${home}/secrets/acceptance-api-key`, 'utf8').trim();
const base = 'http://127.0.0.1:8091/api/v1';
let headers: Record<string, string> = { 'X-API-Key': key, 'Content-Type': 'application/json' };
if (process.argv.includes('--owner')) {
  const account = JSON.parse(readFileSync(`${home}/secrets/account.json`, 'utf8')) as { email: string; password: string };
  const loginResponse = await fetch(`${base}/auth/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(account),
  });
  assert(loginResponse.ok, `Owner login: HTTP ${loginResponse.status}`);
  const login = await loginResponse.json() as { success: boolean; token: string };
  assert(login.success && login.token, 'Owner login did not return a token');
  headers = { Authorization: `Bearer ${login.token}`, 'Content-Type': 'application/json' };
  const modelsResponse = await fetch(`${base}/models`, { headers });
  assert(modelsResponse.ok, 'Owner model catalog is unavailable');
  const models = await modelsResponse.json() as Envelope<{ id: string; parameters: { context_window: number; max_output_tokens: number } }[]>;
  const localModel = models.data.find(model => model.id === 'victor-local-chat');
  assert(localModel?.parameters.context_window === 32768 && localModel.parameters.max_output_tokens === 2048,
    'Application model limits must be 32768 context / 2048 output');
  console.log('PASS application local-model metadata: 32768 context / 2048 output');
}
const kbResponse = await fetch(`${base}/knowledge-bases/${state.kbId}`, { headers });
assert(kbResponse.ok, `Synthetic knowledge base: HTTP ${kbResponse.status}`);
const kb = await kbResponse.json() as Envelope<{ name: string }>;
assert(kb.data.name === '系统验收（合成资料）', 'Assistant test must target the synthetic knowledge base');
const sessionResponse = await fetch(`${base}/sessions`, {
  method: 'POST', headers, body: JSON.stringify({ title: '部署验收：助手工具调用' }),
});
assert(sessionResponse.ok, `Create session: HTTP ${sessionResponse.status}`);
const session = await sessionResponse.json() as Envelope<{ id: string }>;
console.log('Starting the builtin assistant tool path; CPU prefill may take minutes.');
const response = await fetch(`${base}/agent-chat/${session.data.id}`, {
  method: 'POST', headers: { ...headers, Accept: 'text/event-stream' },
  body: JSON.stringify({
    query: '这是只读部署验收。请调用 list_documents，查询“系统验收（合成资料）”知识库中的 victor-acceptance.md 文件，只简短回答找到的文件名。不要更改任何资料。',
    knowledge_base_ids: [state.kbId], agent_enabled: true,
    agent_id: 'builtin-weknora-assistant', assistant_access: 'read_only',
    summary_model_id: 'victor-local-chat', reasoning_effort: 'off',
    disable_title: true, channel: 'web',
  }),
  signal: AbortSignal.timeout(1800000),
});
assert(response.ok, `Assistant request: HTTP ${response.status}`);
const stream = await response.text();
writeFileSync(`${home}/logs/assistant-acceptance-stream.txt`, stream, { mode: 0o600 });
let called = false;
let succeeded = false;
let complete = false;
let answer = '';
for (const line of stream.split('\n')) {
  if (!line.startsWith('data:')) {
    continue;
  }
  const payload = line.slice(5).trim();
  if (!payload || payload === '[DONE]') {
    continue;
  }
  const event = JSON.parse(payload) as StreamEvent;
  assert(event.response_type !== 'error', `Assistant emitted an error: ${event.content ?? ''}`);
  if (event.data?.tool_name === 'list_documents') {
    called ||= event.response_type === 'tool_call';
    succeeded ||= event.response_type === 'tool_result' && event.data.success === true;
  }
  if (event.response_type === 'answer' && typeof event.content === 'string') {
    answer = event.data?.replace ? event.content : answer + event.content;
  }
  complete ||= event.response_type === 'complete';
}
assert(called && succeeded, 'The builtin assistant did not successfully execute list_documents');
assert(complete && answer.includes('victor-acceptance.md'), `Missing final document answer: ${answer.slice(0, 300)}`);
assert(!answer.includes('kept hitting') && !answer.includes('unable to generate'), 'Assistant returned a fallback');
const network = JSON.parse(execFileSync('docker', ['inspect', 'victor-wiki-ollama', '--format', '{{json .NetworkSettings.Networks}}'], { encoding: 'utf8' })) as Record<string, { IPAddress: string }>;
const ip = Object.values(network)[0].IPAddress;
const psResponse = await fetch(`http://${ip}:11434/api/ps`);
assert(psResponse.ok, 'Ollama runtime status is unavailable');
const ps = await psResponse.json() as { models: { name: string; context_length: number }[] };
const model = ps.models.find(model => model.name === 'qwen2.5:3b');
assert(model?.context_length === 32768, `Ollama must actually allocate 32768 tokens: ${model?.context_length}`);
console.log('PASS builtin assistant executed list_documents and returned:', answer.trim());
console.log('PASS Ollama runtime context: 32768');
