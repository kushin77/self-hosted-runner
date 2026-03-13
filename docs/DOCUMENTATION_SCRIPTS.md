# NPM Scripts for Documentation Management
# Add these to backend/package.json under "scripts" section

{
  "scripts": {
    "docs:jsdoc": "typedoc --out ./docs/api-html ./src --excludePrivate --excludeInternal",
    "docs:jsdoc:watch": "typedoc --out ./docs/api-html ./src --excludePrivate --excludeInternal --watch",
    "docs:jsdoc:json": "typedoc --json ./docs/api.json ./src --excludePrivate --excludeInternal",
    "lint:jsdoc": "jsdoc-strict --check-types --exclude-private --exclude-internal src/",
    "lint:jsdoc:strict": "jsdoc-strict --check-types --exclude-private --exclude-internal --strict src/",
    "validate:jsdoc": "tsc --noEmit --allowJs --checkJs --declaration --listFiles src/ && npm run lint:jsdoc",
    "jsdoc:coverage": "jsdoc-coverage --check-types src/ | tee docs/jsdoc-coverage-report.txt",
    "generate:jsdoc-stubs": "jsdoc-stub-generator --output ./docs/jsdoc-stubs.md src/",
    "format:docs": "prettier --write 'docs/**/*.md' '.instructions.md' 'README*.md'",
    "docs:sync": "npm run docs:jsdoc && npm run docs:jsdoc:json && npm run jsdoc:coverage"
  },
  "devDependencies": {
    "typedoc": "^0.24.0",
    "typedoc-plugin-markdown": "^3.15.0",
    "jsdoc": "^4.0.0",
    "jsdoc-strict": "^3.0.0",
    "jsdoc-coverage": "^2.0.0",
    "prettier": "^3.0.0"
  }
}
