# M12 Launcher Preliminary Qualification

## Scope and Authorization

On October 22, 2026, between 12:57 and 13:10 Japan Standard Time as reported by the maintainer, the maintainer performed a preliminary check of the status reporting of the launcher selected for the [M12 GUI-emptiness feasibility procedure](../m12-gui-emptiness-feasibility.md): Terminal.app with a child `/bin/zsh -f`. The check ran only harmless child processes, entered one command at a time by the maintainer in the maintainer's existing ordinary macOS account. No agent operated the terminal. The check did not start GUIProbeMac, did not open or operate Music, and involved no Accessibility permission, Apple Events, test user, personal library, or file outside the commands recorded below.

The check is preliminary. It qualifies the launcher only within the tested account, configuration, and session, and it does not qualify the isolated test user in which a survey would run. It is not a run of the feasibility procedure, whose survey remains unexecuted, and it authorizes no survey, Music operation, rebuilding stage, or repetition of the check.

## Evidence and Provenance

The evidence has three sources, which this report keeps apart. The maintainer submitted the terminal transcript of the session to an independent reviewer engaged by the maintainer, who examined it. The observations attributed below to the transcript are those reported by the maintainer and that reviewer from it. Some facts were supplied separately by the maintainer and do not appear in the transcript: the operating-system product name and build, the Terminal.app application version, the clearing of the scrollback, and the closing of the test window. The repository assessment did not examine the original transcript. It relied on the sanitized reports, on the reviewed protocol, and on the internal consistency of the reported results with that protocol, in particular the accounting of history events below.

The reviewer first returned a conditional verdict because the first transcript excerpt ended at the final `exit`, leaving the return to the login shell unconfirmed. The maintainer then supplied the continuation, which shows the original login-shell prompt after `exit`, and the reviewer revised the verdict to a pass within the tested scope. The complete transcript also shows the wildcard of `/dev/null/*` and the job-state expression in their intended literal forms. A last-login time printed by the terminal before the session is not the execution date.

The expected values against which the results were compared come from earlier measurements in a development pseudo-terminal outside Terminal.app. Those measurements are preliminary and are not evidence about the session.

## Environment

| Item | Value | Source |
| --- | --- | --- |
| macOS product version | 27.0.1 | Transcript (`sw_vers -productVersion`) |
| macOS product name and build | Golden Gate, 26A434 | Maintainer's statement |
| Terminal application | Terminal.app 2.15 | Maintainer's statement (About Terminal) |
| Terminal identification | `TERM_PROGRAM` `Apple_Terminal`, `TERM_PROGRAM_VERSION` 488 | Transcript |
| Shell | `/bin/zsh -f`, zsh 5.9 | Transcript |
| Shell level of the clean shell | 2 | Transcript |
| Account | The maintainer's existing ordinary account, not an isolated test user | Maintainer's statement |

## Results

All ten configuration checks after the prompt assignment passed. The clean shell had no functions, the two zsh default aliases `run-help=man` and `which-command=whence`, no global or suffix aliases, all eight inspected environment variables unset, `TMOUT` unset, and no jobs. The options `rcs`, `errexit`, `errreturn`, `printexitvalue`, and `pipefail` were off, and `notify` and `monitor` were on; the complete list of set options was `interactive`, `monitor`, `norcs`, `shinstdin`, and `zle`. Every inspected hook array and the count of user widgets were zero, and no trap was set. The clean shell's process identifier differed from that of its parent, the login shell. The SHA-256 digest of `/etc/zshenv` matched the reference recorded earlier for the same installation. That reference is specific to that installation and is not a constant of macOS; the digest is not reproduced here.

The thirteen harmless children, each followed immediately by the status capture, reported the statuses below. Every capture showed the clean shell's original process identifier and the history number of its own prompt, and every row matched its expected result.

| Row | Child | Status | Shell message |
| --- | --- | --- | --- |
| C1 | `exit 0` | 0 | None |
| C2 | `exit 1` | 1 | None |
| C3 | `exit 2` | 2 | None |
| C4 | `exit 142` | 142 | None |
| C5 | self-termination by `SIGALRM` | 142 | Alarm notice |
| C6 | `exit 130` | 130 | None |
| C7 | self-termination by `SIGINT` | 130 | None |
| C8 | command not found | 127 | Lookup failure |
| C9 | file that is not executable | 126 | Permission failure |
| C10 | failed output redirection | 1 | Redirection failure; child not run |
| C11 | failed parameter expansion | 1 | Expansion failure; child not run |
| C12 | unmatched glob | 1 | No matches; child not run |
| C13 | pipeline ending in `exit 0` | 0 | None; status of the last command |

Rows C4 and C5, and rows C6 and C7, show that an intentional exit and termination by a signal can produce the same status. The termination by `SIGINT` in row C7 produced no shell message, so the absence of a message did not distinguish it from the intentional exit in row C6. Rows C10 through C12 show a status of 1 without the child having run.

The suspended-child checks followed their safe order. The job table was empty. A newly created harmless child then suspended itself, the shell reported the suspension, and the immediate capture reported 145 with the original process identifier and the correct history number. The job table then held exactly one suspended job with the expected command text, and the job listing showed job 1 with the same command and a child process identifier distinct from both shell identifiers. Only after these identity conditions held was the job resumed with `builtin fg %1`; the shell reported its continuation, the immediate capture reported 0 with the original identifier and the correct history number, and the job table was empty again.

In the status-replacement control, a child that exited with 1 was followed by `true`, and the capture then reported 0, at history events 47 through 49. The final checks reported the original process identifier and shell level unchanged, no jobs, no functions, the two default aliases, no hooks, and no traps. After the final `exit`, the transcript shows the original login-shell prompt.

The reported history events of the clean shell form one sequence from 1 to 53. Event 1 set the prompt, and events 2 through 11 were the ten configuration checks. Event 12 was an additional status capture. Events 13 through 38 were the thirteen children, each with its immediate capture, and events 39 through 46 were the eight suspended-child commands. Events 47 through 49 were the status-replacement control, events 50 through 52 the final checks, and event 53 the final `exit`; the login-shell prompt that followed lies outside this sequence. The submitted sequence shows no unexplained gap. This is a consistency check of attribution and continuity within the transcript, not proof that nothing occurred outside it.

## Deviations

One deviation occurred. At event 12, between the digest check and the first child, the maintainer entered one additional status capture, which returned 0. It only printed shell values and did not fall between any child and its capture, so it is recorded as a harmless procedural deviation and does not affect the result.

## Privacy and Custody

This report contains no terminal output, account or computer name, process identifier, private path, shell-history contents, environment-variable values other than the terminal identification in the Environment section, or identifier mapping. The event numbers, statuses, option states, and counts above are the technical findings of the check, not private history contents, and the system paths in the archival record identify reviewed commands only. The maintainer stated that the scrollback was cleared and the test window closed after the session; these are the maintainer's statements, not terminal output. The complete transcript was shared with the independent reviewer, and the erasure of copies already shared cannot be established; this exposure is not reversed by this report. Later runs, including the repetition of this check in the isolated test user, return only privacy-reviewed summaries, and the original evidence and any identifier mappings remain in the operator's custody.

## Interpretation and Limits

The check passes within its tested scope. In the tested session, the launcher reported intentional exits, termination by a signal, failed lookup and execution, failed expansion and redirection, and a pipeline as expected; it allowed a suspended child to be identified and resumed safely; and the transcript showed no evidence of a discontinuity of the clean shell before its intended exit. It also demonstrated that a status of 130 or 142, which a program can return intentionally, does not by itself establish termination by a signal.

The check does not establish the behavior of GUIProbeMac, its hard stop during a live Accessibility request, its behavior across system sleep, the effect on Music of a client that ends abruptly, the Accessibility hierarchy of Music, the program that macOS treats as the Accessibility permission principal, or the environment and results of the future isolated test user. It does not make `candidateEmpty` reachable and does not satisfy the GUI-emptiness gate of Decision 52.

## Consequences for the Survey Contract

The same change that adds this report corrects the section "Recording the Process Outcome" of the feasibility procedure. That section previously stated that a status greater than 128 means that the process did not end by an exit of its own. It now separates the classification of evidence from its acceptance. A shell message that names a signal, reports a stopped job, or reports a failed lookup, execution, expansion, or redirection is recorded as such. A status greater than 128, 126, or 127 without a message of the matching kind is an unknown outcome, and every status other than 0, 1, or 2 remains nonqualifying. The continuity contract now also requires the immediate status capture to report the history number of its own prompt, exactly one greater than that of the invocation, and records the shell level before the invocation and after the capture. The isolated test user's launcher must pass the same check, with harmless children and never with the probe, before a survey is authorized.

## Archival Command Record

The commands below are recorded exactly as they appear in the reviewed protocol that the maintainer followed. They document what was run. They do not authorize or instruct a new run, which requires the maintainer's separate authorization and the complete protocol with its pacing, status-capture, identity, and stop conditions. In particular, the suspended-child commands of events 39 through 46 are not safe to take out of their verified order or to run without those conditions.

In the login shell of a new Terminal.app window:

```text
/bin/zsh -f
```

Events 1 through 11 in the clean shell:

```text
PS1='[clean %h] %# '
\builtin print -r -- "funcs=${#functions} aliases=${#aliases} galiases=${#galiases} saliases=${#saliases} env=${+ENV}${+BASH_ENV}${+SHELLOPTS}${+POSIXLY_CORRECT}${+PROMPT_COMMAND}${+ZDOTDIR}${+PERL5LIB}${+PERL5OPT} tmout=${+TMOUT} jobs=${#jobstates}"
\builtin print -r -- "zsh=$ZSH_VERSION pid=$$ ppid=$PPID shlvl=$SHLVL term=${TERM_PROGRAM-unset} termv=${TERM_PROGRAM_VERSION-unset}"
\builtin print -r -- "rcs=$options[rcs] errexit=$options[errexit] errreturn=$options[errreturn] pev=$options[printexitvalue] pipefail=$options[pipefail] notify=$options[notify] monitor=$options[monitor]"
\builtin print -r -- "precmd=${#precmd_functions} preexec=${#preexec_functions} chpwd=${#chpwd_functions} periodic=${#periodic_functions} addhist=${#zshaddhistory_functions} zshexit=${#zshexit_functions} user_widgets=${#${(M)${(v)widgets}:#user:*}}"
\builtin setopt
\builtin alias
\builtin trap
\builtin jobs
/usr/bin/sw_vers -productVersion
/usr/bin/shasum -a 256 /etc/zshenv
```

Event 12, the additional status capture, used the status-capture command, which also follows every child below:

```text
builtin print -r -- $? $$ $HISTCMD
```

Events 13 through 38, each child followed immediately by the status capture:

```text
/bin/sh -c 'exit 0'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 1'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 2'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 142'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'kill -ALRM $$'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 130'
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'kill -INT $$'
builtin print -r -- $? $$ $HISTCMD
/nonexistent/harmless-child
builtin print -r -- $? $$ $HISTCMD
/etc/hosts
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 0' > /dev/null/out
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 0' ${undefined_name?x}
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 0' /dev/null/*
builtin print -r -- $? $$ $HISTCMD
/bin/sh -c 'exit 1' | /bin/sh -c 'exit 0'
builtin print -r -- $? $$ $HISTCMD
```

Events 39 through 46, the suspended-child sequence, in which `builtin fg %1` was entered only after every identity condition had held:

```text
builtin print -r -- "jobs=${#jobstates}"
/bin/sh -c 'kill -STOP $$'
builtin print -r -- $? $$ $HISTCMD
builtin print -r -- "jobs=${#jobstates} state=${jobstates[1]%%:*} text=${jobtexts[1]}"
builtin jobs -l
builtin fg %1
builtin print -r -- $? $$ $HISTCMD
builtin print -r -- "jobs=${#jobstates}"
```

Events 47 through 49, the status-replacement control:

```text
/bin/sh -c 'exit 1'
true
builtin print -r -- $? $$ $HISTCMD
```

Events 50 through 53, the final checks and the exit:

```text
\builtin print -r -- "pid=$$ shlvl=$SHLVL hist=$HISTCMD jobs=${#jobstates} funcs=${#functions} aliases=${#aliases}"
\builtin print -r -- "precmd=${#precmd_functions} preexec=${#preexec_functions} chpwd=${#chpwd_functions} periodic=${#periodic_functions} addhist=${#zshaddhistory_functions} zshexit=${#zshexit_functions}"
\builtin trap
exit
```

The protocol also contained one optional read-only command for an unexpected loss of the clean shell, in which no job may be resumed, stopped, or signaled. That condition did not arise, and the command was not run:

```text
\builtin jobs -l
```
