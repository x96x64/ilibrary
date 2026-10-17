# Plan for the Stable Release

## Status and Evidence

Approved by the maintainer on October 17, 2026. This plan supersedes the prospective version assignments in the [historical study](planning-study.md#outlook-to-version-100), not its completed measurements. Version 0.1.0 is published. The maintainer authorized M10 preparation and required a stop before operations in a separate macOS user. Personal-library operations and future publication are not authorized by this plan.

The existing measurements cover 301 private-file copies and twelve separate-user Music command checks. They do not establish evacuation, automatic registration removal, or an identical addition timestamp across an entire rebuilt library. Music's installed scripting dictionary declares `date added` read-only; that is interface evidence, not evidence that quitting Music produces identical dates.

## Required Sequence

1. Inventory every selected file and registration, verify a separate backup, and test restoration.
2. Evacuate the files to an explicitly selected staging directory outside Music's media folder. Downloads is not a required location.
3. Remove the inventoried Music registrations automatically, one persistent ID per call.
4. Confirm that all registrations and the GUI are empty, then quit Music and confirm termination.
5. While Music remains closed, apply the reviewed catalog, names, and optional file dates to working files.
6. Launch Music and add one album at a time in the selected order.
7. Verify files, registrations, order, and addition timestamps.

Use the existing four automatic orders, with ascending release date as the default. Playlists, ratings, play counts, and other library-only history are not restored. This workflow supports local files without cloud library synchronization. It must not change synchronization settings automatically.

Every track must have exactly the same `date added`, at the precision exposed by Music. Calendar-day equality or a visually grouped date is insufficient. The Recently Added display must also reflect the intended album sequence. These are separate gates. If the public interface cannot satisfy both together with album-by-album addition, stop the rebuilding work and the dependent stable release for a maintainer decision. Do not edit Music's database, change the system clock, or silently weaken the gate.

## Preservation and Recovery

Before registration removal, verify the bytes, relative paths, sizes, creation dates, and modification dates of the original files against a backup on a separate storage medium. A hard link is not a backup. Test restoration, then disconnect the backup medium. Insufficient capacity, missing files, unsupported registrations, ambiguous synchronization state, or an incomplete backup prevents removal.

Cross-volume evacuation retains its source until the replacement has been verified. Catalog edits affect working files only. Neither the backup nor recovery records are automatically deleted. These controls isolate a verified original from program and Music operations; they do not promise immunity to hardware failure or physical loss.

Remove only the persistent IDs captured in the verified plan. Stop if the inventory changes or an unexpected registration appears. An interrupted removal must not expand its scope. Recovery records distinguish evacuation, removal, confirmed termination, edits, and addition. Resuming addition must recheck the timestamp gate; successful file recovery alone does not establish a successful rebuild.

## Milestones and Gates

| Milestone | Scope | Completion Gate | Mac Requirement |
| --- | --- | --- | --- |
| M10 | Measure automatic removal, evacuation preservation, empty GUI, termination, editing, and ordered readdition | Both small and practical-scale synthetic runs satisfy every gate, including exact timestamp equality and GUI order | Separate macOS test user; stop for maintainer operation |
| M11 / 0.2.0 | Backup verification, inventory, evacuation plans, and strict catalog export | Complete inventory, tested restoration, and refusal before unsafe changes or unrepresentable catalog values | Portable logic on Linux; dates, storage, and restoration on macOS |
| M12 / 0.3.0 | Implement the qualified staged rebuilding workflow | Separate-user end-to-end success, preserved originals, exactly one registration per file, correct order and dates | Separate macOS test user |
| M13 / 0.4.0 | Interruptions, resumption, and recovery | Power/process interruption simulations, capacity failures, permission failures, disconnected volumes, and concurrent edits cannot cause an unverified source to be discarded | CI plus macOS and separate-user Music checks |
| M14 / 0.9.0 | Freeze features; qualify scale, compatibility, distribution, and documentation | Supported environments have evidence; no unresolved data-loss, incorrect-removal, or recovery defect | macOS; private copies only with separate authorization |
| M15 / 1.0.0 | Freeze compatibility policy and publish reviewed packages | Final approval, artifact audit, successful CI, and public installation checks | macOS verification and maintainer publication approval |

Retain Apple silicon distribution. A macOS deployment target is not runtime qualification; qualify the stated minimum supported OS or revise the support declaration and package requirements before 1.0.0.

## Command and Compatibility Boundaries

The planned interface is `rebuild prepare`, `rebuild stage`, `rebuild clear`, `rebuild apply`, `rebuild add`, and `rebuild status`. Preparation inventories files and registrations, verifies backups, and records the plan. Staging evacuates files. Clearing removes only planned registrations and quits after emptiness is established. Application edits working files while Music is closed. Addition verifies the resulting library. Status reports completed stages, failures, and the next required action.

Mutating stages require `--dry-run`, a complete preview, and post-operation verification. Plan changes require revalidation. Ordinary `add` retains its duplicate refusal and never removes registrations. Keep domain logic portable and platform operations in macOS targets; add no runtime package or external-tool dependency.

Retain `ilibrary-catalog-1`. Add `export --strict` before relying on an export as a complete rebuild inventory: missing tracks, numbering gaps, repeated numbers, and unrepresentable dates must prevent strict success. Do not invent months or days or silently close numbering gaps. Use a separate versioned recovery record rather than adding machine-specific paths and Music IDs to the public catalog format.

## Deferred Work

Network metadata candidates, multidisc flattening, cloud-synchronized rebuilding, and restoration of library-only history are outside 1.0.0. Developer ID signing and notarization are also deferred under the maintainer's no-additional-cost decision: Apple's [Developer Program](https://developer.apple.com/programs/) normally requires annual paid membership for [Developer ID](https://developer.apple.com/developer-id/). Preserve the distinction between existing ad hoc signing and Developer ID signing or notarization.

## Delivery and Handoff

Use milestone branches, atomic Conventional Commits, supported attribution trailers, and pull requests. Update Current Status at each checkpoint. Preserve historical reports. Before each approved push, present actual-file previews, section summaries, and Japanese translations. Future tags, releases, registry publication, and personal-library changes require explicit authorization; the 0.1.0 approvals do not extend to new releases.

M10 preparation does not implement `rebuild` or qualify it. The [M10 procedure](rebuild-feasibility-validation.md) describes the limited synthetic experiment and the remaining maintainer actions.

## Recommended Models and Effort

For M10 and the destructive-operation and recovery work in M12–M13, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex, following the existing M5 rationale. Use high for documentation and distribution checkpoints. Do not use ultra.
