// Azure clients. Every client authenticates with the app's user-assigned
// managed identity (DefaultAzureCredential reads AZURE_CLIENT_ID).
// No keys or connection strings anywhere.
import { DefaultAzureCredential } from '@azure/identity';
import { CosmosClient, Container } from '@azure/cosmos';
import { SecretClient } from '@azure/keyvault-secrets';
import { AppConfigurationClient } from '@azure/app-configuration';
import { BlobServiceClient, ContainerClient } from '@azure/storage-blob';

export const credential = new DefaultAzureCredential();

function setting(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing app setting: ${name}`);
  return value;
}

let claims: Container | undefined;
export function claimsContainer(): Container {
  if (!claims) {
    const client = new CosmosClient({ endpoint: setting('COSMOS_ENDPOINT'), aadCredentials: credential });
    claims = client.database(setting('COSMOS_DATABASE')).container(setting('COSMOS_CONTAINER'));
  }
  return claims;
}

let secrets: SecretClient | undefined;
export function secretClient(): SecretClient {
  if (!secrets) secrets = new SecretClient(setting('KEYVAULT_URI'), credential);
  return secrets;
}

let appConfig: AppConfigurationClient | undefined;
function appConfigClient(): AppConfigurationClient {
  if (!appConfig) appConfig = new AppConfigurationClient(setting('APPCONFIG_ENDPOINT'), credential);
  return appConfig;
}

let documents: ContainerClient | undefined;
export function documentsContainer(): ContainerClient {
  if (!documents) {
    const service = new BlobServiceClient(setting('DOCUMENTS_BLOB_ENDPOINT'), credential);
    documents = service.getContainerClient(setting('DOCUMENTS_CONTAINER'));
  }
  return documents;
}

// App Configuration values, cached for 30 seconds so a change in the portal
// takes effect quickly without a restart.
const cache = new Map<string, { value: string; expires: number }>();
export async function getSetting(key: string, fallback: string): Promise<string> {
  const hit = cache.get(key);
  if (hit && hit.expires > Date.now()) return hit.value;
  let value = fallback;
  try {
    const result = await appConfigClient().getConfigurationSetting({ key });
    value = result.value ?? fallback;
  } catch (err: unknown) {
    if ((err as { statusCode?: number }).statusCode !== 404) throw err;
  }
  cache.set(key, { value, expires: Date.now() + 30_000 });
  return value;
}
