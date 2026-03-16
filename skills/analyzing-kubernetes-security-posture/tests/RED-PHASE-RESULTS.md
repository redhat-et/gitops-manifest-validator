# RED Phase: Expected Failures Without Skill

## Scenario 1: Privilege Escalation Chain (01-privilege-escalation.yaml)

Without the skill, an LLM will typically:

- Flag `privileged: true` as a generic best-practice violation
- May note hostPath mount but NOT identify the attack path: container escape -> host FS access -> credential harvesting
- MISS the compound risk: privileged + hostPath "/" + docker.sock + hostNetwork + hostPID creates a full node takeover chain
- MISS the RBAC amplification: the ServiceAccount can read all secrets cluster-wide, so a compromised container can pivot to every namespace
- MISS that docker.sock access allows spawning new privileged containers on the host
- NOT articulate the blast radius: DaemonSet runs on ALL nodes, so one vulnerability = full cluster compromise

## Scenario 2: Defense-in-Depth Violation (02-defense-in-depth-violation.yaml)

Without the skill, an LLM will typically:

- Flag individual missing fields (no resource limits, no securityContext)
- MISS the layered failure: no single issue is critical alone, but the combination is exploitable
- NOT explain the lateral movement path: no NetworkPolicy + auto-mounted token + DB connection strings = attacker can reach K8s API AND database
- MISS that running as root + writable FS means attacker can replace binaries, install tools, establish persistence
- NOT identify the missing seccomp/AppArmor profile as enabling dangerous syscalls
- MISS that hardcoded service addresses in env vars reveal internal architecture to attacker

## Scenario 3: Secret Exposure (03-secret-exposure.yaml)

Without the skill, an LLM will typically:

- Note that passwords should not be in plain text (surface-level observation)
- MISS that secrets in args are visible in /proc/[pid]/cmdline and ps output on the node
- NOT explain the multiple exposure vectors: K8s API (kubectl describe), etcd storage, container env, process table, audit logs
- MISS that even well-secured containers (this one has good securityContext) are undermined by secret exposure
- NOT identify specific credential types (Stripe live key, JWT signing key, AES encryption key) and their blast radius
- MISS that the Stripe live key prefix `sk_live_` indicates a production payment key (PCI-DSS implications)
