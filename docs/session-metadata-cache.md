# Copilot session metadata cache

## Purpose

The Copilot launcher avoids rereading unchanged session metadata while preserving
the conversation choice of a fresh scan. The embedded Python selector in
`bin/agent` owns discovery, caching and ranking. No background service is needed.

This is a disposable metadata cache, not a session database or a cache of the
last winning session ID. It does not change other backends, authentication,
keychain behavior, or attachment to an existing tmux session.

## Lookup

1. Read the workspace's `.ca-retired-sessions` list.
2. Enumerate sorted, immediate, nonhidden directories in
   `~/.copilot/session-state`.
3. Load the cache and validate its format version, session root and entry shape.
   An absent, invalid or inaccessible cache is treated as empty.
4. Check each `workspace.yaml` file's device, inode, size, nanosecond modification
   time and nanosecond change time. Reuse cached fields only when all match.
5. Read new or changed files using eight parallel readers. Parse `cwd`, `id`,
   `updated_at` and `summary_count` for every workspace, not just the requested
   one, so another launch can reuse those records.
6. Apply the existing selection rules: exact workspace match, exclude retired
   IDs, prefer nonempty/nonzero `summary_count`, then greatest `updated_at`.
   Equal-ranked sessions retain the first sorted directory. With no eligible
   session, the launcher uses its deterministic UUID fallback.
7. Publish changed cache entries atomically. Deleted and inaccessible metadata
   files have no entry in the new cache.

Progress and reuse/read/skip counts go to stderr. The selector's stdout contains
only the chosen session ID.

## Concurrent writes and recovery

The selector checks file attributes before and after each changed-file read.
It retries an unstable read once. If the file keeps changing, it does not publish
the snapshot and uses the uncached selector for that invocation. Activity in
another workspace therefore does not become a new reason to block a launch.

Concurrent launchers write separate temporary files and atomically replace the
cache. No lock is needed: even if an older snapshot is published last, the next
lookup checks its entries against the current filesystem.

The directory scan is not a filesystem transaction. A session created after
enumeration or changed after its check can be seen on the next launch, as with
an uncached scan. The cache does not claim a globally atomic snapshot.

Cache files use mode 0600 and live at
`${XDG_CACHE_HOME:-$HOME/.cache}/remote-agent-stack/copilot-sessions-v1.json`.
The first lookup builds the cache; an unchanged snapshot needs no rewrite.
Cache publication failures are nonfatal. Unexpected session-metadata I/O errors
still fail lookup rather than being treated as an empty session list.

Delete only the named cache file to rebuild it. The cache contains no conversation
events, and rebuilding it never edits session metadata or retirement lists.

## Verification

Run the focused checks from the repository root:

```bash
python3 scripts/session-cache.test.py -v
bash scripts/agent.test.sh
```

They cover cold and warm lookups; creation, updates, replacement and deletion;
restored modification times; cross-workspace reuse; retirement changes; ranking
and ties; corrupt or unwritable caches; unstable reads; and an older concurrent
publisher finishing last.

Warm lookups still check every metadata file, so filesystem contention and session
count can affect latency. A future native session index could replace this cache
only if it supplies the complete, fresh metadata needed by the same selection
rules.
