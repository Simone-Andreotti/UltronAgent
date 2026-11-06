import { atom, read, update } from 'claude-code'
import type { ApiMessage, EngineInterface, Register, TurnStepChunk } from 'claude-code'

import type { RunningLead } from '../types'
import { isLeadId, LEADS, leadFromAgentName, namesLead, parseMention, WORKER_EFFORT } from './leads'
import type { Lead, LeadId } from './leads'

const OFF = 'off'
const MAX_REMEMBERED_SESSIONS = 200
const STALL_MINUTES = 5
const PERSON_ORIGINS: readonly string[] = ['composer', 'bridge', 'sdk']

// What a chat's own messages say about its lead, on a line of their own:
// `activationText` and the lead-off skill write a selection, and compaction leaves
// a note of what it removed. No sentence would do, since a prompt or an attached
// file can quote one.
const MARKER = /^\[leads:(selected|kept):(ultron|jarvis|edith|off)\]$/gm

// What the engine's summary must carry, since it is all a lead continues from.
const SUMMARY_KEEPS = "Keep the active plan file's path and milestone, every child still running, every child branch not yet merged, and every claim not yet verified."

const running = atom({ plugin: 'leads', key: 'running' } as const, null)

// A session's lead, kept in the store so it survives a resume and a desktop
// process restart.
type Selection = {
  // Chosen in this chat with a mention or a skill; it beats the main agent.
  lead?: LeadId | typeof OFF
  // The session's main agent, since a resume does not name it again.
  native?: LeadId
  // The model this process started the lead on. While it stands the lead's model
  // is pinned; when it moves, the person chose another model or a safety fallback
  // swapped it, and both are left to stand.
  baseline?: string
  // Whether it had moved, which is what a restarted process has to know: the model
  // it starts on is otherwise no choice, since a GUI reopens a chat on its own picker's.
  picked?: boolean
}

const selectionKey = async ($: EngineInterface) => `lead:${await $.session.id()}`

const markerIn = (messages: readonly ApiMessage[]) => {
  // Prompt text only: a file or a tool result quoting these words selects nobody.
  const prompts = messages
    .filter(({ role }) => role === 'user')
    .flatMap(({ content }) => content.flatMap(block => (block.type === 'text' ? [block.text] : [])))
  const found = [...prompts.join('\n').matchAll(MARKER)]
  // Compaction removes every older selection, and the engine can lift a newer one
  // above its note, so any selection still there outranks the note.
  const last = found.filter(([, kind]) => kind === 'selected').at(-1) ?? found.at(-1)

  return last?.[2] as LeadId | typeof OFF | undefined
}

// A forked chat has a new id and the old chat's messages, so it reads its lead
// back from them.
const checkedSessions = new Set<string>()

const recoverSelection = async ($: EngineInterface, key: string): Promise<Selection | undefined> => {
  if (checkedSessions.has(key)) return undefined
  const messages = await $.session.messages({ as: 'api' })
  if (messages.length === 0) return undefined

  checkedSessions.add(key)
  const lead = markerIn(messages)
  if (!lead) return undefined
  await $.store.set(key, { lead })

  return { lead }
}

// Sessions share the store's file, which can be locked for a moment or corrupt, and
// a write can fail. What this process last knew therefore comes first, and with a
// broken store a chat's own messages name its lead.
const known = new Map<string, Selection>()

const readSelection = async ($: EngineInterface): Promise<Selection | undefined> => {
  const key = await selectionKey($)
  const held = known.get(key)
  if (held) return held

  try {
    const selection = ((await $.store.get(key)) as Selection | undefined) ?? (await recoverSelection($, key))
    if (selection) known.set(key, selection)

    return selection
  } catch {
    const lead = markerIn(await $.session.messages({ as: 'api' }))

    return lead ? { lead } : undefined
  }
}

const writeSelection = async ($: EngineInterface, selection: Selection) => {
  const key = await selectionKey($)
  known.set(key, selection)
  try {
    // Evicted oldest first, so a chat in use moves to the end.
    await $.store.delete(key)
    await $.store.set(key, selection)
    const keys = (await $.store.keys()).filter(stored => stored.startsWith('lead:'))
    for (const old of keys.slice(0, Math.max(0, keys.length - MAX_REMEMBERED_SESSIONS))) {
      await $.store.delete(old)
    }
  } catch {
    // `known` holds it for this process.
  }
}

// A `claude -p` composes the default prompt only when no main agent's is in force,
// which tells `--agent` from a process that merely inherited its variable, such as
// one run from a lead's shell. A terminal composes with or without the flag.
let isDefaultPrompt = false
// A person's own agent of a lead's bare name; `--agent jarvis` then means theirs.
const ownAgents = new Set<string>()
// The session's main agent as this process read it back: /clear keeps its prompt.
let nativeHere: LeadId | undefined

const hasOwnAgent = async ($: EngineInterface, id: LeadId) =>
  ownAgents.has(id) || (await $.fs.ancestors({ names: [`.claude/agents/${id}.md`] })).length > 0

const namedLead = async ($: EngineInterface, name: unknown) =>
  isLeadId(name) && (await hasOwnAgent($, name)) ? undefined : leadFromAgentName(name)

const isFresh = async ($: EngineInterface) =>
  !(await $.session.messages({ as: 'api' })).some(({ role }) => role === 'assistant')

const nativeLead = async ($: EngineInterface) => {
  const flag = await $.env.get('CLAUDE_CODE_AGENT')
  if (flag && !isDefaultPrompt) return namedLead($, flag)

  // A setting reaches new chats; an older chat was started without it.
  const lead = (await namedLead($, await $.settings.read({ key: 'agent' }))) ?? (nativeHere && LEADS[nativeHere])

  return lead && (await isFresh($)) ? lead : undefined
}

const leadOf = async ($: EngineInterface, selection: Selection | undefined): Promise<Lead | undefined> => {
  if (selection?.native) nativeHere = selection.native
  const id = selection?.lead ?? selection?.native ?? (await nativeLead($))?.id

  return isLeadId(id) ? LEADS[id] : undefined
}

const activeLead = async ($: EngineInterface) => leadOf($, await readSelection($))

// A lead running as the session's main agent already has this in its system
// prompt; any other lead gets it as text the model reads.
const contractOf = async ($: EngineInterface, lead: Lead) => {
  const file = await $.fs.read(`${$.plugin.root}/agents/${lead.id}.md`)

  return String(file).replace(/^---[\s\S]*?\n---\s*/, '')
}

const activationText = async ($: EngineInterface, lead: Lead, kind: 'selected' | 'kept' = 'selected') =>
  [
    String(await $.fs.read(`${$.plugin.root}/references/chat-activation.md`)),
    `[leads:${kind}:${lead.id}]\nThe selected lead is ${lead.label}. You run on ${lead.modelLabel} at ${lead.effort} effort, whatever the environment section names. Its contract:`,
    await contractOf($, lead),
  ].join('\n\n')

// The newest selection in the chat decides what the model last read, even in a
// session started on this lead; failing that, its system prompt holds the contract.
const contractInChat = async ($: EngineInterface, selection: Selection | undefined, lead: Lead) => {
  const said = markerIn(await $.session.messages({ as: 'api' }))
  if (said) return said === lead.id

  return selection?.native === lead.id || ((await isFresh($)) && (await nativeLead($))?.id === lead.id)
}

const describe = (lead: RunningLead) => [lead.label, lead.model, lead.effort].filter(Boolean).join(' · ')

const showRunning = async ($: EngineInterface, next: RunningLead | null) => {
  await update($, running, () => next)
  if (!next) $.ui.status(undefined)
}

// The band above the prompt has one drawer at a time, and another plugin's band
// that does not call next hides this one. A band not redrawn since the last request
// is hidden, so the lead is pinned as a status line for as long as that lasts.
let bandDraws = 0
let isStatusPinned = false

const labelled = (lead: Lead, model = lead.modelLabel, effort: RunningLead['effort'] = lead.effort): RunningLead => ({
  label: lead.label,
  model,
  effort,
})

// The lead an agent started under, once a selection has moved on from it. A person
// types the next mention while workers run, since a waiting lead hands back the prompt.
const startedUnder = new Map<string, Lead | undefined>()
// This process's baseline for a chat: the first step it sees, or the stored one
// when the person had moved off it.
const baselineHere = new Map<string, string>()

const select = async ($: EngineInterface, value: LeadId | typeof OFF, previous: Selection | undefined) => {
  const before = await leadOf($, previous)
  for (const { id } of await $.agent.list()) {
    if (!startedUnder.has(id)) startedUnder.set(id, before)
  }
  baselineHere.delete(await selectionKey($))
  await writeSelection($, { lead: value, native: previous?.native ?? (await nativeLead($))?.id })
  await showRunning($, value === OFF ? null : labelled(LEADS[value]))
}

// A lead waits on a notification, so a child whose model request never answers
// would hold it for good. Stopping the child is what sends that notification. Tools
// are not steps, so a long-running command does not count as silence.
async function* watched($: EngineInterface, agentId: string, stream: AsyncIterable<TurnStepChunk>) {
  let silentMinutes = 0
  const tick = $.clock.every(60 * 1000, () => {
    silentMinutes += 1
    if (silentMinutes === STALL_MINUTES) void $.tool.call({ tool: 'TaskStop', task_id: agentId } as never)
  })
  try {
    for await (const chunk of stream) {
      silentMinutes = 0
      yield chunk
    }
  } finally {
    tick.cancel()
  }
}

// Whether the main loop's last request ran on the lead's own model.
let isModelPinned = true

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const lead = await activeLead($)
    await showRunning($, lead ? labelled(lead) : null)

    return next(e)
  })

  on('prompt.compose', (_, e, next) => {
    // A context report composes under any agent.
    if (e.traits.includes('print') && !e.traits.includes('analysis')) isDefaultPrompt = true

    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const isOff = e.command?.name === 'leads:lead-off'
    const commanded = e.command?.name.startsWith('leads:') ? leadFromAgentName(e.command.name) : undefined
    // A worker's notification or another session's message never selects a lead.
    const isPerson = !e.command && PERSON_ORIGINS.includes(e.origin.kind)
    const parsed = isPerson ? parseMention(e.text) : undefined
    // A person's own agent or folder of a lead's bare name stays theirs; `@leads:jarvis` still selects.
    const isTheirs = parsed && !parsed.isScoped && ((await hasOwnAgent($, parsed.lead.id)) || (await $.fs.exists(parsed.lead.id)))
    const mention = isTheirs ? undefined : parsed
    const lead = commanded ?? mention?.lead
    if (!lead && !isOff) {
      if (isPerson && !parsed && namesLead(e.text)) $.ui.toast('A lead is selected only at the start of a line, so this message stays with the current one.')

      // `--resume <plain> --agent <lead>`: the engine does not bring the agent's prompt to an older chat.
      const flagged = (await readSelection($)) ? undefined : await nativeLead($)

      return flagged && !(await isFresh($))
        ? next({ ...e, context: [...(e.context ?? []), await activationText($, flagged)] })
        : next(e)
    }

    const previous = await readSelection($)
    const hasContract = !lead || (await contractInChat($, previous, lead))
    const selected = {
      ...e,
      ...(mention ? { text: mention.task || '(lead selected, no task yet)' } : {}),
      ...(hasContract ? {} : { context: [...(e.context ?? []), await activationText($, lead)] }),
    }
    // Typed over a running turn it fires at Enter and can still be taken back, and
    // that turn's steps are not its own. The selection waits for the row that
    // delivers its contract.
    if (mention && e.turnId && !hasContract) return next(selected)

    await select($, lead?.id ?? OFF, previous)
    const result = await next(selected)
    if (result.drop !== undefined) {
      await writeSelection($, previous ?? {})
      const restored = await leadOf($, previous)
      await showRunning($, restored ? labelled(restored) : null)
    }

    return result
  })

  // The contract arrives beside the prompt. The skill's own instruction to read it
  // is for when this runtime is not loaded: it would cost a request and, in a
  // default permission mode, two prompts, and the engine repeats whatever a skill's
  // text holds after every compaction.
  on('skill.prompt', { skill: ['leads:ultron', 'leads:jarvis', 'leads:edith'] }, async (_, e, next) => {
    const { text } = await next(e)

    return { text: text.slice(text.indexOf('Task:')) }
  })

  on('session.append', { door: 'hook-context' }, async ($, e, next) => {
    const value = e.agentId === undefined ? markerIn([{ role: 'user', content: e.message.content ?? [] } as ApiMessage]) : undefined
    if (value) {
      const previous = await readSelection($)
      if (previous?.lead !== value) await select($, value, previous)
    }

    return next(e)
  })

  // The engine repeats every invoked skill after a compaction, and lead-off's order
  // to stop was for one moment.
  on('prompt.attachment', { type: 'invoked_skills' }, async (_, e, next) => {
    const { text } = await next(e)
    if (!text?.includes('### Skill: leads:lead-off')) return { text }

    const kept = text.replace(/### Skill: leads:lead-off[\s\S]*?(?=### Skill: |$)/, '')

    return { text: kept.includes('### Skill: ') ? kept : null }
  })

  // The engine's plan mode orders the agents a lead refuses.
  on('prompt.attachment', { type: 'plan_mode' }, async ($, e, next) => {
    const result = await next(e)
    const lead = result.text ? await activeLead($) : undefined

    return lead
      ? { text: `${result.text}\n\nUnder ${lead.label}, the Explore and Plan agents above are refused: use leads:haiku-code-analyst for exploration, and write the plan yourself.` }
      : result
  })

  on('prompt.autocomplete', { token: /^@/ }, async ($, e, next) => {
    const result = await next(e)
    if (!/(?:^|\n)[ \t]*$/.test(e.text.slice(0, e.start))) return result

    const token = e.token.toLowerCase()
    const rows = Object.values(LEADS)
      .filter(lead => `@${lead.id}`.startsWith(token))
      .map(lead => ({
        text: `@${lead.id}`,
        description: `${lead.label} leads this chat on ${lead.modelLabel}`,
      }))

    return { suggestions: [...rows, ...result.suggestions] }
  })

  on('turn.step', async function* ($, e, next) {
    const selection = await readSelection($)
    const lead = await leadOf($, selection)

    // A worker keeps the tier in its file. A forked skill has no such file, so it
    // runs on the lead that started it, an agent from before any lead keeps what
    // it has, and the engine's own forks are not listed.
    if (e.agentId !== undefined) {
      const owner = startedUnder.has(e.agentId) ? startedUnder.get(e.agentId) : lead
      const agent = owner && (await $.agent.list()).find(({ id }) => id === e.agentId)
      if (!owner || !agent) return yield* next(e)

      const effort = WORKER_EFFORT[agent.type]

      return yield* watched($, e.agentId, next(effort ? { ...e, effort } : { ...e, model: owner.model, effort: owner.effort }))
    }

    if (!lead) {
      await showRunning($, null)

      return yield* next(e)
    }

    const key = await selectionKey($)
    const isFirstHere = !baselineHere.has(key)
    const baseline = baselineHere.get(key) ?? (selection?.picked ? selection.baseline : undefined) ?? e.model
    baselineHere.set(key, baseline)
    isModelPinned = e.model === baseline || e.model === lead.model
    if (isFirstHere || Boolean(selection?.picked) === isModelPinned) {
      await writeSelection($, { ...selection, baseline, picked: !isModelPinned, ...(selection?.lead ? {} : { native: lead.id }) })
    }
    const shown = isModelPinned ? labelled(lead) : labelled(lead, e.model, e.effort)
    isStatusPinned = bandDraws === 0
    bandDraws = 0
    $.ui.status(isStatusPinned ? describe(shown) : undefined)
    await showRunning($, shown)

    return yield* next(isModelPinned ? { ...e, model: lead.model, effort: lead.effort } : e)
  })

  // Compaction drops the text a selection added, so the contract goes back in
  // after the summary and holds for the rest of a running turn too.
  on('session.compact', async ($, e, next) => {
    const selection = await readSelection($)
    const lead = e.agentId === undefined ? await leadOf($, selection) : undefined
    const said = lead && markerIn(await $.session.messages({ as: 'api' }))
    const result = await next(lead ? { ...e, instructions: [e.instructions, SUMMARY_KEEPS].filter(Boolean).join('\n\n') } : e)
    if (!lead || e.trigger === 'precompute' || !result.messages) return result
    // With no selection in the chat its contract is the system prompt.
    if (!said && selection?.native === lead.id) return result

    const text = `Compaction removed this; it still applies, unless a selection of another lead sits beside or above this note, which came later and wins. Do not repeat the greeting.\n\n${await activationText($, lead, 'kept')}`

    return { ...result, messages: [...result.messages, { role: 'user', text, toolUses: [] }] }
  })

  // The trailer names the lead's model for its whole session, not the session's own.
  // The event does not say which loop asks, so a worker told to commit reads the same.
  on('attribution.text', { kind: 'commit' }, async ($, e, next) => {
    const result = await next(e)
    const lead = isModelPinned ? await activeLead($) : undefined

    return lead ? { text: result.text.replace(/Claude [^<\n]*?(?= <)/, `Claude ${lead.modelLabel}`) } : result
  })

  // Only the active lead's workers are offered. With no lead, this plugin's
  // agents stay out of the listing, so a plain session pays nothing for them.
  on('agent.offer', async ($, e, next) => {
    if (isLeadId(e.agent)) ownAgents.add(e.agent)

    const lead = await activeLead($)
    if (lead) return { isOffered: lead.workers.includes(e.agent) }

    return e.agent.startsWith('leads:') ? { isOffered: false } : next(e)
  })

  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    const lead = await activeLead($)
    if (!lead) return next(e)

    if (!e.subagent_type || !lead.workers.includes(e.subagent_type)) {
      return { deny: `${lead.label} may delegate only to: ${lead.workers.join(', ')}.` }
    }
    if (e.model || e.effort) {
      return { deny: `The agent file owns ${e.subagent_type}'s model and effort. Call it without them.` }
    }

    return next(e)
  }).catch(($, e, next) => (next.called ? next(e) : { deny: `${$.plugin.name}: its routing guard failed.` }))

  on('tool.call', { tool: 'Workflow' }, async ($, e, next) => {
    const lead = await activeLead($)

    // A workflow's agents can run on any tier, so only the lead with every tier starts one.
    return lead && lead.id !== 'ultron' ? { deny: `${lead.label} delegates through its own workers, not workflows.` } : next(e)
  }).catch(($, e, next) => (next.called ? next(e) : { deny: `${$.plugin.name}: its routing guard failed.` }))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const lead = await read($, running)
    if (!lead || e.props.hasSurvey) return next(e)

    bandDraws += 1
    if (isStatusPinned) {
      isStatusPinned = false
      $.ui.status(undefined)
    }

    const { Box, Text } = $.ui.resolve(e)
    const beneath = await next(e)

    return (
      <Box flexDirection="column">
        <Text dimColor>{describe(lead)}</Text>
        {beneath}
      </Box>
    )
  })
}
