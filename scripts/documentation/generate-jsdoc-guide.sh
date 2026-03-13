#!/bin/bash
# Script to generate and update JSDoc documentation for all backend functions
# Scans TypeScript files and generates comprehensive documentation templates

set -e

BACKEND_DIR="backend/src"
DOCS_OUTPUT_DIR="docs/api"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "${DOCS_OUTPUT_DIR}"

echo "🔍 Scanning backend for functions..."
echo "Output directory: ${DOCS_OUTPUT_DIR}"
echo ""

# Function to extract function signatures from TypeScript
extract_functions() {
  local file=$1
  local module_name=$(basename "$file" .ts)
  
  echo "Analyzing: ${file}"
  
  # Extract exported functions and classes
  grep -E "^export (async )?function |^export class " "$file" | while read -r line; do
    echo "  - Found: $line"
  done
}

# Scan all TypeScript files
echo "Backend Files to Document:"
echo "════════════════════════════════════════════════════"
for tsfile in $(find "${BACKEND_DIR}" -name "*.ts" -type f); do
  extract_functions "$tsfile"
done

echo ""
echo "🔧 Generating documentation template..."
echo ""

# Create comprehensive JSDoc guide
cat > "${DOCS_OUTPUT_DIR}/JSDOC_GUIDE.md" <<'EOF'
# JSDoc Documentation Guide for NexusShield Backend

## Overview
All exported functions and classes must have comprehensive JSDoc documentation.

## Structure

### Module-Level Documentation
```typescript
/**
 * @fileoverview Brief description of the module's purpose
 * More detailed explanation of what this module does
 *
 * @author kushin77
 * @version 1.0.0
 * @since 2026-03-13
 */
```

### Function Documentation

#### Async Functions
```typescript
/**
 * Brief one-line description of what the function does.
 * More detailed explanation if needed.
 *
 * @async
 * @param {type} paramName - Description of parameter
 * @param {type} [optionalParam] - Optional parameter with default
 * @returns {Promise<type>} What the promise resolves to
 * @throws {ErrorType} When this error is thrown
 *
 * @example
 * // Example usage
 * const result = await myFunction(param1, param2);
 */
export async function myFunction(
  paramName: Type,
  optionalParam?: string
): Promise<ReturnType> {
  // Implementation
}
```

#### Synchronous Functions
```typescript
/**
 * Brief description.
 *
 * @param {type} paramName - Parameter description
 * @returns {type} Return value description
 * @throws {ErrorType} Error conditions
 *
 * @example
 * const result = mySync Function(param);
 */
export function mySyncFunction(paramName: Type): ReturnType {
  // Implementation
}
```

### Class Documentation

```typescript
/**
 * Brief class description
 *
 * Longer explanation of class purpose and usage patterns.
 *
 * @example
 * const instance = new MyClass(config);
 * const result = await instance.method();
 */
export class MyClass {
  /**
   * Constructor description
   *
   * @param {Config} config - Configuration object
   */
  constructor(config: Config) {
    // ...
  }

  /**
   * Method description with full JSDoc
   */
  async method(): Promise<void> {
    // ...
  }
}
```

## Required Tags

### For all functions:
- `@param` - Each parameter with type and description
- `@returns` - Return type and description
- `@throws` - Any exceptions that can be thrown
- `@example` - At least one usage example

### For async functions:
- `@async` - Mark that function is asynchronous

### For complex types:
- Use `{type}` or `{Type|AlternativeType}` for unions
- Use `{Object}` with property documentation for object literals

## Examples

### Multi-parameter, async function with errors
```typescript
/**
 * Resolves credentials from failover chain with latency tracking.
 *
 * Attempts each credential backend in order until successful.
 * Measures and logs failover latency for SLA compliance.
 *
 * @async
 * @param {string} serviceName - Name of service requiring credentials
 * @param {string[]} [providers] - Backends to try: 'gsm', 'vault', 'kms'
 * @param {Object} [options] - Advanced options object
 * @param {number} [options.timeout=5000] - Timeout in milliseconds
 * @param {boolean} [options.cache=true] - Use local cache if available
 * @param {string} [options.auditLog] - Audit trail destination
 *
 * @returns {Promise<{value: string, latency_ms: number}>} Resolved credential and SLA metric
 * @throws {CredentialError} If all backends fail or timeout
 * @throws {ValidationError} If serviceName is invalid
 *
 * @example
 * try {
 *   const cred = await resolveCredential('api-key', ['gsm', 'vault']);
 *   console.log(`Latency: ${cred.latency_ms}ms`);
 * } catch (err) {
 *   // Handle credential resolution failure
 *   logger.error('Failed to resolve credentials', err);
 * }
 */
```

## Documentation Quality Checklist

- [ ] @fileoverview describes module purpose
- [ ] Every exported function has @param for each parameter
- [ ] Every exported function has @returns describing output
- [ ] @throws documented for all error conditions
- [ ] @example shows common usage pattern
- [ ] Complex objects have Property descriptions
- [ ] Async functions marked with @async
- [ ] Optional parameters in brackets [paramName]
- [ ] Types are specific (not just `Object` or `any`)
- [ ] At least 2-3 lines of description before @param tags

## Running JSDoc Generator

```bash
# Generate HTML documentation from JSDoc comments
npx typedoc --out docs/api-html backend/src

# Validate missing documentation
npm run validate:jsdoc

# Auto-generate stub documentation (manual completion required)
npm run generate:jsdoc-stubs
```

## Files Requiring Complete Documentation

Priority 1 (Complete):
- [ ] backend/src/credentials.ts (5 functions)
- [ ] backend/src/auth.ts (8 functions)
- [ ] backend/src/audit.ts (4 functions)
- [ ] backend/src/compliance.ts (4 functions)

Priority 2 (High):
- [ ] backend/src/metrics.ts (3 functions)
- [ ] backend/src/middleware/*.ts (12 functions)
- [ ] backend/src/routes/*.ts (33 handlers)
- [ ] backend/src/providers/*.ts (8 functions)

Priority 3 (Medium):
- [ ] backend/src/lib/*.ts (Various utilities)
- [ ] backend/src/api/*.ts (REST handlers)

## Tips

1. **Be Specific**: Avoid generic types like `any` or `Object`. Use actual types.
2. **Provide Context**: Explain WHY a function does something, not just WHAT it does.
3. **Show Examples**: Include at least one realistic usage example for each function.
4. **Document Errors**: List all exceptions that could be thrown.
5. **Use Markdown**: JSDoc supports markdown for formatting:
   - `code` for inline code
   - **bold** for emphasis
   - Lists for multiple items
6. **Link Types**: Use `{linkpkg:type}` to create cross-references between documented types.

## Automated Validation

```bash
# Check for missing JSDoc (run in pre-commit)
npm run lint:jsdoc --strict

# Generate coverage report
npm run jsdoc:coverage

# This will fail CI if documentation < 90% complete
```
EOF

echo "✅ Generated JSDoc guide: ${DOCS_OUTPUT_DIR}/JSDOC_GUIDE.md"

# Create summary report
cat > "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md" <<'EOF'
# Backend Documentation Status Report

## Summary
Comprehensive JSDoc documentation implementation for all backend functions.

## Files Analyzed
EOF

find "${BACKEND_DIR}" -name "*.ts" -type f | while read -r file; do
  echo "- $file" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"  
  # Count functions
  func_count=$(grep -c "^export.*function\|^export class" "$file" || echo 0)
  echo "  - Functions/Classes: $func_count" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
done

echo "" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "## Next Steps" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "1. Review JSDOC_GUIDE.md for documentation standards" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "2. Add @param, @returns, @throws, and @example to all functions" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "3. Run typedoc to generate HTML documentation" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo "4. Validate with: npm run lint:jsdoc --strict" >> "${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"

echo "✅ Generated status report: ${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo ""
echo "📚 Documentation files created:"
echo "  - ${DOCS_OUTPUT_DIR}/JSDOC_GUIDE.md"
echo "  - ${DOCS_OUTPUT_DIR}/documentation-status-${TIMESTAMP}.md"
echo ""
echo "Next: Review the guide and add JSDoc to all exported functions"
