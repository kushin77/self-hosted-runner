/**
 * NexusShield Portal - VS Code Extension
 * 
 * Integrates the NexusShield migration dashboard and portal
 * into VS Code for seamless DevOps automation and monitoring.
 * 
 * Features:
 * - Dashboard webview panel
 * - Migration job management
 * - Health monitoring
 * - Audit logging
 * - API key management
 * - Real-time notifications
 */

import * as vscode from 'vscode';
import * as axios from 'axios';
import * as path from 'path';
import { NexusShieldAPI } from './api/client';
import { DashboardPanel } from './views/dashboard-panel';
import { MigrationsTreeProvider } from './views/migrations-tree';
import { HealthTreeProvider } from './views/health-tree';
import { RecentActivityTreeProvider } from './views/recent-activity-tree';
import { Logger } from './utils/logger';

// Global state
let extensionContext: vscode.ExtensionContext;
let apiClient: NexusShieldAPI;
let logger: Logger;
let dashboardPanel: DashboardPanel | undefined;
let statusBarItem: vscode.StatusBarItem;

// Tree view providers
let migrationsProvider: MigrationsTreeProvider;
let healthProvider: HealthTreeProvider;
let recentActivityProvider: RecentActivityTreeProvider;

/**
 * Extension activation
 */
export async function activate(context: vscode.ExtensionContext) {
  extensionContext = context;
  logger = new Logger('nexus-shield', context);
  
  logger.info('NexusShield Portal extension activating...');

  try {
    // Initialize API client
    const config = vscode.workspace.getConfiguration('nexus-shield');
    const apiUrl = config.get<string>('apiUrl') || 'http://localhost:8080';
    const apiKey = await context.secrets.get('nexus-shield.apiKey') || '';
    
    apiClient = new NexusShieldAPI(apiUrl, apiKey, logger);
    
    // Register commands
    registerCommands(context);
    
    // Register tree view providers
    registerTreeViews(context);
    
    // Register status bar
    registerStatusBar(context);
    
    // Set up auto-refresh
    setupAutoRefresh(context);
    
    // Set context for command visibility
    vscode.commands.executeCommand('setContext', 'nexus-shield.authenticated', !!apiKey);
    
    logger.info('NexusShield Portal extension activated successfully');
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    logger.error(`Failed to activate extension: ${errorMsg}`);
    vscode.window.showErrorMessage(`NexusShield: Failed to activate (${errorMsg})`);
  }
}

/**
 * Extension deactivation
 */
export function deactivate() {
  logger.info('NexusShield Portal extension deactivating...');
  dashboardPanel?.dispose();
  statusBarItem?.dispose();
}

/**
 * Register all extension commands
 */
function registerCommands(context: vscode.ExtensionContext) {
  // Open Dashboard
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.openDashboard', async () => {
      logger.info('Opening NexusShield Dashboard');
      
      if (dashboardPanel) {
        dashboardPanel.reveal(vscode.ViewColumn.Beside);
      } else {
        dashboardPanel = new DashboardPanel(
          extensionContext,
          apiClient,
          logger
        );
        dashboardPanel.onDidDispose(() => {
          dashboardPanel = undefined;
        });
      }
    })
  );

  // View Migrations
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.viewMigrations', async () => {
      logger.info('Viewing migrations');
      await vscode.commands.executeCommand('nexus-shield.migrations.focus');
    })
  );

  // View Metrics
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.viewMetrics', async () => {
      logger.info('Viewing metrics');
      const metrics = await apiClient.getMetrics();
      
      vscode.window.showInformationMessage(
        `NexusShield Metrics:\n` +
        `Active Migrations: ${metrics.activeMigrations}\n` +
        `Completed: ${metrics.completedMigrations}\n` +
        `Health: ${metrics.healthStatus}`
      );
    })
  );

  // View Audit Log
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.viewAuditLog', async () => {
      logger.info('Opening audit log');
      const auditLog = await apiClient.getAuditLog(100);
      
      const panel = vscode.window.createWebviewPanel(
        'nexus-shield-audit',
        'NexusShield Audit Log',
        vscode.ViewColumn.Beside,
        { enableScripts: true }
      );
      
      panel.webview.html = generateAuditLogHtml(auditLog);
    })
  );

  // Start Migration
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.startMigration', async () => {
      logger.info('Starting new migration');
      
      const name = await vscode.window.showInputBox({
        prompt: 'Enter migration name',
        placeHolder: 'my-migration-2026-03-11'
      });
      
      if (!name) return;
      
      const source = await vscode.window.showQuickPick(
        ['AWS', 'GCP', 'Azure', 'On-Prem'],
        { placeHolder: 'Select source cloud' }
      );
      
      if (!source) return;
      
      const target = await vscode.window.showQuickPick(
        ['AWS', 'GCP', 'Azure', 'On-Prem'],
        { placeHolder: 'Select target cloud' }
      );
      
      if (!target) return;
      
      try {
        const migration = await apiClient.createMigration({
          name,
          source,
          target,
          createdBy: process.env.USER || 'unknown'
        });
        
        logger.info(`Migration created: ${migration.id}`);
        vscode.window.showInformationMessage(`Migration created: ${migration.id}`);
        
        // Refresh migrations tree
        migrationsProvider.refresh();
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(`Failed to create migration: ${errorMsg}`);
        vscode.window.showErrorMessage(`Failed to create migration: ${errorMsg}`);
      }
    })
  );

  // Authenticate
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.authenticate', async () => {
      logger.info('Authenticating with NexusShield');
      
      const apiKey = await vscode.window.showInputBox({
        prompt: 'Enter NexusShield API Key',
        password: true,
        placeHolder: 'sk_live_...'
      });
      
      if (!apiKey) return;
      
      try {
        // Verify API key
        const apiUrl = vscode.workspace.getConfiguration('nexus-shield').get<string>('apiUrl');
        const testClient = new NexusShieldAPI(apiUrl || 'http://localhost:8080', apiKey, logger);
        await testClient.health();
        
        // Store API key securely
        await context.secrets.store('nexus-shield.apiKey', apiKey);
        
        // Update global client
        apiClient = testClient;
        
        // Set context for command visibility
        vscode.commands.executeCommand('setContext', 'nexus-shield.authenticated', true);
        
        logger.info('Authentication successful');
        vscode.window.showInformationMessage('NexusShield authentication successful');
        
        // Refresh trees
        migrationsProvider.refresh();
        healthProvider.refresh();
        recentActivityProvider.refresh();
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(`Authentication failed: ${errorMsg}`);
        vscode.window.showErrorMessage(`Authentication failed: ${errorMsg}`);
      }
    })
  );

  // Open Settings
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.openSettings', async () => {
      logger.info('Opening NexusShield settings');
      await vscode.commands.executeCommand(
        'workbench.action.openSettings',
        'nexus-shield'
      );
    })
  );
}

/**
 * Register tree view providers
 */
function registerTreeViews(context: vscode.ExtensionContext) {
  // Migrations tree
  migrationsProvider = new MigrationsTreeProvider(apiClient, logger);
  vscode.window.registerTreeDataProvider('nexus-shield.migrations', migrationsProvider);
  
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.migrations.refresh', () => {
      migrationsProvider.refresh();
    })
  );
  
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.migration.open', (item) => {
      vscode.window.showInformationMessage(`Migration ${item.label}: ${JSON.stringify(item.data)}`);
    })
  );

  // Health tree
  healthProvider = new HealthTreeProvider(apiClient, logger);
  vscode.window.registerTreeDataProvider('nexus-shield.health', healthProvider);
  
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.health.refresh', () => {
      healthProvider.refresh();
    })
  );

  // Recent activity tree
  recentActivityProvider = new RecentActivityTreeProvider(apiClient, logger);
  vscode.window.registerTreeDataProvider('nexus-shield.recent', recentActivityProvider);
  
  context.subscriptions.push(
    vscode.commands.registerCommand('nexus-shield.recent.refresh', () => {
      recentActivityProvider.refresh();
    })
  );
}

/**
 * Register status bar
 */
function registerStatusBar(context: vscode.ExtensionContext) {
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100
  );
  statusBarItem.command = 'nexus-shield.openDashboard';
  statusBarItem.text = '$(cloud) NexusShield';
  statusBarItem.tooltip = 'Click to open NexusShield Dashboard';
  statusBarItem.show();
  
  context.subscriptions.push(statusBarItem);
}

/**
 * Setup auto-refresh of tree views
 */
function setupAutoRefresh(context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration('nexus-shield');
  const autoRefresh = config.get<boolean>('autoRefresh', true);
  const refreshInterval = config.get<number>('refreshInterval', 5000);
  
  if (autoRefresh) {
    const interval = setInterval(() => {
      if (apiClient) {
        migrationsProvider.refresh();
        healthProvider.refresh();
        recentActivityProvider.refresh();
      }
    }, refreshInterval);
    
    context.subscriptions.push(
      new vscode.Disposable(() => clearInterval(interval))
    );
  }
  
  // Listen for configuration changes
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(e => {
      if (e.affectsConfiguration('nexus-shield')) {
        logger.info('Configuration changed, reloading...');
        // Reload extension configuration
      }
    })
  );
}

/**
 * Generate HTML for audit log view
 */
function generateAuditLogHtml(auditLog: any[]): string {
  const rows = auditLog.map(log => `
    <tr>
      <td>${log.timestamp}</td>
      <td>${log.action}</td>
      <td>${log.status}</td>
      <td>${log.details}</td>
    </tr>
  `).join('');
  
  return `<!DOCTYPE html>
  <html>
  <head>
    <style>
      body { font-family: var(--vscode-font-family); }
      table { width: 100%; border-collapse: collapse; }
      th, td { padding: 8px; text-align: left; border-bottom: 1px solid var(--vscode-editorWidget-border); }
      th { background-color: var(--vscode-editorWidget-background); font-weight: bold; }
    </style>
  </head>
  <body>
    <h2>Audit Log</h2>
    <table>
      <thead>
        <tr>
          <th>Timestamp</th>
          <th>Action</th>
          <th>Status</th>
          <th>Details</th>
        </tr>
      </thead>
      <tbody>
        ${rows}
      </tbody>
    </table>
  </body>
  </html>`;
}
