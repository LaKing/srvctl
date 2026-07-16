# srvctl TODO

Prioritized from the read-only audit performed on 2026-07-16. Revalidate each item against a fixed commit before implementation because the working tree was changing during the audit.

## Current topology-migration review

- [x] **High — Pin `regenerate all-hosts` through its complete execution window.**
  - RESOLVED via child-side enforcement: `_regenerate_cluster_host` passes the
    plan generation to every child (`env SC_EXPECTED_CLUSTERS_SHA256=…` locally,
    an env prefix on the remote ssh command), and init.sh aborts 113 before any
    hook when the child's freshly verified generation differs. A flip in the
    probe→launch→child-init window is therefore caught by the child itself,
    regardless of when publication lands; the controller reports the host failed.
  - Tests: regenlib.test.sh "every child receives the plan generation" (real
    `_regenerate_cluster_host` through the run stub, both transports) and
    modules/srvctl/selftest/expected-generation.test.sh (real srvctl.sh init:
    mismatch → 113, non-hex ignored, absent unaffected, match proceeds). Both
    verified failing with the respective half of the fix removed.

- [x] **Medium — Prevent vncproxy from restart-looping when projections are absent or invalid.**
  - RESOLVED: `start.sh` exits 78 (EX_CONFIG) for the missing-projection and
    empty-`SC_HOST_IP` cases and `services/vncproxy.service` declares
    `RestartPreventExitStatus=78`; genuine proxy crashes still restart.
  - Operational note: the unit is hand-installed — deployed hosts need the updated
    unit copied to /etc/systemd/system plus `systemctl daemon-reload`.

- [x] **Low — Make the optional vncproxy watchdog honor an empty host address.**
  - RESOLVED: `vncproxy-restarter.sh` exits 0 with a SKIP message when the
    sourced projection lacks `SC_HOST_IP`, so the timer no longer probes nmap or
    issues futile `systemctl restart vncproxy` attempts once per minute.

## P0 — Release blockers

- [ ] Restrict `CMD` to a strict, documented basename grammar before any path construction or dispatch.
  - Reject path separators, `..`, absolute paths, control characters, and empty or ambiguous names.
  - Apply the same validation to normal execution, help, command indexing, and every fallback dispatch lane.
  - Add regression tests proving traversal cannot escape `commands/` or reach arbitrary `.sh` files.
  - Evidence: `srvctl.sh` command parsing and `commonlib.sh` dispatch paths.

- [ ] Prevent privileged processes from sourcing commands from a user's home directory.
  - Define whether user custom commands are allowed during unprivileged execution only, or remove the lane entirely.
  - When effective UID is 0, fail closed before reading or executing user-owned command files.
  - Cover direct dispatch and bare/help command discovery.
  - Add tests for sudo execution, ownership, permissions, symlinks, and replacement races.
  - Evidence: `init.sh` derives `SC_HOME` from `SUDO_USER`; `commonlib.sh` sources `$SC_HOME/srvctl-includes/$CMD.sh`.

- [ ] Stop sourcing the user-owned module cache as shell code.
  - Replace it with a non-executable, strictly parsed data format.
  - Store privileged cache state in a root-owned location with safe ownership and permissions.
  - Validate the complete cache contents rather than relying on a reproducible generation marker.
  - Use atomic, symlink-safe reads and writes.
  - Add hostile-cache tests for appended shell, substitutions, symlinks, ownership, modes, and concurrent replacement.
  - Evidence: module-cache loading in `commonlib.sh`.

- [ ] Redesign the generated sudo policy around an explicit command allowlist.
  - Remove `NOPASSWD: .../srvctl.sh *`.
  - Ensure authorization occurs before hooks, module caches, help metadata, or command files can execute.
  - Test the installed sudoers policy with ordinary managed-host users.
  - Re-audit all initialization and dispatch code reachable before authorization.
  - Evidence: `modules/usersonhost/hooks/update-install-host.sh`.

- [ ] Eliminate executable help metadata.
  - Parse help/index metadata as inert text or structured data.
  - Never execute metadata extracted from user-controlled files.
  - Test bare command listings and help requests under elevated execution.
  - Evidence: dynamic `## &&&` handling in `commonlib.sh`.

## P1 — Network and data-plane security

- [ ] Authenticate peer snapshots before using them to generate authoritative DNS.
  - Verify peer certificates against a dedicated trust root and validate peer identity.
  - Add an application-level signature or MAC if snapshots may traverse untrusted intermediaries.
  - Enforce response-size, timeout, content-type, freshness, and strict record-schema limits.
  - Bind cached snapshots to the authenticated peer and reject unsigned legacy cache data.
  - Add tampering, wrong-peer, expired-certificate, oversized-body, malformed-record, and cache-poisoning tests.
  - Evidence: `modules/named/lib/snapshots.js` and snapshot consumption in `modules/named/named.js`.

- [ ] Fix path traversal in the public PKI validation handler.
  - Parse and decode the request path exactly once.
  - Accept only the expected validation-token grammar.
  - Resolve the candidate path and verify containment beneath the intended document root.
  - Run the service as an unprivileged account and expose only the required directory.
  - Add encoded and unencoded traversal tests through the complete HAProxy-to-service route.
  - Evidence: `modules/datastore/apps/datastore-server.js`.

- [ ] Minimize and authenticate the public datastore snapshot endpoint.
  - Publish a DNS-specific projection rather than the full containers datastore.
  - Remove secrets and operational metadata from the public representation.
  - Add authentication, authorization, rate limits, and bounded responses where public access is unnecessary.

- [ ] Reassess the cluster-wide NFS trust model.
  - Remove `no_root_squash` where possible and narrow exports to specific hosts and required paths.
  - Document the accepted compromise boundary if unrestricted root-equivalent sharing remains intentional.
  - Add deployment checks that reject unexpectedly broad exports.
  - Evidence: `modules/nfs/libs/nfslib.sh`.

- [ ] Reduce private-CA blast radius.
  - Do not replicate CA private keys to every cluster host.
  - Separate root, intermediate, and leaf-key responsibilities.
  - Protect exported PKCS#12 material with an appropriate secret-delivery mechanism.
  - Define and test key rotation and host-compromise recovery.
  - Evidence: `modules/ca/libs/netlib.sh` and `modules/ca/libs/calib.sh`.

- [ ] Audit the static server's `Host`-derived document root.
  - Treat this as high priority anywhere port 1280 is reachable.
  - Validate the host grammar, canonicalize the path, enforce root containment, and drop privileges.
  - Verify firewall and HAProxy exposure in deployed environments.

## P1 — Test and release reliability

- [ ] Repair the sandbox integration harness.
  - Include the cluster configuration helper now required by `init.sh`, or make the fixture explicitly independent of cluster configuration.
  - Preserve and display stderr on failures.
  - Stop swallowing command failures with `|| true`.
  - Confirm that blank output can never satisfy or obscure a failed invocation.
  - Evidence: `modules/srvctl/selftest/sandbox/run-harness.sh`.

- [ ] Add a single top-level test entry point.
  - Run every first-party shell and Node test with deterministic ordering and a nonzero exit on any failure or unexpected skip.
  - Report test counts, skipped tests, and runtime prerequisites.

- [ ] Add continuous integration for supported environments.
  - Run Bash syntax checks, Node syntax checks, ShellCheck, unit tests, sandbox tests, and security regressions.
  - Pin or document the supported Bash, Node, Fedora, and systemd versions.

- [ ] Make the release/push workflow fail closed.
  - Propagate ShellCheck failures.
  - Require the top-level test suite before version bump, commit, or push.
  - Avoid staging unrelated working-tree changes automatically.

- [ ] Add integration coverage for privileged deployment behavior.
  - Exercise sudoers, systemd services, systemd-nspawn, firewalld, HAProxy, BIND, NFS, DNF, SSH, and multi-host failure cases in disposable environments.

- [ ] Expand tests beyond the currently covered modules.
  - Prioritize privilege boundaries, public listeners, file generation, remote inputs, and destructive lifecycle commands.

## P2 — Architecture and maintainability

- [ ] Define the sourced-shell API explicitly.
  - Document hook order, shared globals, dynamically scoped variables, exit codes, and dispatch precedence.
  - Namespace module functions and detect collisions during module loading.

- [ ] Make authorization guards enforce policy consistently.
  - Review `authorize`, `hs_only`, and `ve_only` for fail-open or no-op behavior.
  - Add negative tests showing forbidden commands stop before side effects.

- [ ] Route all datastore mutations through one locking and validation layer.
  - Remove or isolate legacy direct-write paths.
  - Pass validators from every caller.
  - Define transaction semantics for operations spanning multiple entity files.

- [ ] Establish one canonical topology source and documented generated projections.
  - Make ownership, location, publication, rollback, and retirement behavior unambiguous.
  - Add compatibility and migration tests for legacy topology files.

- [ ] Triage existing `FIXME(v4)` markers.
  - Convert actionable items into tracked work, close obsolete notes, and assign severity and ownership.

## P2 — Documentation and audit hygiene

- [ ] Update documentation that still describes v3 or obsolete campaign state.
  - Reconcile `README.md`, `CLAUDE.md`, and `update-campaign/` with the actual v4 runtime and current topology design.
  - Correct the claim that hostile-user sudo bypass is resolved.

- [ ] Create a security model document.
  - Enumerate ordinary users, root, containers, cluster peers, public clients, operators, and compromised hosts.
  - State which boundaries are enforced and which are accepted shared-trust assumptions.

- [ ] Keep future audits reproducible.
  - Record commit, staged diff, unstaged diff, generated configuration, installed runtime checksum, and deployment role.
  - Audit committed, staged, unstaged, and installed code separately when they differ.

## Completion gate

- [ ] All P0 items are fixed and covered by adversarial regression tests.
- [ ] No user-owned file can be parsed or executed by srvctl before authorization while effective UID is 0.
- [ ] All network-derived configuration is authenticated, bounded, schema-validated, and safely cached.
- [ ] The full test suite and static checks run from one command and fail reliably.
- [ ] A clean deployment test passes on every supported host role.
