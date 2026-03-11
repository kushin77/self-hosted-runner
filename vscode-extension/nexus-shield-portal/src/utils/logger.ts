/**
 * Logger utility for NexusShield extension
 */

import * as vscode from 'vscode';

export class Logger {
  private outputChannel: vscode.OutputChannel;
  private logLevel: 'debug' | 'info' | 'warn' | 'error';

  constructor(name: string, context: vscode.ExtensionContext) {
    this.outputChannel = vscode.window.createOutputChannel(`NexusShield: ${name}`);
    
    const config = vscode.workspace.getConfiguration('nexus-shield');
    this.logLevel = config.get<'debug' | 'info' | 'warn' | 'error'>('logLevel', 'info');
    
    context.subscriptions.push(this.outputChannel);
  }

  debug(message: string) {
    if (this.shouldLog('debug')) {
      this.log(`[DEBUG] ${message}`);
    }
  }

  info(message: string) {
    if (this.shouldLog('info')) {
      this.log(`[INFO] ${message}`);
    }
  }

  warn(message: string) {
    if (this.shouldLog('warn')) {
      this.log(`[WARN] ${message}`);
    }
  }

  error(message: string) {
    this.log(`[ERROR] ${message}`);
  }

  private log(message: string) {
    const timestamp = new Date().toISOString();
    this.outputChannel.appendLine(`${timestamp} ${message}`);
  }

  private shouldLog(level: string): boolean {
    const levels = ['debug', 'info', 'warn', 'error'];
    return levels.indexOf(level) >= levels.indexOf(this.logLevel);
  }

  show() {
    this.outputChannel.show();
  }
}
