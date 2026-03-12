Title: Fix TypeScript Compile Errors in Backend

Summary:
Several TypeScript compile errors were observed during CI builds. These errors are causing noisy logs and may hide real runtime issues. Fixing them improves code quality and prevents regressions.

Errors observed (examples):
- Property signature mismatches in cloud provider implementations (AwsProvider, AzureProvider, GcpProvider).
- Missing/incorrect Azure SDK exports usage.
- Type/interface mismatches for ProviderCredentials and operation results.

Reproduction:
1. cd backend
2. npm ci
3. npm run build

Suggested steps:
1. Run `npm run build` locally and capture full `tsc` output.
2. Fix type mismatches by aligning `ICloudProvider` and provider classes, updating return types to `OperationResult<{valid:boolean}>` where required.
3. Correct Azure SDK imports to use the supported client packages (verify package versions in `package.json`).
4. Add a TypeScript compile check to CI (already added in `cloudbuild.yaml`).
5. Add unit tests to cover provider validation flows.

Assignee: backend leads
Labels: bug, high-priority, typescript
