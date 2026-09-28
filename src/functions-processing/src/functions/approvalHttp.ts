// HTTP endpoints for the approval workflow (function-key protected).
//   POST /api/claims/{claimId}/approval   body: { approved, approver, comment? }
//   GET  /api/claims/{claimId}/workflow   -> orchestration status + history
import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import * as df from 'durable-functions';

async function getStatusOrUndefined(client: df.DurableClient, instanceId: string, withHistory = false) {
  try {
    return await client.getStatus(instanceId, { showHistory: withHistory, showHistoryOutput: withHistory, showInput: true });
  } catch {
    return undefined;
  }
}

app.http('submitApproval', {
  methods: ['POST'],
  route: 'claims/{claimId}/approval',
  authLevel: 'function',
  extraInputs: [df.input.durableClient()],
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const claimId = request.params.claimId;
    let body: { approved?: unknown; approver?: unknown; comment?: unknown };
    try {
      body = (await request.json()) as typeof body;
    } catch {
      return { status: 400, jsonBody: { error: 'Body must be JSON: { "approved": true|false, "approver": "name", "comment": "..." }' } };
    }
    if (typeof body.approved !== 'boolean' || typeof body.approver !== 'string' || !body.approver.trim()) {
      return { status: 400, jsonBody: { error: '"approved" (boolean) and "approver" (string) are required' } };
    }

    const client = df.getClient(context);
    const status = await getStatusOrUndefined(client, claimId);
    if (status?.runtimeStatus !== df.OrchestrationRuntimeStatus.Running) {
      return { status: 409, jsonBody: { error: `No running approval workflow for claim ${claimId}`, runtimeStatus: status?.runtimeStatus ?? 'NotFound' } };
    }

    await client.raiseEvent(claimId, 'ApprovalDecision', {
      approved: body.approved,
      approver: body.approver.trim(),
      comment: typeof body.comment === 'string' ? body.comment : '',
      decidedAt: new Date().toISOString(),
    });
    context.log(`Claim ${claimId}: ApprovalDecision raised by ${body.approver}`);
    return { status: 202, jsonBody: { claimId, message: 'Decision delivered to the approval workflow' } };
  },
});

app.http('getWorkflowStatus', {
  methods: ['GET'],
  route: 'claims/{claimId}/workflow',
  authLevel: 'function',
  extraInputs: [df.input.durableClient()],
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const claimId = request.params.claimId;
    const status = await getStatusOrUndefined(df.getClient(context), claimId, true);
    if (!status) return { status: 404, jsonBody: { error: `No approval workflow for claim ${claimId}` } };
    return { status: 200, jsonBody: status };
  },
});
