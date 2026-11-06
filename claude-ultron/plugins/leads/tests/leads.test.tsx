import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { LEADS, leadFromAgentName, namesLead, parseMention } from '../hooks/leads'

const BAND = {
  plugin: 'leads',
  component: 'AbovePrompt',
  requestId: 'band',
  props: { hasSurvey: false },
} as const

type Agent = { id: string; type: string; status: string }

type World = {
  env?: Record<string, string>
  agents?: Agent[]
  messages?: object[]
  entries?: Record<string, unknown>
  isBlocked?: (text: string) => boolean
  folders?: string[]
  ownAgentFiles?: string[]
  settings?: Record<string, unknown>
  onTool?: (input: { task_id: string }) => void
}

const world = (on: On, { env = {}, agents = [], messages = [], entries = {}, isBlocked = () => false, folders = [], ownAgentFiles = [], settings = {}, onTool }: World = {}) => {
  const store = new Map<string, unknown>(Object.entries(entries))
  const health = { isBroken: false }
  const guarded = <T,>(answer: () => T) => {
    if (health.isBroken) throw new Error('locked')

    return { value: answer() }
  }
  on('store.get', (_, e) => guarded(() => store.get(e.key)) as never)
  on('store.set', (_, e) => guarded(() => void store.set(e.key, e.value)) as never)
  on('store.keys', () => guarded(() => [...store.keys()]) as never)
  on('store.delete', (_, e) => guarded(() => void store.delete(e.key)) as never)
  mock.env(on, env)
  on('session.id', () => ({ value: 'session-1' }))
  on('session.messages', () => ({ value: messages }) as never)
  on('agent.list', () => ({ value: agents }) as never)
  on('settings.read', () => ({ value: settings }))
  on('fs.read', (_, e) => ({ value: `contract of ${e.path}` }))
  on('fs.exists', (_, e) => ({ value: folders.some(folder => e.path.endsWith(folder)) }) as never)
  on('fs.ancestors', (_, e) => ({ value: e.names.filter(name => ownAgentFiles.includes(name)).map(name => ({ name })) }) as never)
  on('prompt.submit', (_, e) => (isBlocked(e.text) ? { drop: 'blocked' } : { text: e.text, context: e.context }))
  on('tool.call', async (_, e) => {
    onTool?.(e as never)

    return { result: {} } as never
  })

  return { store, health }
}

// What the request would name once the plugin's turn.step hook has run.
const stepped = (on: On) => {
  const sent: { model: string; effort?: string | number }[] = []
  on('turn.step', async function* (_, e) {
    sent.push({ model: e.model, effort: e.effort })

    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [] } as never
  })

  return sent
}

const step = async ($: Parameters<Parameters<typeof test>[1]>[0], model: string, agentId?: string) => {
  const stream = $.turn.step({ turnId: 't', index: 0, model, effort: 'medium', messageCount: 1, agentId })
  for await (const _ of stream) void _
}

const prompted = (text: string) => ({ role: 'user', content: [{ type: 'text', text }] })
const answered = { role: 'assistant', content: [{ type: 'text', text: 'OK' }] }
const selected = (id: string) => prompted(`# Chat activation\n\n[leads:selected:${id}]\nThe selected lead is ${id}. Its contract: ...`)
const kept = (id: string) => prompted(`Compaction removed this\n\n[leads:kept:${id}]\nThe selected lead is ${id}. Its contract: ...`)
const COMPOSED = { model: 'claude-haiku-5-5', promptModel: 'claude-haiku-5-5', surfaces: [], tools: [], outputStyle: null } as const

test('a mention at the start of a line selects a lead', () => {
  expect(parseMention('@ultron fix it')).toMatchObject({ lead: { id: 'ultron' }, task: 'fix it' })
  expect(parseMention('  @Jarvis: fix it')).toMatchObject({ lead: { id: 'jarvis' }, task: 'fix it' })
  expect(parseMention('@EDITH')).toMatchObject({ lead: { id: 'edith' }, task: '' })
  expect(parseMention('first\n\n@edith second')).toMatchObject({ lead: { id: 'edith' }, task: 'first\n\nsecond' })
  expect(parseMention('@ultron one\n@jarvis two')).toMatchObject({ lead: { id: 'ultron' }, task: 'one\n@jarvis two' })
  expect(parseMention('@ultron review this thread\n@jarvis said ship it')).toMatchObject({ task: 'review this thread\n@jarvis said ship it' })
})

test('the engine rows for a lead select that lead', () => {
  expect(parseMention('@leads:edith (agent)')).toMatchObject({ lead: { id: 'edith' }, task: '' })
  expect(parseMention('@leads:jarvis (agent)fix it')).toMatchObject({ lead: { id: 'jarvis' }, task: 'fix it' })
  expect(parseMention('@"leads:jarvis (agent)" fix it')).toMatchObject({ lead: { id: 'jarvis' }, task: 'fix it', isScoped: true })
  expect(parseMention('@leads:ultron go')).toMatchObject({ lead: { id: 'ultron' }, task: 'go', isScoped: true })
  expect(parseMention('@ultron go')).toMatchObject({ isScoped: false })
})

test('other text selects nobody', () => {
  for (const text of [
    'fix @ultron',
    '@ultron.md',
    '@ultron/x',
    '@ultrons',
    'me@ultron.com',
    '@ultron-notes',
    "@edith's review is attached",
    '@ultron:notes',
    '@leads:opus-specialist (agent)',
    '@"leads:opus-specialist (agent)"',
    '    @edith indented is code',
  ]) {
    expect(parseMention(text)).toBeUndefined()
  }
})

test('a lead named where nothing selects it can be told from any other text', () => {
  expect(namesLead('please @ultron fix it')).toBe(true)
  expect(namesLead('see @leads:jarvis there')).toBe(true)
  for (const text of ['see @ultron.md', 'mail me@ultron.com', '@ultrons are near', 'why?\n```\nask @edith\n```']) {
    expect(namesLead(text)).toBe(false)
  }
})

test('fenced text and IDE blocks are quoted, and keep their handles', () => {
  expect(parseMention('why?\n```\n@edith approve\n```')).toBeUndefined()
  expect(parseMention('why?\n```\n@edith unterminated')).toBeUndefined()
  expect(parseMention('why?\n~~~\n@edith approve\n~~~\nend')).toBeUndefined()
  expect(parseMention('a stray ``` here\n@ultron go')).toMatchObject({ lead: { id: 'ultron' } })
  expect(parseMention('inline ```x``` here\n@ultron go')).toMatchObject({ lead: { id: 'ultron' } })
  expect(parseMention('```x``` first\n@ultron go')).toMatchObject({ lead: { id: 'ultron' } })
  expect(parseMention('<ide_selection>\n@ultron hello\n</ide_selection>\nplain prompt')).toBeUndefined()
  expect(parseMention('<ide_opened_file>a.ts</ide_opened_file>\n@jarvis fix it')).toMatchObject({
    lead: { id: 'jarvis' },
    task: '<ide_opened_file>a.ts</ide_opened_file>\nfix it',
  })
  expect(parseMention('<ide_opened_file>a.ts</ide_opened_file>@jarvis fix it')).toMatchObject({
    lead: { id: 'jarvis' },
    task: '<ide_opened_file>a.ts</ide_opened_file>fix it',
  })
  expect(parseMention('@jarvis read\n```\n@edith approve\n```')).toMatchObject({
    lead: { id: 'jarvis' },
    task: 'read\n```\n@edith approve\n```',
  })
})

test('agent names resolve bare and scoped', () => {
  expect(leadFromAgentName('ultron')?.id).toBe('ultron')
  expect(leadFromAgentName('leads:edith')?.id).toBe('edith')
  expect(leadFromAgentName('other')).toBeUndefined()
  expect(leadFromAgentName(undefined)).toBeUndefined()
})

test('every lead has its requested model and effort', () => {
  expect([LEADS.ultron.model, LEADS.ultron.effort]).toEqual(['claude-opus-5-5', 'xhigh'])
  expect([LEADS.jarvis.model, LEADS.jarvis.effort]).toEqual(['claude-sonnet-5-5', 'xhigh'])
  expect([LEADS.edith.model, LEADS.edith.effort]).toEqual(['claude-haiku-5-5', 'max'])
})

test('a selection pins the main loop, and a worker keeps its file\'s model and effort', async ($, on) => {
  const agents: Agent[] = []
  world(on, { agents })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')
  await $.prompt.submit({ text: '@edith tidy', origin: { kind: 'composer' } })
  agents.push({ id: 'worker-1', type: 'leads:haiku-worker', status: 'running' })
  await step($, 'claude-opus-5-5')
  await step($, 'claude-haiku-5-5', 'worker-1')

  expect(sent).toEqual([
    { model: 'claude-opus-5-5', effort: 'medium' },
    { model: 'claude-haiku-5-5', effort: 'max' },
    { model: 'claude-haiku-5-5', effort: 'max' },
  ])
})

test('a forked skill runs on the lead, the engine\'s own forks are left alone', async ($, on) => {
  const agents: Agent[] = []
  world(on, { agents })
  const sent = stepped(on)

  await $.prompt.submit({ text: '@edith tidy', origin: { kind: 'composer' } })
  agents.push({ id: 'fork-1', type: 'general-purpose', status: 'running' })
  await step($, 'claude-opus-5-5', 'fork-1')
  await step($, 'claude-opus-5-5', 'compaction-fork')

  expect(sent).toEqual([
    { model: 'claude-haiku-5-5', effort: 'max' },
    { model: 'claude-opus-5-5', effort: 'medium' },
  ])
})

test('a worker whose request stays silent is stopped, and one that answers is not', async ($, on) => {
  const clock = mock.clock(on)
  const stopped: string[] = []
  const agents: Agent[] = []
  world(on, { agents, onTool: e => stopped.push(e.task_id) })
  on('turn.step', async function* (_, e) {
    if (e.agentId === 'hung') await new Promise(() => {})
    await clock.sleep(4 * 60 * 1000)
    yield { kind: 'text', index: 0, text: 'x', turnId: e.turnId, step: e.index } as never
    await clock.sleep(4 * 60 * 1000)

    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [] } as never
  })

  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  agents.push({ id: 'hung', type: 'leads:haiku-worker', status: 'running' }, { id: 'slow', type: 'leads:haiku-worker', status: 'running' })
  void step($, 'claude-haiku-5-5', 'hung')
  const slow = step($, 'claude-haiku-5-5', 'slow')
  await clock.settle()
  await clock.advance(4 * 60 * 1000)
  expect(stopped).toEqual([])
  await clock.advance(4 * 60 * 1000)
  await slow

  expect(stopped).toEqual(['hung'])
})

test('a change of lead leaves running agents on what they run on', async ($, on) => {
  const agents: Agent[] = [{ id: 'plain-1', type: 'general-purpose', status: 'running' }]
  world(on, { agents })
  const sent = stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  agents.push({ id: 'fork-1', type: 'general-purpose', status: 'running' }, { id: 'worker-1', type: 'leads:opus-specialist', status: 'running' })
  await $.prompt.submit({ text: '@edith next', origin: { kind: 'composer' } })
  await step($, 'claude-haiku-5-5', 'plain-1')
  await step($, 'claude-sonnet-5-5', 'fork-1')
  await step($, 'claude-opus-5-5', 'worker-1')

  expect(sent).toEqual([
    { model: 'claude-haiku-5-5', effort: 'medium' },
    { model: 'claude-opus-5-5', effort: 'xhigh' },
    { model: 'claude-opus-5-5', effort: 'xhigh' },
  ])
})

test('a model that moves after selection stands, until a lead is selected again', async ($, on) => {
  world(on)
  const sent = stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  await step($, 'claude-sonnet-5-5')
  await step($, 'claude-opus-4-8')
  await $.prompt.submit({ text: '@ultron again', origin: { kind: 'composer' } })
  await step($, 'claude-opus-4-8')

  expect(sent.map(s => s.model)).toEqual(['claude-opus-5-5', 'claude-opus-4-8', 'claude-opus-5-5'])
})

test('picking the lead\'s own model keeps its effort', async ($, on) => {
  world(on)
  const sent = stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  await step($, 'claude-sonnet-5-5')
  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([
    { model: 'claude-opus-5-5', effort: 'xhigh' },
    { model: 'claude-opus-5-5', effort: 'xhigh' },
  ])
})

test('the band says what really runs when a model stands', async ($, on) => {
  world(on)
  stepped(on)
  on('ui.render', (_, e) => {
    const { Text } = _.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  await step($, 'claude-sonnet-5-5')
  await step($, 'claude-haiku-5-5')

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('Ultron · claude-haiku-5-5 · medium')
  await ui.unmount()
})

test('the baseline is stored, so a restarted process keeps a model the person picked', async ($, on) => {
  const { store } = world(on)
  stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  await step($, 'claude-sonnet-5-5')

  expect(store.get('lead:session-1')).toEqual({ lead: 'ultron', baseline: 'claude-sonnet-5-5', picked: false })
})

test('a process that starts on another model is no pick, so the lead stays pinned', async ($, on) => {
  world(on, { entries: { 'lead:session-1': { lead: 'ultron', baseline: 'claude-opus-5-5', picked: false } } })
  const sent = stepped(on)

  await step($, 'claude-sonnet-5-5')

  expect(sent).toEqual([{ model: 'claude-opus-5-5', effort: 'xhigh' }])
})

test('a model picked before a restart stands, and going back to the first one pins again', async ($, on) => {
  world(on, { entries: { 'lead:session-1': { lead: 'ultron', baseline: 'claude-opus-5-5', picked: true } } })
  const sent = stepped(on)

  await step($, 'claude-haiku-5-5')
  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([
    { model: 'claude-haiku-5-5', effort: 'medium' },
    { model: 'claude-opus-5-5', effort: 'xhigh' },
  ])
})

test('only the person can select a lead', async ($, on) => {
  world(on)
  const sent = stepped(on)

  for (const kind of ['task-notification', 'peer', 'scheduled-trigger'] as const) {
    await $.prompt.submit({ text: '@ultron take over', origin: { kind } as never })
  }
  await step($, 'claude-haiku-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'medium' }])
})

test('a prompt that was blocked moves nobody', async ($, on) => {
  const { store } = world(on, { isBlocked: text => text.includes('secret') })
  const sent = stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  await $.prompt.submit({ text: '@edith secret', origin: { kind: 'composer' } })
  await step($, 'claude-opus-4-8')

  expect(store.get('lead:session-1')).toMatchObject({ lead: 'ultron' })
  expect(sent).toEqual([{ model: 'claude-opus-5-5', effort: 'xhigh' }])
})

test('naming the active lead again does not resend its contract', async ($, on) => {
  const messages: object[] = []
  world(on, { messages })

  const first = await $.prompt.submit({ text: '@ultron one', origin: { kind: 'composer' } })
  messages.push(selected('ultron'))
  const again = await $.prompt.submit({ text: '@ultron two', origin: { kind: 'composer' } })

  expect('text' in first && first.context).toHaveLength(1)
  expect('text' in again && again.context).toBeUndefined()
  expect('text' in again && again.text).toBe('two')
})

test('returning to a session\'s own lead sends its contract again', async ($, on) => {
  const messages: object[] = [selected('jarvis')]
  world(on, { messages, entries: { 'lead:session-1': { lead: 'jarvis', native: 'ultron' } } })

  const back = await $.prompt.submit({ text: '@ultron back', origin: { kind: 'composer' } })

  expect('text' in back && back.context).toHaveLength(1)
})

test('naming a session\'s own lead from the start adds no copy', async ($, on) => {
  const messages: object[] = []
  world(on, { messages, env: { CLAUDE_CODE_AGENT: 'leads:ultron' } })

  const first = await $.prompt.submit({ text: '@ultron one', origin: { kind: 'composer' } })
  messages.push(prompted('one'), answered)
  const second = await $.prompt.submit({ text: '@ultron two', origin: { kind: 'composer' } })

  expect('text' in first && first.context).toBeUndefined()
  expect('text' in second && second.context).toBeUndefined()
})

test('naming the flag\'s lead in a chat older than the flag sends its contract', async ($, on) => {
  world(on, { messages: [prompted('plain question'), answered], env: { CLAUDE_CODE_AGENT: 'leads:ultron' } })

  const older = await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })

  expect('text' in older && older.context).toHaveLength(1)
})

test('a mention typed over a running turn selects only once its contract is delivered', async ($, on) => {
  const { store } = world(on, { entries: { 'lead:session-1': { lead: 'ultron' } } })
  on('session.append', (_, e, next) => next(e))
  const sent = stepped(on)
  const row = (text: string) => ({ door: 'hook-context', uuid: 'u', origin: { kind: 'hook' }, message: { type: 'attachment', role: 'user', content: [{ type: 'text', text }] } }) as never

  const queued = await $.prompt.submit({ text: '@edith next', origin: { kind: 'composer' }, turnId: 'running' })
  await step($, 'claude-opus-5-5')
  expect(store.get('lead:session-1')).toMatchObject({ lead: 'ultron' })

  await $.session.append(row('# Chat activation\n\n[leads:selected:edith]\nThe selected lead is Edith.'))
  await step($, 'claude-opus-5-5')

  expect('text' in queued && queued.context).toHaveLength(1)
  expect(store.get('lead:session-1')).toMatchObject({ lead: 'edith' })
  expect(sent.map(s => s.model)).toEqual(['claude-opus-5-5', 'claude-haiku-5-5'])
})

test('a person\'s own agent or folder of a lead\'s bare name stays theirs', async ($, on) => {
  const { store } = world(on, { folders: ['jarvis'], ownAgentFiles: ['.claude/agents/edith.md'] })

  for (const text of ['@jarvis look here', '@edith look here']) {
    const result = await $.prompt.submit({ text, origin: { kind: 'composer' } })
    expect('text' in result && result.text).toBe(text)
  }
  expect(store.has('lead:session-1')).toBe(false)

  const scoped = await $.prompt.submit({ text: '@leads:jarvis go', origin: { kind: 'composer' } })
  expect('text' in scoped && scoped.text).toBe('go')
  expect(store.get('lead:session-1')).toMatchObject({ lead: 'jarvis' })
})

test('the mention rows show only where a mention selects', async ($, on) => {
  world(on)
  on('prompt.autocomplete', () => ({ suggestions: [] }))
  const rows = async (text: string, start: number) =>
    (await $.prompt.autocomplete({ text, cursor: text.length, token: text.slice(start), start } as never)).suggestions

  expect(await rows('@ul', 0)).toHaveLength(1)
  expect(await rows('first\n  @ul', 8)).toHaveLength(1)
  expect(await rows('please @ul', 7)).toHaveLength(0)
})

test('the repeat of lead-off after a compaction is dropped, and other skills stay', async ($, on) => {
  world(on)
  on('prompt.attachment', (_, e) => ({ text: e.text }))
  const repeat = (text: string) => $.prompt.attachment({ type: 'invoked_skills', text } as never)

  expect((await repeat('Skills earlier:\n\n### Skill: leads:lead-off\nStop following\n### Skill: other\nKeep me')).text).toBe('Skills earlier:\n\n### Skill: other\nKeep me')
  expect((await repeat('Skills earlier:\n\n### Skill: leads:lead-off\nStop following')).text).toBeNull()
  expect((await repeat('Skills earlier:\n\n### Skill: other\nKeep me')).text).toBe('Skills earlier:\n\n### Skill: other\nKeep me')
})

test('plan mode is told which agents a lead refuses', async ($, on) => {
  world(on)
  on('prompt.attachment', (_, e) => ({ text: e.text }))
  const plan = () => $.prompt.attachment({ type: 'plan_mode', text: 'Launch Explore agents.' } as never)

  expect((await plan()).text).toBe('Launch Explore agents.')
  await $.prompt.submit({ text: '@jarvis go', origin: { kind: 'composer' } })
  expect((await plan()).text).toMatch(/Under Jarvis, the Explore and Plan agents above are refused/)
})

test('a lead skill keeps only its task, since the contract arrives beside the prompt', async ($, on) => {
  world(on)
  on('skill.prompt', (_, e) => ({ text: e.text }))

  const { text } = await $.skill.prompt({
    skill: 'leads:jarvis',
    text: 'Read the files.\n\nTask: fix: the Task: bug',
    frontmatter: {},
    source: 'plugin',
  } as never)

  expect(text).toBe('Task: fix: the Task: bug')
})

test('--agent makes a lead active', async ($, on) => {
  const { store } = world(on, { env: { CLAUDE_CODE_AGENT: 'jarvis' } })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
  expect(store.get('lead:session-1')).toMatchObject({ native: 'jarvis' })
})

test('a resume that does not name the main agent keeps its lead', async ($, on) => {
  world(on, { entries: { 'lead:session-1': { native: 'jarvis', baseline: 'claude-opus-5-5' } } })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
})

test('the agent variable alone does not make a lead when a print run composes the default prompt', async ($, on) => {
  const { store } = world(on, { env: { CLAUDE_CODE_AGENT: 'ultron' } })
  on('prompt.compose', () => ({ sections: [] }))
  const sent = stepped(on)

  await $.prompt.compose({ ...COMPOSED, traits: ['lean', 'print', 'skills'] })
  await step($, 'claude-haiku-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'medium' }])
  expect(store.has('lead:session-1')).toBe(false)
})

test('a terminal composes under --agent too, and a context report composes under any agent', async ($, on) => {
  world(on, { env: { CLAUDE_CODE_AGENT: 'ultron' } })
  on('prompt.compose', () => ({ sections: [] }))
  const sent = stepped(on)

  await $.prompt.compose({ ...COMPOSED, traits: ['lean', 'skills'] })
  await $.prompt.compose({ ...COMPOSED, traits: ['lean', 'print', 'analysis'] })
  await step($, 'claude-haiku-5-5')

  expect(sent).toEqual([{ model: 'claude-opus-5-5', effort: 'xhigh' }])
})

test('a person\'s own agent of a lead\'s name is left alone', async ($, on) => {
  world(on, { env: { CLAUDE_CODE_AGENT: 'jarvis' } })
  on('agent.offer', () => ({ isOffered: true }))
  const sent = stepped(on)

  await $.agent.offer({ agent: 'jarvis', description: 'mine', source: 'projectSettings', provider: {} } as never)
  await step($, 'claude-haiku-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'medium' }])
})

test('the agent setting makes a lead active, in either spelling', async ($, on) => {
  mock.store(on)
  mock.env(on, {})
  on('session.id', () => ({ value: 'session-1' }))
  on('session.messages', () => ({ value: [] }) as never)
  on('settings.read', () => ({ value: { agent: 'leads:edith' } }))
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'max' }])
})

test('the agent setting reaches new chats, not older ones', async ($, on) => {
  const { store } = world(on, { messages: [prompted('old question'), answered], settings: { agent: 'leads:edith' } })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-opus-5-5', effort: 'medium' }])
  expect(store.has('lead:session-1')).toBe(false)
})

test('--agent on an older chat brings its contract along', async ($, on) => {
  world(on, { env: { CLAUDE_CODE_AGENT: 'leads:ultron' }, messages: [prompted('old question'), answered] })

  const result = await $.prompt.submit({ text: 'next', origin: { kind: 'composer' } })

  expect('text' in result && result.context).toHaveLength(1)
  expect('text' in result && result.context?.[0]).toMatch(/\[leads:selected:ultron\]/)
})

test('a forked chat reads its lead back from its messages', async ($, on) => {
  world(on, { messages: [prompted('fix it'), selected('jarvis')] })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
})

test('a forked chat honors a later lead-off', async ($, on) => {
  world(on, { messages: [selected('jarvis'), prompted('[leads:selected:off]\nThe user deactivated the lead for this chat.')] })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-opus-5-5', effort: 'medium' }])
})

test('a selection outranks the compaction note, whichever reads first', async ($, on) => {
  world(on, { messages: [selected('edith'), kept('jarvis')] })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'max' }])
})

test('the compaction note alone keeps a fork on its lead', async ($, on) => {
  world(on, { messages: [kept('jarvis')] })
  const sent = stepped(on)

  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
})

test('text that quotes a marker, in words or inside a line, selects nobody', async ($, on) => {
  const toolResult = { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't', content: '[leads:selected:ultron]' }] }
  world(on, { messages: [toolResult, prompted('The selected lead is Ultron.'), prompted('see [leads:selected:ultron] here'), prompted('The user deactivated the lead')] })
  const sent = stepped(on)

  await step($, 'claude-haiku-5-5')

  expect(sent).toEqual([{ model: 'claude-haiku-5-5', effort: 'medium' }])
})

test('a broken store leaves a plain session plain and a lead on its lead', async ($, on) => {
  const { health } = world(on)
  const sent = stepped(on)
  const explore = { tool: 'Agent', prompt: 'go', description: 't', subagent_type: 'Explore' } as never

  health.isBroken = true
  expect((await $.tool.call(explore)).deny).toBeUndefined()
  await $.prompt.submit({ text: '@jarvis go', origin: { kind: 'composer' } })
  await step($, 'claude-opus-5-5')

  expect((await $.tool.call(explore)).deny).toMatch(/may delegate only/)
  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
})

test('a selection holds when the store cannot be written, and off takes effect', async ($, on) => {
  const { health } = world(on)
  const sent = stepped(on)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  health.isBroken = true
  await $.prompt.submit({ text: '@jarvis next', origin: { kind: 'composer' } })
  await step($, 'claude-opus-5-5')
  health.isBroken = false
  await step($, 'claude-opus-5-5')

  expect(sent.map(s => s.model)).toEqual(['claude-sonnet-5-5', 'claude-sonnet-5-5'])
})

test('with a broken store a resumed chat reads its lead from its messages', async ($, on) => {
  const { health } = world(on, { messages: [selected('jarvis')] })
  const sent = stepped(on)

  health.isBroken = true
  await step($, 'claude-opus-5-5')

  expect(sent).toEqual([{ model: 'claude-sonnet-5-5', effort: 'xhigh' }])
})

test('each lead reaches only its own workers, with no per-call overrides', async ($, on) => {
  world(on)

  const call = (input: object) =>
    $.tool.call({ tool: 'Agent', prompt: 'go', description: 't', ...input } as never)

  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  expect((await call({ subagent_type: 'leads:haiku-worker' })).deny).toBeUndefined()
  expect((await call({ subagent_type: 'leads:sonnet-worker' })).deny).toMatch(/may delegate only/)
  expect((await call({ subagent_type: 'leads:opus-specialist' })).deny).toMatch(/may delegate only/)

  await $.prompt.submit({ text: '@jarvis go', origin: { kind: 'composer' } })
  expect((await call({ subagent_type: 'leads:sonnet-worker' })).deny).toBeUndefined()
  expect((await call({ subagent_type: 'leads:opus-reviewer' })).deny).toMatch(/may delegate only/)
  expect((await call({ subagent_type: 'leads:opus-specialist' })).deny).toMatch(/may delegate only/)

  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  expect((await call({ subagent_type: 'leads:opus-specialist' })).deny).toBeUndefined()
  expect((await call({ subagent_type: 'leads:opus-reviewer' })).deny).toBeUndefined()
  expect((await call({ subagent_type: 'Explore' })).deny).toMatch(/may delegate only/)
  expect((await call({})).deny).toMatch(/may delegate only/)
  expect((await call({ subagent_type: 'leads:haiku-worker', model: 'opus' })).deny).toMatch(/owns/)
  expect((await call({ subagent_type: 'leads:haiku-worker', effort: 'low' })).deny).toMatch(/owns/)
})

test('a forked skill holds the same limits as its lead', async ($, on) => {
  world(on)

  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  const nested = await $.tool.call({
    tool: 'Agent',
    prompt: 'go',
    description: 't',
    subagent_type: 'Explore',
    agentId: 'fork-1',
  } as never)

  expect(nested.deny).toMatch(/may delegate only/)
})

test('a lead has no limit on running workers', async ($, on) => {
  const agents = Array.from({ length: 40 }, (_, index) => ({ id: `worker-${index}`, type: 'leads:haiku-worker', status: 'running' }))
  world(on, { agents })

  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  const ran = await $.tool.call({ tool: 'Agent', prompt: 'go', description: 't', subagent_type: 'leads:haiku-worker' } as never)

  expect(ran.deny).toBeUndefined()
})

test('Ultron may run workflows, Jarvis and Edith may not, and a plain session keeps them', async ($, on) => {
  world(on)
  const workflow = { tool: 'Workflow', script: 'x' } as never

  expect((await $.tool.call(workflow)).deny).toBeUndefined()
  await $.prompt.submit({ text: '@jarvis go', origin: { kind: 'composer' } })
  expect((await $.tool.call(workflow)).deny).toMatch(/not workflows/)
  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  expect((await $.tool.call(workflow)).deny).toMatch(/not workflows/)
  await $.prompt.submit({ text: '@ultron go', origin: { kind: 'composer' } })
  expect((await $.tool.call(workflow)).deny).toBeUndefined()
})

test('with no lead, delegation passes through', async ($, on) => {
  world(on)

  const ran = await $.tool.call({ tool: 'Agent', prompt: 'go', description: 't', subagent_type: 'Explore' } as never)

  expect(ran.deny).toBeUndefined()
})

test('a commit credits the model that ran it', async ($, on) => {
  world(on)
  stepped(on)
  on('attribution.text', (_, e) => ({ text: e.text }))
  const trailer = { kind: 'commit', text: 'Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>' } as const

  expect((await $.attribution.text(trailer)).text).toBe(trailer.text)

  await $.prompt.submit({ text: '@edith go', origin: { kind: 'composer' } })
  await step($, 'claude-opus-5-5')
  expect((await $.attribution.text(trailer)).text).toBe('Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>')

  await step($, 'claude-sonnet-5-5')
  expect((await $.attribution.text(trailer)).text).toBe(trailer.text)
})

test('the band names the active lead on every surface and keeps what is drawn beneath', async ($, on) => {
  world(on)
  on('ui.render', (_, e) => {
    const { Text } = _.ui.resolve(e)

    return <Text>engine</Text>
  })

  await $.prompt.submit({ text: '@jarvis go', origin: { kind: 'composer' } })

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text' }))?.text).toBe('Jarvis · Sonnet 5.5 · xhigh')
    expect(await ui.find({ text: 'engine' })).toBeTruthy()
    await ui.unmount()
  }
})
