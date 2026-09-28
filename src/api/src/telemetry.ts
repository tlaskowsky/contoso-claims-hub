// Must be imported before anything else so HTTP and Azure SDK calls are
// auto-instrumented. Telemetry is sent with the app's managed identity
// (Application Insights has local/key auth disabled).
import { useAzureMonitor } from '@azure/monitor-opentelemetry';
import { ManagedIdentityCredential } from '@azure/identity';

const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
const clientId = process.env.AZURE_CLIENT_ID;

if (connectionString) {
  useAzureMonitor({
    azureMonitorExporterOptions: {
      connectionString,
      credential: clientId ? new ManagedIdentityCredential({ clientId }) : new ManagedIdentityCredential(),
    },
  });
}
