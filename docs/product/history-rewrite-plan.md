# Repository history rewrite plan

Status: planned only. Do not run this procedure as part of an ordinary release,
rename commit, or pull request.

## Goal and limit

Rewrite Git objects reachable from the repository's approved branch set so the
former product and repository names do not remain in active source trees,
filenames, or commit messages. The replacement vocabulary is:

- Product display name: `Sekret`
- Dart application class: `Sekret`
- Dart package, platform-channel namespace, and Windows binary: `sekret`
- GitHub repository: `ricejy/sekret`
- Test temporary-path prefix: `sekret-`

This cannot guarantee absolute erasure. GitHub issue and pull-request metadata,
comments, review text, Actions logs and artifacts, caches, immutable external
links, forks, local clones, backups, and search-engine copies are outside a Git
object rewrite. The renamed repository may also retain a provider-managed redirect
from its former URL. Handle those surfaces separately, only where the provider
supports editing or deletion and the owner explicitly approves it.

## Compatibility exceptions during migration

Do not change the installed iPhone bundle identifiers as part of the source or
repository rename. Keeping the bundle identifier stable allows the renamed app to
update the existing installation and retain access to its current sandbox.

The existing database filename must also remain readable until a tested in-place
migration has completed. The migration should:

1. Open the existing database in the current application container.
2. Create an atomic backup or copy before changing its filename or schema.
3. Validate SQLite integrity, foreign keys, expected schema, and retained records.
4. Reopen the migrated database through the production startup path.
5. Retain a rollback path until the owner verifies the migrated installation.

These legacy identifiers are approved, explicit compatibility exceptions. Do not
obfuscate or assemble strings dynamically merely to produce a misleading zero-match
scan. Remove an exception only after the user's data has migrated successfully and
the compatibility path is no longer required.

## Preconditions

- Merge or pause all active work, including device benchmarks.
- Ensure the normal rename and feature pull requests are merged and CI is green.
- Record the exact remote branch and tag inventory.
- Ask collaborators to stop pushing and prepare to make fresh clones after cutover.
- Make an offline mirror backup of the repository and record its checksum.
- Install a reviewed, pinned version of `git-filter-repo` in an isolated tool
  environment. Do not use the dirty development checkout for the rewrite.
- Decide explicitly which remote branches and tags remain supported. Do not delete
  branches automatically merely because they are old.
- Review branch-protection requirements and obtain explicit approval for the
  temporary force-push window.

## Dry run in a disposable mirror

1. Create a fresh mirror clone of `ricejy/sekret` in a disposable directory.
2. Save the original ref inventory and object IDs outside the mirror.
3. Prepare a reviewed replacement map covering display-name, repository-name,
   package, class, channel, Windows-binary, and temporary-prefix variants.
4. Run the pinned history-rewrite tool against only the approved refs. Include
   commit and tag messages as well as file contents and paths.
5. Do not rewrite approved compatibility literals until their migrations have
   completed. Record each surviving match and its reason.
6. Produce an old-to-new commit mapping for maintainers. Keep it outside the
   rewritten repository if it contains the retired name.

No dry-run result is pushed.

## Verification

Verify the mirror before requesting cutover approval:

- Enumerate every rewritten branch and tag and compare it with the approved ref
  inventory.
- Search every reachable tree, path, commit message, and tag message for all name
  variants. Review declared compatibility exceptions individually.
- Confirm no unexpected large, private, generated, credential, model-weight, or
  personal-signing blobs became reachable.
- Check repository integrity with `git fsck`.
- Check out the rewritten default branch into a separate worktree and run static
  analysis, portable tests, native tests, and migration tests.
- Confirm that documentation and remote links use `ricejy/sekret`.
- Review the complete rewritten ref delta and the old-to-new mapping with the owner.

## Coordinated cutover

Cutover requires a separate, explicit approval. At that time:

1. Freeze writes and fetch the remote again.
2. Confirm every remote ref still matches the dry-run lease value. Abort on drift.
3. Re-run the rewrite from that exact fresh mirror if anything changed.
4. Temporarily adjust branch protection only as narrowly as required.
5. Force-push approved rewritten refs with lease protection. Never use an
   unconditional broad force push.
6. Restore branch protection immediately.
7. Verify the remote ref inventory and default branch after the push.
8. Tell collaborators to archive old clones and create fresh clones. Do not advise
   merging rewritten and pre-rewrite histories.

Branch deletion, Actions-log deletion, artifact deletion, cache invalidation,
release-asset removal, and GitHub issue or pull-request edits are separate actions.
None is authorized automatically by this plan.

## Aftercare

- Run CI against rewritten heads.
- Re-run the iPhone migration and data-integrity acceptance checks before removing
  any compatibility exception.
- Update open pull requests or recreate them from rewritten heads as needed.
- Audit GitHub-visible text and retained artifacts, then present each proposed
  deletion or edit for explicit approval.
- Keep the offline pre-rewrite backup access-controlled for the owner-defined
  retention period; destroying it is a separate destructive decision.
