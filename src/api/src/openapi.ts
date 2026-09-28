// OpenAPI 3.0 description of the Claims Intake API, served at /openapi.json
// and rendered by Swagger UI at /docs.
const claimExample = {
  customerId: 'CUST-10021',
  policyNumber: 'POL-AUTO-55821',
  claimType: 'auto',
  amount: 4200,
  description: 'Rear bumper and tail light damaged in a parking lot collision.',
};

const binaryFile = { schema: { type: 'string', format: 'binary' } };

export const openApiSpec = {
  openapi: '3.0.3',
  info: {
    title: 'Contoso Claims Hub — Claims Intake API',
    version: '1.0.0',
    description:
      'Submit insurance claims, upload supporting documents, and follow each claim through validation, ' +
      'processing and approval.\n\n' +
      '**Typical flow:** `POST /claims` → copy the `claimId` → `POST /claims/{claimId}/documents` (choose the ' +
      'file\'s content type, e.g. `application/pdf`) → poll `GET /claims/{claimId}` and watch `status` change.',
  },
  servers: [{ url: '/' }],
  tags: [
    { name: 'Claims', description: 'Submit and inspect claims' },
    { name: 'Documents', description: 'Upload supporting documents (validated asynchronously)' },
    { name: 'Health', description: 'Liveness and dependency checks' },
  ],
  paths: {
    '/claims': {
      post: {
        tags: ['Claims'],
        summary: 'Submit a new claim',
        requestBody: {
          required: true,
          content: { 'application/json': { schema: { $ref: '#/components/schemas/ClaimRequest' }, example: claimExample } },
        },
        responses: {
          '201': { description: 'Claim created', content: { 'application/json': { schema: { $ref: '#/components/schemas/Claim' } } } },
          '400': { description: 'Invalid request', content: { 'application/json': { schema: { $ref: '#/components/schemas/Errors' } } } },
          '422': { description: 'Amount exceeds the configured maximum (App Configuration: ClaimsHub:MaxClaimAmount)', content: { 'application/json': { schema: { $ref: '#/components/schemas/Errors' } } } },
        },
      },
    },
    '/claims/{claimId}': {
      get: {
        tags: ['Claims'],
        summary: 'Get a claim, including its status, documents, assessment and decision',
        parameters: [{ $ref: '#/components/parameters/ClaimId' }],
        responses: {
          '200': { description: 'The claim', content: { 'application/json': { schema: { $ref: '#/components/schemas/Claim' } } } },
          '404': { description: 'Claim not found', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
        },
      },
    },
    '/claims/{claimId}/documents': {
      post: {
        tags: ['Documents'],
        summary: 'Upload a supporting document',
        description:
          'Send the raw file as the request body and pick the matching content type. Accepted: PDF, PNG, JPEG ' +
          '(max 5 MB). Validation runs asynchronously; check the claim afterwards.',
        parameters: [
          { $ref: '#/components/parameters/ClaimId' },
          { name: 'fileName', in: 'query', required: true, schema: { type: 'string', example: 'repair-estimate.pdf' }, description: 'Letters, digits, . _ - only' },
        ],
        requestBody: {
          required: true,
          content: { 'application/pdf': binaryFile, 'image/png': binaryFile, 'image/jpeg': binaryFile },
        },
        responses: {
          '202': { description: 'Accepted; validation runs asynchronously' },
          '400': { description: 'Missing file name or empty body', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
          '404': { description: 'Claim not found', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
        },
      },
    },
    '/health': {
      get: { tags: ['Health'], summary: 'Liveness check', responses: { '200': { description: 'The API is running' } } },
    },
    '/health/dependencies': {
      get: {
        tags: ['Health'],
        summary: 'Check identity-based access to Cosmos DB, Key Vault, App Configuration and Blob Storage',
        responses: { '200': { description: 'All dependencies reachable' }, '503': { description: 'At least one dependency failed' } },
      },
    },
  },
  components: {
    parameters: {
      ClaimId: { name: 'claimId', in: 'path', required: true, schema: { type: 'string', example: 'CLM-MUKK8XLE-8B6B' } },
    },
    schemas: {
      ClaimRequest: {
        type: 'object',
        required: ['customerId', 'policyNumber', 'claimType', 'amount', 'description'],
        properties: {
          customerId: { type: 'string' },
          policyNumber: { type: 'string', pattern: '^POL-[A-Z0-9-]+$' },
          claimType: { type: 'string', enum: ['auto', 'home', 'health', 'commercial'] },
          amount: { type: 'number', minimum: 0, exclusiveMinimum: true },
          description: { type: 'string', maxLength: 2000 },
        },
      },
      Claim: {
        type: 'object',
        properties: {
          claimId: { type: 'string' },
          status: {
            type: 'string',
            enum: ['Submitted', 'DocumentsValidated', 'DocumentRejected', 'Processing', 'PendingApproval', 'AutoApproving', 'Approved', 'Rejected'],
          },
          customerId: { type: 'string' },
          policyNumber: { type: 'string' },
          claimType: { type: 'string' },
          amount: { type: 'number' },
          description: { type: 'string' },
          documents: { type: 'object', additionalProperties: true },
          assessment: { type: 'object', additionalProperties: true },
          decision: { type: 'object', additionalProperties: true },
          history: { type: 'array', items: { type: 'object', additionalProperties: true } },
          createdAt: { type: 'string', format: 'date-time' },
          updatedAt: { type: 'string', format: 'date-time' },
        },
      },
      Error: { type: 'object', properties: { error: { type: 'string' } } },
      Errors: { type: 'object', properties: { errors: { type: 'array', items: { type: 'string' } } } },
    },
  },
};
