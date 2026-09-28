// Service Bus (claims-processing) -> verify the claim's policy with the
// (simulated) policy administration system -> start the approval workflow.
//
// Failure path for the DLQ labs: policies numbered POL-LEGACY-* live in a
// legacy system that is "offline" while App Configuration key
// ClaimsHub:LegacyPolicySystemOnline is not "true". The function throws, the
// message is retried, and after maxDeliveryCount (3) it is dead-lettered.
// Fix the root cause (set the key to "true"), then replay the DLQ.
import { app, InvocationContext } from '@azure/functions';
import * as df from 'durable-functions';
import { getClaim, getSetting, updateClaim } from '../shared/azure';

interface ClaimReadyForProcessing {
  type?: string;
  claimId?: string;
  documentName?: string;
}

export async function processClaim(message: unknown, context: InvocationContext): Promise<void> {
  const command = (typeof message === 'string' ? JSON.parse(message) : message) as ClaimReadyForProcessing;
  if (!command?.claimId) throw new Error('Message has no claimId');
  const { claimId } = command;
  const deliveryCount = (context.triggerMetadata?.deliveryCount as number | undefined) ?? 1;
  context.log(`Processing claim ${claimId} (delivery attempt ${deliveryCount})`);

  const claim = await getClaim(claimId);
  if (!claim) throw new Error(`Claim ${claimId} not found`);

  if (claim.policyNumber.startsWith('POL-LEGACY')) {
    const online = (await getSetting('ClaimsHub:LegacyPolicySystemOnline', 'false')).toLowerCase() === 'true';
    if (!online) {
      throw new Error(`Claim ${claimId}: legacy policy system is offline; cannot verify policy ${claim.policyNumber}`);
    }
  }

  // Idempotency: commands are delivered at least once, and every validated
  // document produces a command. Start the workflow only once per claim.
  const client = df.getClient(context);
  let existing: df.DurableOrchestrationStatus | undefined;
  try {
    existing = await client.getStatus(claimId);
  } catch {
    existing = undefined;
  }
  const restartable = [df.OrchestrationRuntimeStatus.Failed, df.OrchestrationRuntimeStatus.Terminated];
  if (existing?.runtimeStatus && !restartable.includes(existing.runtimeStatus)) {
    context.log(`Claim ${claimId}: approval workflow already exists (${existing.runtimeStatus}); nothing to do`);
    return;
  }

  await updateClaim(claimId, { status: 'Processing' }, `Policy ${claim.policyNumber} verified; approval workflow starting`);
  await client.startNew('approvalOrchestrator', { instanceId: claimId, input: { claimId } });
  context.log(`Claim ${claimId}: approval workflow started`);
}

app.serviceBusQueue('processClaim', {
  connection: 'ServiceBusConnection',
  queueName: 'claims-processing',
  extraInputs: [df.input.durableClient()],
  handler: processClaim,
});
