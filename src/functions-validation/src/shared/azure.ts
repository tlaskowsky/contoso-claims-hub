// Identity-based clients (user-assigned managed identity via AZURE_CLIENT_ID).
import { DefaultAzureCredential } from '@azure/identity';
import { CosmosClient, Container } from '@azure/cosmos';

export const credential = new DefaultAzureCredential();

let claims: Container | undefined;
export function claimsContainer(): Container {
  if (!claims) {
    const endpoint = process.env.COSMOS_ENDPOINT;
    const database = process.env.COSMOS_DATABASE;
    const container = process.env.COSMOS_CONTAINER;
    if (!endpoint || !database || !container) throw new Error('Cosmos DB app settings are missing');
    claims = new CosmosClient({ endpoint, aadCredentials: credential }).database(database).container(container);
  }
  return claims;
}
