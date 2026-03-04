#!/usr/bin/env node

/**
 * Agentic Workflows Management CLI
 * Orchestrate, validate, and deploy self-service agentic workflows
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const WORKFLOWS_DIR = '.github/workflows/agentic';
const COLORS = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m'
};

const log = {
  info: (msg) => console.log(`${COLORS.cyan}ℹ️  ${msg}${COLORS.reset}`),
  success: (msg) => console.log(`${COLORS.green}✅ ${msg}${COLORS.reset}`),
  warn: (msg) => console.log(`${COLORS.yellow}⚠️  ${msg}${COLORS.reset}`),
  error: (msg) => console.error(`${COLORS.red}❌ ${msg}${COLORS.reset}`),
  debug: (msg) => console.log(`${COLORS.dim}🐛 ${msg}${COLORS.reset}`)
};

/**
 * Parse YAML frontmatter from Markdown workflow file
 */
function parseFrontmatter(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  
  if (lines[0] !== '---') {
    throw new Error('Missing YAML frontmatter');
  }
  
  let endIdx = 1;
  while (endIdx < lines.length && lines[endIdx] !== '---') {
    endIdx++;
  }
  
  const yaml = lines.slice(1, endIdx).join('\n');
  const frontmatter = {};
  
  yaml.split('\n').forEach(line => {
    const [key, ...rest] = line.split(':');
    if (key && rest.length > 0) {
      frontmatter[key.trim()] = rest.join(':').trim();
    }
  });
  
  return { frontmatter, endLine: endIdx };
}

/**
 * List all agentic workflows
 */
async function listWorkflows() {
  if (!fs.existsSync(WORKFLOWS_DIR)) {
    log.warn(`Directory not found: ${WORKFLOWS_DIR}`);
    return;
  }
  
  const files = fs.readdirSync(WORKFLOWS_DIR)
    .filter(f => f.endsWith('.md'))
    .sort();
  
  if (files.length === 0) {
    log.info('No workflows found');
    return;
  }
  
  console.log(`\n📋 Agentic Workflows:\n`);
  
  files.forEach(file => {
    const mdPath = path.join(WORKFLOWS_DIR, file);
    const lockPath = path.join(WORKFLOWS_DIR, file.replace('.md', '.lock.yml'));
    
    try {
      const { frontmatter } = parseFrontmatter(mdPath);
      const name = frontmatter.name || 'Unknown';
      const desc = frontmatter.description || '';
      const compiled = fs.existsSync(lockPath);
      
      console.log(`  ${compiled ? '✅' : '⚠️ '} ${name}`);
      if (desc) console.log(`     ${desc}`);
      console.log(`     📄 ${file}`);
      if (compiled) {
        const stats = fs.statSync(lockPath);
        console.log(`     🔒 Compiled (${stats.size} bytes)`);
      } else {
        console.log(`     🔴 Not compiled`);
      }
      console.log('');
    } catch (err) {
      log.error(`Failed to parse ${file}: ${err.message}`);
    }
  });
}

/**
 * Validate a workflow file
 */
function validateWorkflow(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }
  
  try {
    const { frontmatter } = parseFrontmatter(filePath);
    
    const required = ['name', 'on', 'permissions', 'runs-on'];
    const missing = required.filter(field => !frontmatter[field]);
    
    if (missing.length > 0) {
      throw new Error(`Missing required fields: ${missing.join(', ')}`);
    }
    
    log.success(`Validation passed: ${filePath}`);
    return true;
  } catch (err) {
    throw err;
  }
}

/**
 * Compile a workflow (calls the bash compiler)
 */
function compileWorkflow(filePath) {
  validateWorkflow(filePath);
  
  log.info(`Compiling ${filePath}...`);
  
  try {
    const compilerPath = path.join(__dirname, 'compile-agentic-workflows.sh');
    execSync(`bash ${compilerPath} compile ${filePath}`, { stdio: 'inherit' });
    log.success(`Compiled: ${filePath}`);
  } catch (err) {
    throw new Error(`Compilation failed: ${err.message}`);
  }
}

/**
 * Compile all workflows
 */
function compileAll() {
  if (!fs.existsSync(WORKFLOWS_DIR)) {
    log.error(`Directory not found: ${WORKFLOWS_DIR}`);
    return;
  }
  
  const files = fs.readdirSync(WORKFLOWS_DIR)
    .filter(f => f.endsWith('.md'))
    .map(f => path.join(WORKFLOWS_DIR, f));
  
  if (files.length === 0) {
    log.warn('No workflows to compile');
    return;
  }
  
  log.info(`Compiling ${files.length} workflow(s)...`);
  
  let success = 0;
  let failed = 0;
  
  files.forEach(file => {
    try {
      compileWorkflow(file);
      success++;
    } catch (err) {
      log.error(err.message);
      failed++;
    }
  });
  
  console.log(`\n${COLORS.bright}Results:${COLORS.reset}`);
  log.success(`${success} compiled`);
  if (failed > 0) {
    log.error(`${failed} failed`);
  }
}

/**
 * Initialize agentic workflows directory with examples
 */
function initWorkflows() {
  if (!fs.existsSync(WORKFLOWS_DIR)) {
    fs.mkdirSync(WORKFLOWS_DIR, { recursive: true });
    log.success(`Created directory: ${WORKFLOWS_DIR}`);
  }
  
  const examples = [
    'auto-fix.md',
    'pr-review.md',
    'dependency-audit.md'
  ];
  
  examples.forEach(example => {
    const examplePath = path.join(__dirname, '..', 'docs', 'examples', example);
    const destPath = path.join(WORKFLOWS_DIR, example);
    
    if (fs.existsSync(examplePath) && !fs.existsSync(destPath)) {
      fs.copyFileSync(examplePath, destPath);
      log.success(`Initialized template: ${example}`);
    }
  });
}

/**
 * Show workflow details
 */
async function showWorkflow(name) {
  const filePath = path.join(WORKFLOWS_DIR, name.endsWith('.md') ? name : `${name}.md`);
  
  if (!fs.existsSync(filePath)) {
    throw new Error(`Workflow not found: ${filePath}`);
  }
  
  const { frontmatter, endLine } = parseFrontmatter(filePath);
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  
  console.log(`\n${COLORS.bright}Workflow Details${COLORS.reset}\n`);
  console.log(`Name:        ${frontmatter.name}`);
  console.log(`Description: ${frontmatter.description || 'N/A'}`);
  console.log(`Trigger:     ${frontmatter.on}`);
  console.log(`Permissions: ${frontmatter.permissions}`);
  console.log(`Runner:      ${frontmatter['runs-on']}`);
  
  const lockPath = filePath.replace('.md', '.lock.yml');
  if (fs.existsSync(lockPath)) {
    const stats = fs.statSync(lockPath);
    const mtime = new Date(stats.mtime).toLocaleString();
    console.log(`Compiled:    Yes (${mtime})`);
  } else {
    console.log(`Compiled:    No`);
  }
  
  console.log(`\n${COLORS.bright}Task Description${COLORS.reset}\n`);
  const description = lines.slice(endLine + 1).join('\n');
  console.log(description);
}

/**
 * Show CLI help
 */
function showHelp() {
  console.log(`
${COLORS.bright}Agentic Workflows CLI${COLORS.reset}
Manage self-service, AI-powered GitHub Actions workflows

${COLORS.bright}USAGE${COLORS.reset}
  aw <command> [options]

${COLORS.bright}COMMANDS${COLORS.reset}
  list              List all agentic workflows
  init              Initialize workflows directory with examples
  validate <name>   Validate a workflow file
  compile <name>    Compile a workflow to .lock.yml
  compile-all       Compile all workflows
  show <name>       Show workflow details
  help              Show this help message

${COLORS.bright}EXAMPLES${COLORS.reset}
  aw list
  aw init
  aw validate auto-fix.md
  aw compile pr-review
  aw compile-all
  aw show auto-fix
  aw help

${COLORS.bright}DOCUMENTATION${COLORS.reset}
  Setup:    docs/AGENTIC_WORKFLOWS_SETUP.md
  Examples: docs/AGENTIC_WORKFLOWS_EXAMPLES.md

${COLORS.bright}ENVIRONMENT${COLORS.reset}
  WORKFLOWS_DIR    Override workflows directory (default: .github/workflows/agentic)
  DEBUG            Set to 1 for debug output

`);
}

/**
 * Main CLI handler
 */
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'help';
  
  try {
    switch (command) {
      case 'list':
        await listWorkflows();
        break;
      
      case 'init':
        initWorkflows();
        break;
      
      case 'validate':
        if (!args[1]) throw new Error('Usage: aw validate <workflow.md>');
        validateWorkflow(args[1]);
        break;
      
      case 'compile':
        if (!args[1]) throw new Error('Usage: aw compile <workflow.md>');
        compileWorkflow(args[1]);
        break;
      
      case 'compile-all':
        compileAll();
        break;
      
      case 'show':
        if (!args[1]) throw new Error('Usage: aw show <name>');
        await showWorkflow(args[1]);
        break;
      
      case 'help':
        showHelp();
        break;
      
      default:
        log.error(`Unknown command: ${command}`);
        showHelp();
        process.exit(1);
    }
  } catch (err) {
    log.error(err.message);
    process.exit(1);
  }
}

main();
