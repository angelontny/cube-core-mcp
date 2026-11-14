// Cube Core Server Configuration
// Connects to Google BigQuery using Application Default Credentials (ADC) or workload identity.
// Core connection parameters (CUBEJS_DB_TYPE, CUBEJS_DB_BQ_PROJECT_ID, CUBEJS_DEV_MODE,
// CUBEJS_API_SECRET) are managed via container environment variables.
module.exports = {
  telemetry: false,
  compileContext: () => {
    const reportingProject = process.env.CUBEJS_REPORTING_PROJECT_ID || process.env.CUBEJS_DB_BQ_PROJECT_ID;
    const reportingDataset = process.env.CUBEJS_REPORTING_DATASET_ID || 'analytics';

    return {
      reportingProject,
      reportingDataset,
      sourceTable: (tableName) => {
        if (reportingProject) {
          return `\`${reportingProject}\`.${reportingDataset}.${tableName}`;
        }
        return `${reportingDataset}.${tableName}`;
      },
    };
  },
  orchestratorOptions: {
    queryCacheOptions: {
      refreshKeyRenewalThreshold: 300,
    },
  },
};
