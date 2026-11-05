export type LeadId = 'ultron' | 'jarvis' | 'edith'

export type Lead = {
  id: LeadId
  label: string
  model: string
  modelLabel: string
  effort: 'xhigh' | 'max'
  workers: readonly string[]
}

const HAIKU_ROLES = [
  'leads:haiku-code-analyst',
  'leads:haiku-researcher',
  'leads:haiku-worker',
] as const

export const LEADS: Readonly<Record<LeadId, Lead>> = {
  ultron: {
    id: 'ultron',
    label: 'Ultron',
    model: 'claude-opus-5-5',
    modelLabel: 'Opus 5.5',
    effort: 'xhigh',
    workers: [...HAIKU_ROLES, 'leads:sonnet-worker', 'leads:opus-specialist'],
  },
  jarvis: {
    id: 'jarvis',
    label: 'Jarvis',
    model: 'claude-sonnet-5-5',
    modelLabel: 'Sonnet 5.5',
    effort: 'xhigh',
    workers: [...HAIKU_ROLES, 'leads:sonnet-worker'],
  },
  edith: {
    id: 'edith',
    label: 'Edith',
    model: 'claude-haiku-5-5',
    modelLabel: 'Haiku 5.5',
    effort: 'max',
    workers: HAIKU_ROLES,
  },
}

// A worker's file names its effort, but the person's CLAUDE_CODE_EFFORT_LEVEL
// outranks a file, and only a request can outrank that.
export const WORKER_EFFORT: Readonly<Record<string, Lead['effort']>> = {
  'leads:haiku-code-analyst': 'max',
  'leads:haiku-researcher': 'max',
  'leads:haiku-worker': 'max',
  'leads:sonnet-worker': 'xhigh',
  'leads:opus-specialist': 'xhigh',
}

export const isLeadId = (value: unknown): value is LeadId =>
  value === 'ultron' || value === 'jarvis' || value === 'edith'

// An agent name as `--agent` or the `agent` setting spell it: bare or scoped.
export const leadFromAgentName = (name: unknown): Lead | undefined => {
  const bare = typeof name === 'string' ? name.replace(/^leads:/, '') : ''

  return isLeadId(bare) ? LEADS[bare] : undefined
}

// `@ultron` at the start of a line, in any case, selects that lead. The first one
// wins, so a pasted thread below it stays the task; four spaces of indent is code.
// `@ultron.md`, `@ultron/x` and `@ultron's` stay text. The terminal's own agent row
// writes `@leads:jarvis (agent)`, in quotes when taken with Enter, and Tab adds no
// space after it.
const MENTION = /^\u0001* {0,3}@"?(?:agent-)?(?:leads:)?(ultron|jarvis|edith)(?: \(agent\)"?|"|(?=[ \t,]|:(?:[ \t]|$)|$))[:,]?[ \t]*/gim

// Named anywhere else, it selects nobody.
const NAMED = /(?:^|\s)@(?:leads:)?(?:ultron|jarvis|edith)(?![\w./-])/i

// What a person fenced or the IDE attached is quoted, not addressed to a lead. A
// mention can follow an IDE block on its line, so a blank span stays apart from
// real indentation.
const QUOTED = /```.*?```|^ {0,3}(```|~~~)[\s\S]*?(?:^ {0,3}\1|(?![\s\S]))|<(ide_selection|ide_opened_file)>[\s\S]*?<\/\2>/gm

const unquoted = (text: string) => text.replace(QUOTED, quoted => quoted.replace(/[^\r\n]/g, '\u0001'))

export const namesLead = (text: string) => NAMED.test(unquoted(text))

export const parseMention = (text: string): { lead: Lead; task: string; isScoped: boolean } | undefined => {
  const first = [...unquoted(text).matchAll(MENTION)][0]
  if (!first) return undefined

  const handle = first.index + first[0].indexOf('@')

  return {
    lead: LEADS[first[1].toLowerCase() as LeadId],
    task: (text.slice(0, handle) + text.slice(first.index + first[0].length)).trim(),
    isScoped: /leads:/i.test(first[0]),
  }
}
