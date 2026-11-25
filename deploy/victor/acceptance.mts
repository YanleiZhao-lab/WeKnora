import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';

interface Account { username: string; email: string; password: string }
interface Login { success: boolean; token: string; user: { is_system_admin: boolean }; active_tenant: { id: number } }
interface Envelope<T> { success: boolean; data: T }
interface Model { id: string; name: string; type: string; source: string }
interface KnowledgeBase { id: string; name: string }
interface Knowledge { id: string; parse_status: string; error_message?: string }
interface SearchHit { content: string; knowledge_id: string }
interface Session { id: string }
interface State { kbId: string; knowledgeId: string; chatModelId: string; mainKbId?: string }
interface CreatedKey { token: string }
interface StreamEvent { response_type?: string; content?: string; knowledge_references?: SearchHit[]; data?: { replace?: boolean } }

const home = process.env.VICTOR_HOME ?? '/home/lenovo/victor_wiki';
const base = 'http://127.0.0.1:8091/api/v1';
const accountPath = `${home}/secrets/account.json`;
const statePath = `${home}/secrets/acceptance-state.json`;
const initialize = process.argv.includes('--init');
const provisionOnly = process.argv.includes('--provision-only');
const keyPath = `${home}/secrets/acceptance-api-key`;
let token = '';
let apiKey = '';

function authHeaders(): Record<string, string> {
  if (apiKey) {
    return { 'X-API-Key': apiKey };
  }
  if (token) {
    return { Authorization: `Bearer ${token}` };
  }
  return {};
}

async function request<T>(path: string, method = 'GET', payload?: unknown): Promise<T> {
  const headers = authHeaders();
  if (payload !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(`${base}${path}`, {
    method, headers, body: payload === undefined ? undefined : JSON.stringify(payload),
    signal: AbortSignal.timeout(600000),
  });
  if (!response.ok) {
    throw new Error(`${method} ${path}: HTTP ${response.status}`);
  }
  return await response.json() as T;
}

let localModels: { embedding: Model; chat: Model } | undefined;
let tenantId: number | undefined;
if (initialize || provisionOnly) {
  if (!existsSync(accountPath)) {
    assert(initialize, 'Initial account has not been provisioned');
    const account: Account = { username: 'victor', email: 'victor@local.invalid', password: randomBytes(24).toString('base64url') };
    writeFileSync(accountPath, JSON.stringify(account, null, 2), { mode: 0o600 });
  }
  const account = JSON.parse(readFileSync(accountPath, 'utf8')) as Account;
  assert(typeof account.email === 'string' && typeof account.password === 'string');
  let login: Login;
  if (initialize) {
    const existing = await fetch(`${base}/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: account.email, password: account.password }) });
    if (existing.ok) {
      login = await existing.json() as Login;
    } else {
      assert([400, 401].includes(existing.status), `Initial login failed: ${existing.status}`);
      await request('/auth/register', 'POST', account);
      login = await request<Login>('/auth/login', 'POST', { email: account.email, password: account.password });
    }
  } else {
    login = await request<Login>('/auth/login', 'POST', { email: account.email, password: account.password });
  }
  assert(login.success && login.token, 'Login did not return an authenticated session');
  assert(login.user.is_system_admin, 'Bootstrap owner is not system administrator');
  token = login.token;
  tenantId = login.active_tenant.id;
  console.log('PASS owner login');
  const models = await request<Envelope<Model[]>>('/models');
  const embedding = models.data.find(model => model.name === 'bge-m3');
  const chat = models.data.find(model => model.name === 'qwen2.5:3b');
  assert(embedding && chat, 'Local models are missing from the application catalog');
  assert(embedding.source === 'local' && chat.source === 'local', 'Knowledge processing must use local model providers');
  localModels = { embedding, chat };
  console.log('PASS local model registration');
  if (provisionOnly) {
    console.log('Owner provisioning complete; full knowledge acceptance has not run.');
    process.exit(0);
  }
} else {
  assert(existsSync(keyPath), 'Run --init after local models are installed');
  apiKey = readFileSync(keyPath, 'utf8').trim();
  assert(apiKey.length > 0, 'Maintenance key is empty');
}

let state: State;
if (existsSync(statePath)) {
  state = JSON.parse(readFileSync(statePath, 'utf8')) as State;
} else {
  assert(initialize && localModels, 'Acceptance knowledge base has not been provisioned');
  const kb = await request<Envelope<KnowledgeBase>>('/knowledge-bases', 'POST', {
    name: '系统验收（合成资料）', description: '仅用于本地部署与升级验证，不含真实个人资料。', type: 'document',
    embedding_model_id: localModels.embedding.id, summary_model_id: localModels.chat.id,
    chunking_config: { chunk_size: 512, chunk_overlap: 50 },
  });
  assert(kb.success && kb.data.id, 'Knowledge base creation failed');
  const form = new FormData();
  form.append('file', new File([readFileSync(`${home}/testdata/victor-acceptance.md`)], 'victor-acceptance.md', { type: 'text/markdown' }));
  const upload = await fetch(`${base}/knowledge-bases/${kb.data.id}/knowledge/file`, {
    method: 'POST', headers: authHeaders(), body: form, signal: AbortSignal.timeout(120000),
  });
  assert(upload.ok, `Document upload failed: ${upload.status}`);
  const result = await upload.json() as Envelope<Knowledge>;
  assert(result.success && result.data.id, 'Document upload did not return an identifier');
  state = { kbId: kb.data.id, knowledgeId: result.data.id, chatModelId: localModels.chat.id };
  writeFileSync(statePath, JSON.stringify(state, null, 2), { mode: 0o600 });
}

if (initialize) {
  assert(localModels && tenantId, 'Bootstrap model configuration is missing');
  if (!state.mainKbId) {
    const main = await request<Envelope<KnowledgeBase>>('/knowledge-bases', 'POST', {
      name: 'victor_wiki', description: '个人知识库：资料、索引与模型处理均保留在本地。', type: 'document',
      embedding_model_id: localModels.embedding.id, summary_model_id: localModels.chat.id,
      chunking_config: { chunk_size: 512, chunk_overlap: 50 },
    });
    assert(main.success && main.data.id, 'Personal knowledge base creation failed');
    state.mainKbId = main.data.id;
    writeFileSync(statePath, JSON.stringify(state, null, 2), { mode: 0o600 });
  }
  if (!existsSync(keyPath)) {
    const key = await request<Envelope<CreatedKey>>(`/tenants/${tenantId}/api-keys`, 'POST', {
      name: 'victor_wiki 本机维护验收（检索与问答）', full_access: true,
      knowledge_base_ids: [], capabilities: ['retrieve', 'chat'],
    });
    assert(key.success && key.data.token, 'Maintenance key creation failed');
    writeFileSync(keyPath, key.data.token + '\n', { mode: 0o600 });
  }
  apiKey = readFileSync(keyPath, 'utf8').trim();
}

let parsed = false;
for (let attempt = 0; attempt < 180; attempt++) {
  const knowledge = await request<Envelope<Knowledge>>(`/knowledge/${state.knowledgeId}`);
  if (knowledge.data.parse_status === 'completed') {
    parsed = true;
    break;
  }
  assert(knowledge.data.parse_status !== 'failed', `Document parsing failed: ${knowledge.data.error_message ?? ''}`);
  await new Promise(resolve => setTimeout(resolve, 5000));
}
assert(parsed, 'Document parsing exceeded the acceptance deadline');
console.log('PASS document upload and parsing');

const search = await request<Envelope<SearchHit[]>>(`/knowledge-bases/${state.kbId}/hybrid-search`, 'POST', {
  query_text: '星河计划的资料复查周期', match_count: 5, vector_threshold: 0, keyword_threshold: 0,
});
assert(search.success && search.data.some(hit => hit.content.includes('21') && hit.knowledge_id === state.knowledgeId), 'Retrieval missed the original source and its 21-day review interval');
console.log('PASS retrieval with original source');

const session = await request<Envelope<Session>>('/sessions', 'POST', { title: '系统验收：本地知识问答' });
const response = await fetch(`${base}/knowledge-chat/${session.data.id}`, {
  method: 'POST', headers: { ...authHeaders(), 'Content-Type': 'application/json', Accept: 'text/event-stream' },
  body: JSON.stringify({ query: '星河计划的资料复查周期是多少天？请根据资料只回答天数。', knowledge_base_ids: [state.kbId], summary_model_id: state.chatModelId, reasoning_effort: 'off', disable_title: true, channel: 'web' }),
  signal: AbortSignal.timeout(900000),
});
assert(response.ok, `Knowledge chat failed: ${response.status}`);
const stream = await response.text();
writeFileSync(`${home}/logs/acceptance-stream.txt`, stream, { mode: 0o600 });
let answer = '';
let terminal = false;
let citedSource = false;
for (const line of stream.split('\n')) {
  if (!line.startsWith('data:')) {
    continue;
  }
  const payload = line.slice(5).trim();
  if (!payload || payload === '[DONE]') {
    continue;
  }
  const event = JSON.parse(payload) as StreamEvent;
  const type = event.response_type;
  assert(type !== 'error', 'Knowledge chat emitted an error event');
  if (type === 'answer' && typeof event.content === 'string') {
    answer = event.data?.replace ? event.content : answer + event.content;
  }
  if (type === 'references') {
    citedSource ||= event.knowledge_references?.some(ref => ref.knowledge_id === state.knowledgeId) ?? false;
  }
  if (type === 'complete') {
    terminal = true;
  }
}
const visibleAnswer = answer.replace(/<(?:ref|kb)\b[^>]*\/?>/g, '').trim();
assert(terminal && visibleAnswer.length <= 100 && /(?:21|二十一)\s*(?:天|$)/.test(visibleAnswer), `Expected a completed answer with the 21-day interval; received ${answer.slice(0, 200)}`);
assert(citedSource, 'Knowledge answer did not cite the uploaded original source');
console.log('PASS knowledge answer citation');
writeFileSync(`${home}/logs/acceptance-answer.txt`, answer);
console.log('PASS local knowledge answer:', answer.trim());
console.log('Acceptance passed using the local maintenance API key.');
