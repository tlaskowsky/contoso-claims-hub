// Event Grid (BlobCreated) -> validate the uploaded document -> record the
// result in Cosmos DB -> on success, send a ClaimReadyForProcessing command
// to the Service Bus queue (identity-based). Until Service Bus exists (Lab 2.2),
// validated claims simply wait in DocumentsValidated.
import { app, EventGridEvent, InvocationContext } from '@azure/functions';
import { ServiceBusClient, ServiceBusSender } from '@azure/service-bus';
import { BlobClient } from '@azure/storage-blob';
import { PatchOperationType } from '@azure/cosmos';
import { claimsContainer, credential } from '../shared/azure';

const QUEUE_NAME = 'claims-processing';
let sender: ServiceBusSender | undefined;
function processingQueue(): ServiceBusSender | undefined {
  const namespace = process.env.ServiceBusConnection__fullyQualifiedNamespace;
  if (!namespace) return undefined; // Service Bus is added in Lab 2.2
  if (!sender) sender = new ServiceBusClient(namespace, credential).createSender(QUEUE_NAME);
  return sender;
}

// Allowed content types and the "magic bytes" each file must start with.
const SIGNATURES: Record<string, number[]> = {
  'application/pdf': [0x25, 0x50, 0x44, 0x46], // %PDF
  'image/png': [0x89, 0x50, 0x4e, 0x47],
  'image/jpeg': [0xff, 0xd8, 0xff],
};
const MAX_BYTES = 5 * 1024 * 1024;

// Only claims in these states move to DocumentsValidated / DocumentRejected.
// A later upload must not pull a claim back from Processing or PendingApproval.
const PRE_PROCESSING_STATES = "('Submitted', 'DocumentsValidated', 'DocumentRejected')";

export async function validateDocument(event: EventGridEvent, context: InvocationContext): Promise<void> {
  const data = event.data as { url?: string } | undefined;
  if (!data?.url) {
    context.warn(`Event ${event.id} has no blob URL; ignoring`);
    return;
  }

  // Blob path convention: claim-documents/{claimId}/{fileName}
  const segments = decodeURIComponent(new URL(data.url).pathname).split('/').filter(Boolean);
  if (segments.length < 3) {
    context.warn(`Unexpected blob path ${data.url}; ignoring`);
    return;
  }
  const claimId = segments[1];
  const fileName = segments.slice(2).join('/');
  const docKey = fileName.replace(/[^A-Za-z0-9_-]/g, '_');
  context.log(`Validating document ${fileName} for claim ${claimId}`);

  const blob = new BlobClient(data.url, credential);
  const props = await blob.getProperties();
  const size = props.contentLength ?? 0;
  const contentType = (props.contentType ?? '').toLowerCase();

  const problems: string[] = [];
  if (size === 0) problems.push('file is empty');
  if (size > MAX_BYTES) problems.push(`file is larger than ${MAX_BYTES / 1024 / 1024} MB`);
  const signature = SIGNATURES[contentType];
  if (!signature) {
    problems.push(`content type '${contentType}' is not allowed`);
  } else if (size > 0) {
    const header = await blob.downloadToBuffer(0, signature.length);
    if (!signature.every((byte, i) => header[i] === byte)) problems.push('file content does not match its declared content type');
  }

  const valid = problems.length === 0;
  const now = new Date().toISOString();
  const item = claimsContainer().item(claimId, claimId);

  try {
    await item.patch([
      { op: PatchOperationType.set, path: `/documents/${docKey}/status`, value: valid ? 'Validated' : 'Rejected' },
      { op: PatchOperationType.set, path: `/documents/${docKey}/validation`, value: { validatedAt: now, sizeBytes: size, problems } },
      {
        op: PatchOperationType.add,
        path: '/history/-',
        value: { at: now, status: valid ? 'DocumentValidated' : 'DocumentRejected', note: valid ? `${fileName} passed validation` : `${fileName}: ${problems.join('; ')}` },
      },
      { op: PatchOperationType.set, path: '/updatedAt', value: now },
    ]);
  } catch (err) {
    const code = (err as { code?: number }).code;
    if (code === 404 || code === 400) {
      context.warn(`Claim ${claimId} or its document record ${docKey} was not found; ignoring`);
      return;
    }
    throw err; // transient: let Event Grid retry
  }

  // Claim-level status, only while the claim is still pre-processing.
  try {
    await item.patch({
      condition: `FROM c WHERE c.status IN ${PRE_PROCESSING_STATES}`,
      operations: [{ op: PatchOperationType.set, path: '/status', value: valid ? 'DocumentsValidated' : 'DocumentRejected' }],
    });
  } catch (err) {
    if ((err as { code?: number }).code !== 412) throw err;
    context.log(`Claim ${claimId} is already past document validation; status unchanged`);
  }

  if (valid) {
    const queue = processingQueue();
    if (queue) {
      await queue.sendMessages({
        body: { type: 'ClaimReadyForProcessing', claimId, documentName: fileName, validatedAt: now },
        contentType: 'application/json',
        subject: 'ClaimReadyForProcessing',
      });
      context.log(`Claim ${claimId}: ClaimReadyForProcessing sent to ${QUEUE_NAME}`);
    } else {
      context.log(`Claim ${claimId}: validated; Service Bus not configured yet, so processing waits for Lab 2.2`);
    }
  } else {
    context.warn(`Claim ${claimId}: document ${fileName} rejected (${problems.join('; ')})`);
  }
}

app.eventGrid('validateDocument', {
  handler: validateDocument,
});
