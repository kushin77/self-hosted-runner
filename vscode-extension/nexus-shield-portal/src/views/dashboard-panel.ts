/**
 * Dashboard Panel - Webview for NexusShield Dashboard
 */

import * as vscode from 'vscode';
import * as path from 'path';
import { NexusShieldAPI } from '../api/client';
import { Logger } from '../utils/logger';

export class DashboardPanel {
  public static readonly viewType = 'nexus-shield-dashboard';
  private panel: vscode.WebviewPanel;
  private disposables: vscode.Disposable[] = [];

  constructor(
    context: vscode.ExtensionContext,
    private apiClient: NexusShieldAPI,
    private logger: Logger
  ) {
    // Create webview panel
    this.panel = vscode.window.createWebviewPanel(
      DashboardPanel.viewType,
      'NexusShield Dashboard',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        enableFindWidget: true,
        retainContextWhenHidden: true
      }
    );

    // Set icon
    const iconPath = vscode.Uri.file(
      path.join(context.extensionPath, 'resources', 'icon.svg')
    );
    this.panel.iconPath = iconPath;

    // Handle messages from webview
    this.panel.webview.onDidReceiveMessage(
      message => this.handleMessage(message),
      undefined,
      this.disposables
    );

    // Handle panel disposal
    this.panel.onDidDispose(
      () => this.dispose(),
      undefined,
      this.disposables
    );

    // Listen for configuration changes
    vscode.workspace.onDidChangeConfiguration(
      e => {
        if (e.affectsConfiguration('nexus-shield')) {
          this.updateContent();
        }
      },
      undefined,
      this.disposables
    );

    // Initial content
    this.updateContent();
  }

  private async handleMessage(message: any) {
    this.logger.debug(`Webview message: ${message.command}`);

    switch (message.command) {
      case 'refresh':
        await this.updateContent();
        break;

      case 'get-metrics':
        try {
          const metrics = await this.apiClient.getMetrics();
          this.panel.webview.postMessage({
            command: 'metrics-data',
            data: metrics
          });
        } catch (error) {
          this.logger.error(`Failed to get metrics: ${error}`);
        }
        break;

      case 'get-migrations':
        try {
          const migrations = await this.apiClient.listMigrations();
          this.panel.webview.postMessage({
            command: 'migrations-data',
            data: migrations
          });
        } catch (error) {
          this.logger.error(`Failed to get migrations: ${error}`);
        }
        break;

      case 'start-migration':
        await vscode.commands.executeCommand('nexus-shield.startMigration');
        break;

      case 'open-settings':
        await vscode.commands.executeCommand('nexus-shield.openSettings');
        break;

      default:
        this.logger.warn(`Unknown command: ${message.command}`);
    }
  }

  private async updateContent() {
    const config = vscode.workspace.getConfiguration('nexus-shield');
    const dashboardUrl = config.get<string>('dashboardUrl') || 'http://localhost:3000';

    this.panel.webview.html = this.getHtml(dashboardUrl);
  }

  private getHtml(dashboardUrl: string): string {
    return `<!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>NexusShield Dashboard</title>
      <style>
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        
        body {
          font-family: var(--vscode-font-family);
          font-size: var(--vscode-font-size);
          color: var(--vscode-foreground);
          background-color: var(--vscode-editor-background);
          height: 100vh;
          overflow: hidden;
        }
        
        .container {
          display: flex;
          flex-direction: column;
          height: 100%;
          padding: 10px;
        }
        
        .header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 10px;
          border-bottom: 1px solid var(--vscode-editorWidget-border);
          margin-bottom: 10px;
        }
        
        .header h1 {
          font-size: 16px;
          font-weight: 600;
        }
        
        .controls {
          display: flex;
          gap: 5px;
        }
        
        button {
          padding: 6px 12px;
          background-color: var(--vscode-button-background);
          color: var(--vscode-button-foreground);
          border: 1px solid var(--vscode-editorWidget-border);
          border-radius: 2px;
          cursor: pointer;
          font-size: 12px;
          font-family: var(--vscode-font-family);
        }
        
        button:hover {
          background-color: var(--vscode-button-hoverBackground);
        }
        
        button:active {
          background-color: var(--vscode-button-background);
          opacity: 0.8;
        }
        
        .content {
          flex: 1;
          overflow: hidden;
          display: flex;
          flex-direction: column;
        }
        
        .dashboard-container {
          width: 100%;
          height: 100%;
          border: 1px solid var(--vscode-editorWidget-border);
          border-radius: 4px;
          overflow: hidden;
          background-color: var(--vscode-editor-background);
        }
        
        iframe {
          width: 100%;
          height: 100%;
          border: none;
          display: block;
        }
        
        .status {
          display: flex;
          gap: 10px;
          padding: 10px;
          background-color: var(--vscode-editorWidget-background);
          border-radius: 2px;
          font-size: 12px;
        }
        
        .status-item {
          display: flex;
          align-items: center;
          gap: 5px;
        }
        
        .status-indicator {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background-color: var(--vscode-testing-iconPassed);
        }
        
        .status-indicator.error {
          background-color: var(--vscode-testing-iconFailed);
        }
        
        .status-indicator.warning {
          background-color: var(--vscode-testing-iconQueued);
        }
        
        .loading {
          display: flex;
          justify-content: center;
          align-items: center;
          height: 100%;
          color: var(--vscode-descriptionForeground);
        }
        
        .spinner {
          border: 2px solid var(--vscode-editorWidget-border);
          border-top: 2px solid var(--vscode-button-background);
          border-radius: 50%;
          width: 20px;
          height: 20px;
          animation: spin 0.8s linear infinite;
        }
        
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>🚀 NexusShield Dashboard</h1>
          <div class="controls">
            <button onclick="refresh()">Refresh</button>
            <button onclick="startMigration()">New Migration</button>
            <button onclick="openSettings()">Settings</button>
          </div>
        </div>
        
        <div class="status">
          <div class="status-item">
            <div class="status-indicator" id="health-indicator"></div>
            <span id="health-text">Loading health status...</span>
          </div>
        </div>
        
        <div class="content">
          <div class="dashboard-container" id="dashboard">
            <div class="loading">
              <div>
                <div class="spinner"></div>
                <p style="margin-top: 10px;">Loading Dashboard...</p>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <script>
        const vscode = acquireVsCodeApi();
        let isLoading = false;
        
        function refresh() {
          if (!isLoading) {
            isLoading = true;
            vscode.postMessage({ command: 'refresh' });
            setTimeout(() => { isLoading = false; }, 1000);
          }
        }
        
        function startMigration() {
          vscode.postMessage({ command: 'start-migration' });
        }
        
        function openSettings() {
          vscode.postMessage({ command: 'open-settings' });
        }
        
        function updateHealth(status) {
          const indicator = document.getElementById('health-indicator');
          const text = document.getElementById('health-text');
          
          indicator.className = 'status-indicator';
          if (status === 'healthy') {
            indicator.style.backgroundColor = '#4EC9B0';
            text.textContent = '✓ System Healthy';
          } else if (status === 'degraded') {
            indicator.className = 'status-indicator warning';
            text.textContent = '⚠ System Degraded';
          } else {
            indicator.className = 'status-indicator error';
            text.textContent = '✗ System Unhealthy';
          }
        }
        
        // Load dashboard in iframe
        window.addEventListener('load', () => {
          const iframe = document.createElement('iframe');
          iframe.src = '${dashboardUrl}';
          document.getElementById('dashboard').innerHTML = '';
          document.getElementById('dashboard').appendChild(iframe);
          
          // Fetch health status
          vscode.postMessage({ command: 'get-metrics' });
        });
        
        // Handle messages from extension
        window.addEventListener('message', event => {
          const message = event.data;
          
          if (message.command === 'metrics-data') {
            updateHealth(message.data.healthStatus || 'unknown');
          }
        });
      </script>
    </body>
    </html>`;
  }

  public reveal(column?: vscode.ViewColumn) {
    this.panel.reveal(column);
  }

  public dispose() {
    this.panel.dispose();
    this.disposables.forEach(d => d.dispose());
  }
}
