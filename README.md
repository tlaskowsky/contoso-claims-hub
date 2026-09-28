# Contoso Claims Hub — final solution

Reference implementation of the end-of-course state for a 3-day Azure
Solution Architect course. Instructor material — not learner-facing.

## Architecture

```
               ┌───────────────────────── VNet (Private Endpoints, private DNS) ─────────────────────────┐
 curl / client │                                                                                         │
      │        │   Key Vault      App Configuration      Cosmos DB (claims, /claimId)     Storage x2     │
      ▼        │       ▲                ▲                     ▲        ▲        ▲          ▲      ▲      │
 Claims Intake API ────┴────────────────┴─────────────────────┘        │        │          │      │      │
 (App Service) ──── uploads document ──────────────────────────────────┼────────┼──► claim-documents     │
               │                                                       │        │          │             │
               │        Event Grid (BlobCreated) ◄─────────────────────┼────────┼──────────┘             │
               │               │                                       │        │                        │
               │               ▼                                       │        │                        │
               │   validateDocument (Flex Function) ──────────────────►┘        │                        │
               │               │ ClaimReadyForProcessing                        │                        │
               └───────────────┼────────────────────────────────────────────────┼────────────────────────┘
                               ▼                                                │
                Service Bus queue: claims-processing (DLQ after 3 deliveries)   │
                  (Standard tier - public endpoint, Entra ID only)               │
                               │                                                │
                               ▼                                                │
               processClaim ──► approvalOrchestrator (Durable) ─────────────────┘
                                 fan-out: fraud | coverage | documentation
                                 wait: ApprovalDecision event (HTTP) or 72 h timeout

 Observability: Application Insights (Entra-only ingestion) + Log Analytics, 2 alerts
 Governance:    tag-inheritance policies + deny VMs/VMSS/AKS on the resource group
 Public by design (Entra ID only): Service Bus (Standard tier), App Configuration (ARM deploys key-values)
```

## Repository

| Path | Contents |
|---|---|
| `infra/main.bicep` | Subscription-scope entry point; each section is labelled with its lab |
| `infra/modules/` | One module per service |
| `infra/parameters/` | `dev` and `test` parameter files (Lab 3.3) |
| `src/api/` | Claims Intake API (Express, TypeScript) |
| `src/functions-validation/` | `validateDocument` — Event Grid trigger, Service Bus output |
| `src/functions-processing/` | `processClaim`, Durable `approvalOrchestrator` + activities, approval HTTP endpoints |
| `scripts/` | Deploy, test, App Configuration change, teardown |
| `tests/` | Sample claims (auto, home, health, commercial, low-value, legacy) and documents |
| `queries/` | KQL: trace one claim, DLQ accumulation, stage latency |

`LAB-BLANK(x.y)` comments mark candidate blanks for the learner start versions.
