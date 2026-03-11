/**
 * Recent Activity Tree View Provider
 */

import * as vscode from 'vscode';
import { NexusShieldAPI } from '../api/client';
import { Logger } from '../utils/logger';

export class RecentActivityTreeProvider implements vscode.TreeDataProvider<ActivityItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<ActivityItem | undefined | null | void> =
    new vscode.EventEmitter<ActivityItem | undefined | null | void>();
  readonly onDidChangeTreeData: vscode.Event<ActivityItem | undefined | null | void> =
    this._onDidChangeTreeData.event;

  private activities: any[] = [];
  private autoRefreshInterval: NodeJS.Timeout | null = null;

  constructor(private apiClient: NexusShieldAPI, private logger: Logger) {
    this.startAutoRefresh();
  }

  async getTreeItem(element: ActivityItem): Promise<vscode.TreeItem> {
    const icon = this.getActivityIcon(element.action);
    
    return {
      label: element.label,
      description: element.timestamp,
      iconPath: icon,
      collapsibleState: vscode.TreeItemCollapsibleState.None,
      tooltip: element.details
    };
  }

  async getChildren(element?: ActivityItem | undefined): Promise<ActivityItem[]> {
    if (element) {
      return [];
    }

    try {
      this.activities = await this.apiClient.getRecentActivity(20);
      
      return this.activities.map(activity =>
        new ActivityItem(
          this.formatActivityLabel(activity),
          activity.action,
          this.formatTime(activity.timestamp),
          activity.details || ''
        )
      );
    } catch (error) {
      this.logger.error(`Failed to load recent activity: ${error}`);
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

  private getActivityIcon(action: string): vscode.ThemeIcon {
    switch (action.toLowerCase()) {
      case 'migrate':
        return new vscode.ThemeIcon('cloud-upload');
      case 'deploy':
        return new vscode.ThemeIcon('rocket');
      case 'complete':
        return new vscode.ThemeIcon('check');
      case 'error':
        return new vscode.ThemeIcon('error');
      case 'start':
        return new vscode.ThemeIcon('play');
      case 'stop':
        return new vscode.ThemeIcon('stop');
      default:
        return new vscode.ThemeIcon('history');
    }
  }

  private formatActivityLabel(activity: any): string {
    return activity.message || activity.action || 'Unknown Activity';
  }

  private formatTime(timestamp: string): string {
    try {
      const date = new Date(timestamp);
      const now = new Date();
      const diff = now.getTime() - date.getTime();
      
      const minutes = Math.floor(diff / 60000);
      const hours = Math.floor(diff / 3600000);
      const days = Math.floor(diff / 86400000);
      
      if (minutes < 1) return 'just now';
      if (minutes < 60) return `${minutes}m ago`;
      if (hours < 24) return `${hours}h ago`;
      if (days < 7) return `${days}d ago`;
      
      return date.toLocaleDateString();
    } catch {
      return timestamp;
    }
  }

  dispose() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
    }
  }
}

export class ActivityItem {
  constructor(
    public label: string,
    public action: string,
    public timestamp: string,
    public details: string
  ) {}
}
