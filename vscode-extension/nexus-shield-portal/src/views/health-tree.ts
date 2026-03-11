/**
 * Health Status Tree View Provider
 */

import * as vscode from 'vscode';
import { NexusShieldAPI, HealthStatus } from '../api/client';
import { Logger } from '../utils/logger';

export class HealthTreeProvider implements vscode.TreeDataProvider<HealthItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<HealthItem | undefined | null | void> =
    new vscode.EventEmitter<HealthItem | undefined | null | void>();
  readonly onDidChangeTreeData: vscode.Event<HealthItem | undefined | null | void> =
    this._onDidChangeTreeData.event;

  private health: HealthStatus | null = null;
  private autoRefreshInterval: NodeJS.Timeout | null = null;

  constructor(private apiClient: NexusShieldAPI, private logger: Logger) {
    this.startAutoRefresh();
  }

  async getTreeItem(element: HealthItem): Promise<vscode.TreeItem> {
    const icon = this.getStatusIcon(element.type, element.value);
    
    return {
      label: element.label,
      description: element.value ? 'Available' : 'Down',
      iconPath: icon,
      collapsibleState: vscode.TreeItemCollapsibleState.None
    };
  }

  async getChildren(element?: HealthItem | undefined): Promise<HealthItem[]> {
    if (element) {
      return [];
    }

    try {
      this.health = await this.apiClient.health();
      
      const items: HealthItem[] = [
        new HealthItem('API Service', this.health.services.api, 'service'),
        new HealthItem('Database', this.health.services.database, 'service'),
        new HealthItem('Cache Service', this.health.services.cache, 'service')
      ];
      
      return items;
    } catch (error) {
      this.logger.error(`Failed to load health status: ${error}`);
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

  private getStatusIcon(type: string, value: boolean): vscode.ThemeIcon {
    return value
      ? new vscode.ThemeIcon('check-all')
      : new vscode.ThemeIcon('error');
  }

  dispose() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
    }
  }
}

export class HealthItem {
  constructor(
    public label: string,
    public value: boolean,
    public type: string
  ) {}
}
