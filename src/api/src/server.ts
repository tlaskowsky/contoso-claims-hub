// Contoso Claims Hub - Claims Intake API
import './telemetry'; // keep first
import express, { NextFunction, Request, Response } from 'express';
import { randomBytes } from 'crypto';
import { PatchOperationType } from '@azure/cosmos';
import { trace } from '@opentelemetry/api';
import swaggerUi from 'swagger-ui-express';
import { openApiSpec } from './openapi';
import { claimsContainer, documentsContainer, getSetting, secretClient } from './azure';

const CLAIM_TYPES = ['auto', 'home', 'health', 'commercial'] as const;
type ClaimType = (typeof CLAIM_TYPES)[number];

interface DocumentRecord {
  fileName: string;
  blobPath: string;
  contentType: string;
  sizeBytes: number;
  status: 'Uploaded' | 'Validated' | 'Rejected';
  uploadedAt: string;
}

interface Claim {
  id: string;
  claimId: string; // partition key
  customerId: string;
  policyNumber: string;
  claimType: ClaimType;
  amount: number;
  description: string;
  status: string;
  documents: Record<string, DocumentRecord>;
  history: { at: string; status: string; note: string }[];
  createdAt: string;
  updatedAt: string;
}

const app = express();
app.use(express.json({ limit: '100kb' }));

// Name request telemetry by route ("GET /claims/:claimId") instead of just the
// HTTP method, so Application Insights shows one row per endpoint.
function nameSpan(req: Request): void {
  const span = trace.getActiveSpan();
  const route = req.route?.path as string | undefined;
  if (span && route) {
    span.setAttribute('http.route', route);
    span.updateName(`${req.method} ${route}`);
  }
}

const asyncRoute =
  (fn: (req: Request, res: Response) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction) => {
    nameSpan(req);
    fn(req, res).catch(next);
  };

function newClaimId(): string {
  return `CLM-${Date.now().toString(36).toUpperCase()}-${randomBytes(2).toString('hex').toUpperCase()}`;
}

function documentKey(fileName: string): string {
  return fileName.replace(/[^A-Za-z0-9_-]/g, '_');
}

function publicView(claim: Claim) {
  // Return every field except Cosmos DB system properties (_rid, _self, _etag, _ts, ...).
  return Object.fromEntries(Object.entries(claim).filter(([key]) => !key.startsWith('_')));
}

// --- Root, health and platform probes -----------------------------------------
// App Service "Always On" pings "/" and the container warm-up probe requests
// /robots933456.txt. Answer both so they don't show up as failed requests.
app.get('/', (req, res) => {
  nameSpan(req);
  res.json({ service: 'Contoso Claims Hub - Claims Intake API', status: 'ok', docs: '/docs' });
});
app.get('/robots933456.txt', (req, res) => {
  nameSpan(req);
  res.type('text/plain').send('');
});

// --- API documentation ---------------------------------------------------------
// OpenAPI description + Swagger UI. In production you would protect or disable
// these; here they give learners a browser view of the API.
app.get('/openapi.json', (req, res) => {
  nameSpan(req);
  res.json(openApiSpec);
});
app.use(
  '/docs',
  (_req: Request, _res: Response, next: NextFunction) => {
    trace.getActiveSpan()?.updateName('GET /docs');
    next();
  },
  swaggerUi.serve,
  swaggerUi.setup(openApiSpec, { customSiteTitle: 'Contoso Claims Hub API' }),
);

app.get('/health', (req, res) => {
  nameSpan(req);
  res.json({ status: 'ok' });
});

// Proves identity-based access to every dependency (never returns secret values).
app.get(
  '/health/dependencies',
  asyncRoute(async (_req, res) => {
    const check = async (name: string, fn: () => Promise<string>) => {
      try {
        return { name, ok: true, detail: await fn() };
      } catch (err) {
        return { name, ok: false, detail: (err as Error).message };
      }
    };
    const checks = await Promise.all([
      check('cosmosDb', async () => {
        await claimsContainer().read();
        return 'claims container reachable';
      }),
      check('keyVault', async () => {
        const secret = await secretClient().getSecret('PolicyAdminApiKey');
        return `secret PolicyAdminApiKey present (${secret.value?.length ?? 0} characters)`;
      }),
      check('appConfiguration', async () => `ClaimsHub:MaxClaimAmount = ${await getSetting('ClaimsHub:MaxClaimAmount', '(not set)')}`),
      check('blobStorage', async () => ((await documentsContainer().exists()) ? 'documents container reachable' : 'documents container missing')),
    ]);
    const ok = checks.every((c) => c.ok);
    res.status(ok ? 200 : 503).json({ ok, checks });
  }),
);

// --- Claims ------------------------------------------------------------------
app.post(
  '/claims',
  asyncRoute(async (req, res) => {
    const { customerId, policyNumber, claimType, amount, description } = req.body ?? {};
    const errors: string[] = [];
    if (typeof customerId !== 'string' || !customerId.trim()) errors.push('customerId is required');
    if (typeof policyNumber !== 'string' || !/^POL-[A-Z0-9-]+$/.test(policyNumber)) errors.push('policyNumber must look like POL-XXXX');
    if (!CLAIM_TYPES.includes(claimType)) errors.push(`claimType must be one of: ${CLAIM_TYPES.join(', ')}`);
    if (typeof amount !== 'number' || !(amount > 0)) errors.push('amount must be a positive number');
    if (typeof description !== 'string' || description.length > 2000) errors.push('description is required (max 2000 characters)');
    if (errors.length) return res.status(400).json({ errors });

    const maxAmount = Number(await getSetting('ClaimsHub:MaxClaimAmount', '250000'));
    if (amount > maxAmount) {
      return res.status(422).json({ errors: [`amount exceeds the maximum claim amount of ${maxAmount} (App Configuration: ClaimsHub:MaxClaimAmount)`] });
    }

    const now = new Date().toISOString();
    const claimId = newClaimId();
    const claim: Claim = {
      id: claimId,
      claimId,
      customerId,
      policyNumber,
      claimType,
      amount,
      description,
      status: 'Submitted',
      documents: {},
      history: [{ at: now, status: 'Submitted', note: 'Claim received by intake API' }],
      createdAt: now,
      updatedAt: now,
    };
    await claimsContainer().items.create(claim);
    console.log(`Claim ${claimId} created (${claimType}, ${amount})`);
    res.status(201).location(`/claims/${claimId}`).json(publicView(claim));
  }),
);

app.get(
  '/claims/:claimId',
  asyncRoute(async (req, res) => {
    const { claimId } = req.params;
    const { resource } = await claimsContainer().item(claimId, claimId).read<Claim>();
    if (!resource) return res.status(404).json({ error: `Claim ${claimId} not found` });
    res.json(publicView(resource));
  }),
);

// Upload a supporting document. Send the raw file as the request body:
//   curl --data-binary @estimate.pdf -H "Content-Type: application/pdf" \
//        "$API/claims/$ID/documents?fileName=estimate.pdf"
app.post(
  '/claims/:claimId/documents',
  express.raw({ type: () => true, limit: '10mb' }),
  asyncRoute(async (req, res) => {
    const { claimId } = req.params;
    const fileName = String(req.query.fileName ?? '').trim();
    const contentType = String(req.headers['content-type'] ?? 'application/octet-stream').split(';')[0].trim().toLowerCase();
    const body = req.body as Buffer;

    if (!fileName || !/^[A-Za-z0-9._-]{1,100}$/.test(fileName)) {
      return res.status(400).json({ error: 'fileName query parameter is required (letters, digits, . _ - only)' });
    }
    if (!Buffer.isBuffer(body) || body.length === 0) return res.status(400).json({ error: 'Request body is empty' });

    const { resource: claim } = await claimsContainer().item(claimId, claimId).read<Claim>();
    if (!claim) return res.status(404).json({ error: `Claim ${claimId} not found` });

    const now = new Date().toISOString();
    const key = documentKey(fileName);
    const blobPath = `${claimId}/${fileName}`;
    const record: DocumentRecord = { fileName, blobPath, contentType, sizeBytes: body.length, status: 'Uploaded', uploadedAt: now };

    // Record the document first, then upload: the BlobCreated event that
    // follows must find this record when the validation Function runs.
    await claimsContainer()
      .item(claimId, claimId)
      .patch([
        { op: PatchOperationType.set, path: `/documents/${key}`, value: record },
        { op: PatchOperationType.add, path: '/history/-', value: { at: now, status: claim.status, note: `Document uploaded: ${fileName}` } },
        { op: PatchOperationType.set, path: '/updatedAt', value: now },
      ]);

    await documentsContainer()
      .getBlockBlobClient(blobPath)
      .uploadData(body, { blobHTTPHeaders: { blobContentType: contentType } });

    console.log(`Document ${fileName} uploaded for claim ${claimId}`);
    res.status(202).json({ claimId, document: record, message: 'Document accepted; validation runs asynchronously' });
  }),
);

// --- Errors ------------------------------------------------------------------
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error', detail: err.message });
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => console.log(`Claims Intake API listening on port ${port}`));
