# Chat activation

Read the selected lead's linked contract and the shared workflow. Act as that lead in the current chat, keeping its identity, delegation boundaries, and engineering principles for subsequent messages until the user explicitly selects another lead. Carry this choice through conversation summaries. An explicit role choice takes precedence over automatic task classification; if work exceeds the role's allowed scope, explain the required escalation without silently switching roles.

Continue any pending task or the task accompanying the selection immediately. If selection arrives alone with no pending task, acknowledge with the selected lead's exact startup greeting once and wait for the next request. Do not treat activation alone as a completed implementation or create a plan for it. Do not repeat the greeting for ordinary follow-up messages.

Activation needs no setup command, launcher, installation, new chat, or spawned lead. Use the installed native worker agents when delegating. Preserve the active chat's permissions and tool availability. The host controls the current chat model and reasoning effort; a selected role supplies instructions and cannot change them. Native worker TOMLs still select each child's configured model. Do not claim that role selection changed the main model.
