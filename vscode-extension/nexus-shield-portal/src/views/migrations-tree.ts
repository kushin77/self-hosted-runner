/**
 * Migrations Tree View Provider
 */

import * as vscode from 'vscode';
import { NexusShieldAPI, Migration } from '../api/client';
import { Logger } from '../utils/logger';

export class MigrationsTreeProvider implements vscode.TreeDataProvider<MigrationItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<MigrationItem | undefined | null | void> =
    new vscode.EventEmitter<MigrationItem | undefined | null | void>();
  readonly onDidChangeTreeData: vscode.Event<MigrationItem | undefined | null | void> =
    this._onDidChangeTreeData.event;

  private migrations: Migration[] = [];
  private autoRefreshInterval: NodeJS.Timeout | null = null;

  constructor(private apiClient: NexusShieldAPI, private logger: Logger) {
    this.startAutoRefresh();
  }

  async getTreeItem(element: MigrationItem): Promise<vscode.TreeItem> {
    const icon = this.getStatusIcon(element.data.status);
    
    return {
      label: element.data.name,
      description: `${element.data.status} (${element.data.progress}%)`,
      collapsibleState: vscode.TreeItemCollapsibleState.None,
      iconPath: icon,
      command: {
        command: 'nexus-shield.migration.open',
        title: 'Open Migration',
        arguments: [element]
      }
    };
  }

  async getChildren(element?: MigrationItem | undefined): Promise<MigrationItem[]> {
    if (element) {
      return [];
    }

    try {
      this.migrations = await this.apiClient.listMigrations(50);
      return this.migrations.map(m => new MigrationItem(m));
    } catch (error) {
      this.logger.error(`Failed to load migrations: ${error}`);
      return [];
    }
  }

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  private startAutoRefresh() {
    const config = vscode.workspace.getConfiguration('nexus-shield');
    const autoRefresh = config.get<boolean>('autoRefresh', true);
    const refreshInterval = config.get<number>('refreshInterval', 5000);

    if (autoRefresh) {
      this.autoRefreshInterval = setInterval(() => {
        this.refresh();
      }, refreshInterval);
    }
  }

  private getStatusIcon(status: string): vscode.ThemeIcon {
    switch (status) {
      case 'running':
        return new vscode.ThemeIcon('sync');
      case 'completed':
        return new vscode.ThemeIcon('check');
      case 'failed':
        return new vscode.ThemeIcon('error');
      case 'pending':
        return new vscode.ThemeIcon('clock');
      default:
        return new vscode.ThemeIcon('question');
    }
  }

  dispose() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
    }
  }
}

export class MigrationItem {
  constructor(public data: Migration) {}
}
