// Cube Core Server Configuration
// Connects to Google BigQuery using Application Default Credentials (ADC) or workload identity.
// Core connection parameters (CUBEJS_DB_TYPE, CUBEJS_DB_BQ_PROJECT_ID, CUBEJS_DEV_MODE,
// CUBEJS_API_SECRET) are managed via container environment variables.
module.exports = {
  telemetry: false,
  orchestratorOptions: {
    queryCacheOptions: {
      refreshKeyRenewalThreshold: 300,
    },
  },
};
