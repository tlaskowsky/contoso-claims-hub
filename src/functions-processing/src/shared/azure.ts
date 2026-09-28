// Identity-based clients (user-assigned managed identity via AZURE_CLIENT_ID).
import { DefaultAzureCredential } from '@azure/identity';
import { CosmosClient, Container, PatchOperation, PatchOperationType } from '@azure/cosmos';
import { AppConfigurationClient } from '@azure/app-configuration';

export const credential = new DefaultAzureCredential();

export interface ClaimDocument {
  fileName: string;
  status: string;
}

export interface Claim {
  claimId: string;
  customerId: string;
  policyNumber: string;
  claimType: string;
  amount: number;
  description: string;
  status: string;
  documents: Record<string, ClaimDocument>;
}

let claims: Container | undefined;
function claimsContainer(): Container {
  if (!claims) {
    const endpoint = process.env.COSMOS_ENDPOINT;
    const database = process.env.COSMOS_DATABASE;
    const container = process.env.COSMOS_CONTAINER;
    if (!endpoint || !database || !container) throw new Error('Cosmos DB app settings are missing');
    claims = new CosmosClient({ endpoint, aadCredentials: credential }).database(database).container(container);
  }
  return claims;
}

export async function getClaim(claimId: string): Promise<Claim | undefined> {
  const { resource } = await claimsContainer().item(claimId, claimId).read<Claim>();
  return resource;
}

/** Set fields on a claim and append one history entry. */
export async function updateClaim(claimId: string, fields: Record<string, unknown>, historyNote: string): Promise<void> {
  const now = new Date().toISOString();
  const ops: PatchOperation[] = Object.entries(fields).map(([key, value]) => ({ op: PatchOperationType.set, path: `/${key}`, value }));
  ops.push({ op: PatchOperationType.set, path: '/updatedAt', value: now });
  ops.push({ op: PatchOperationType.add, path: '/history/-', value: { at: now, status: (fields.status as string) ?? '', note: historyNote } });
  await claimsContainer().item(claimId, claimId).patch(ops);
}

let appConfig: AppConfigurationClient | undefined;
function appConfigClient(): AppConfigurationClient {
  if (!appConfig) {
    const endpoint = process.env.APPCONFIG_ENDPOINT;
    if (!endpoint) throw new Error('APPCONFIG_ENDPOINT app setting is missing');
    appConfig = new AppConfigurationClient(endpoint, credential);
  }
  return appConfig;
}

/** Read an App Configuration value; returns the fallback if the key does not exist. */
export async function getSetting(key: string, fallback: string): Promise<string> {
  try {
    const result = await appConfigClient().getConfigurationSetting({ key });
    return result.value ?? fallback;
  } catch (err) {
    if ((err as { statusCode?: number }).statusCode === 404) return fallback;
    throw err;
  }
}

/** Read an App Configuration feature flag; missing flag = disabled. */
export async function isFeatureEnabled(name: string): Promise<boolean> {
  const raw = await getSetting(`.appconfig.featureflag/${name}`, '');
  if (!raw) return false;
  try {
    return (JSON.parse(raw) as { enabled?: boolean }).enabled === true;
  } catch {
    return false;
  }
}
