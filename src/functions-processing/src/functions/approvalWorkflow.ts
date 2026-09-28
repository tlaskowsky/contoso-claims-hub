// Durable Functions approval workflow for one claim (instance ID = claimId).
//
//   fan-out:  fraudCheck | coverageCheck | documentationCheck   (parallel)
//   fan-in:   recordAssessment
//   then:     auto-approve (feature flag) OR wait for a human ApprovalDecision
//             event, with a 72-hour timeout
//   finally:  recordDecision
import { InvocationContext } from '@azure/functions';
import * as df from 'durable-functions';
import { getClaim, isFeatureEnabled, updateClaim } from '../shared/azure';

export interface CheckResult {
  check: 'fraud' | 'coverage' | 'documentation';
  passed: boolean;
  detail: string;
}

export interface ApprovalDecision {
  approved: boolean;
  approver: string;
  comment?: string;
  decidedAt?: string;
}

const APPROVAL_TIMEOUT_HOURS = 72;
const AUTO_APPROVE_LIMIT = 1000;
const COVERAGE_LIMITS: Record<string, number> = { auto: 50_000, home: 250_000, health: 100_000, commercial: 500_000 };

// ---------------------------------------------------------------- orchestrator
const approvalOrchestrator: df.OrchestrationHandler = function* (context: df.OrchestrationContext) {
  const { claimId } = context.df.getInput() as { claimId: string };

  const results: CheckResult[] = yield context.df.Task.all([
    context.df.callActivity('fraudCheck', claimId),
    context.df.callActivity('coverageCheck', claimId),
    context.df.callActivity('documentationCheck', claimId),
  ]);
  const allPassed = results.every((r) => r.passed);

  const autoApprove: boolean = yield context.df.callActivity('checkAutoApproval', { claimId, allPassed });
  yield context.df.callActivity('recordAssessment', { claimId, results, autoApprove });

  let decision: ApprovalDecision;
  if (autoApprove) {
    decision = { approved: true, approver: 'system:auto-approval', comment: `Under $${AUTO_APPROVE_LIMIT} and all checks passed (feature flag AutoApproveLowValue)` };
  } else {
    const deadline = new Date(context.df.currentUtcDateTime.getTime() + APPROVAL_TIMEOUT_HOURS * 3_600_000);
    const timeout = context.df.createTimer(deadline);
    const humanDecision = context.df.waitForExternalEvent('ApprovalDecision');
    const winner: df.Task = yield context.df.Task.any([humanDecision, timeout]);
    if (winner === humanDecision) {
      timeout.cancel();
      decision = humanDecision.result as ApprovalDecision;
    } else {
      decision = { approved: false, approver: 'system:timeout', comment: `No decision within ${APPROVAL_TIMEOUT_HOURS} hours` };
    }
  }

  yield context.df.callActivity('recordDecision', { claimId, decision });
  return decision;
};
df.app.orchestration('approvalOrchestrator', approvalOrchestrator);

// ------------------------------------------------------------------ activities
df.app.activity('fraudCheck', {
  handler: async (claimId: unknown, context: InvocationContext): Promise<CheckResult> => {
    const claim = await getClaim(claimId as string);
    if (!claim) throw new Error(`Claim ${claimId} not found`);
    let score = 10;
    if (claim.amount > 25_000) score += 30;
    if (/cash|urgent|wire/i.test(claim.description)) score += 25;
    if (claim.claimType === 'commercial') score += 10;
    context.log(`Claim ${claimId}: fraud score ${score}`);
    return { check: 'fraud', passed: score < 50, detail: `risk score ${score}/100` };
  },
});

df.app.activity('coverageCheck', {
  handler: async (claimId: unknown, context: InvocationContext): Promise<CheckResult> => {
    const claim = await getClaim(claimId as string);
    if (!claim) throw new Error(`Claim ${claimId} not found`);
    const limit = COVERAGE_LIMITS[claim.claimType] ?? 0;
    context.log(`Claim ${claimId}: coverage limit ${limit}, amount ${claim.amount}`);
    return { check: 'coverage', passed: claim.amount <= limit, detail: `amount ${claim.amount} vs ${claim.claimType} limit ${limit}` };
  },
});

df.app.activity('documentationCheck', {
  handler: async (claimId: unknown, context: InvocationContext): Promise<CheckResult> => {
    const claim = await getClaim(claimId as string);
    if (!claim) throw new Error(`Claim ${claimId} not found`);
    const docs = Object.values(claim.documents ?? {});
    const validated = docs.filter((d) => d.status === 'Validated').length;
    context.log(`Claim ${claimId}: ${validated}/${docs.length} documents validated`);
    return { check: 'documentation', passed: validated > 0, detail: `${validated} of ${docs.length} documents validated` };
  },
});

df.app.activity('checkAutoApproval', {
  handler: async (input: unknown): Promise<boolean> => {
    const { claimId, allPassed } = input as { claimId: string; allPassed: boolean };
    if (!allPassed) return false;
    const claim = await getClaim(claimId);
    if (!claim || claim.amount >= AUTO_APPROVE_LIMIT) return false;
    return isFeatureEnabled('AutoApproveLowValue');
  },
});

df.app.activity('recordAssessment', {
  handler: async (input: unknown): Promise<void> => {
    const { claimId, results, autoApprove } = input as { claimId: string; results: CheckResult[]; autoApprove: boolean };
    const summary = results.map((r) => `${r.check}: ${r.passed ? 'pass' : 'FAIL'}`).join(', ');
    await updateClaim(
      claimId,
      { status: autoApprove ? 'AutoApproving' : 'PendingApproval', assessment: { results, assessedAt: new Date().toISOString() } },
      autoApprove ? `Automated checks passed (${summary}); auto-approving` : `Automated checks complete (${summary}); awaiting approver`,
    );
  },
});

df.app.activity('recordDecision', {
  handler: async (input: unknown): Promise<void> => {
    const { claimId, decision } = input as { claimId: string; decision: ApprovalDecision };
    const status = decision.approved ? 'Approved' : 'Rejected';
    await updateClaim(claimId, { status, decision }, `${status} by ${decision.approver}${decision.comment ? `: ${decision.comment}` : ''}`);
  },
});
