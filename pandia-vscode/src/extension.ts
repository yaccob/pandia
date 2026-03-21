import * as vscode from 'vscode';
import { PandiaClient } from './client';
import { ContainerManager } from './container';
import { patchHtmlForWebview } from './html-patch';

let previewPanel: vscode.WebviewPanel | undefined;
let client: PandiaClient | undefined;
let containerManager: ContainerManager | undefined;
let debounceTimer: ReturnType<typeof setTimeout> | undefined;

async function ensureServer(): Promise<PandiaClient> {
  const config = vscode.workspace.getConfiguration('pandia');
  const serverUrl = config.get<string>('serverUrl');
  const port = config.get<number>('port') || 3300;

  // If user configured a server URL, use it
  if (serverUrl) {
    const c = new PandiaClient(serverUrl);
    if (await c.checkHealth()) {
      return c;
    }
    throw new Error(`Pandia server at ${serverUrl} is not responding.`);
  }

  // Try default local URL
  const defaultUrl = `http://localhost:${port}`;
  const c = new PandiaClient(defaultUrl);
  if (await c.checkHealth()) {
    return c;
  }

  // No server running — start a container
  const image = config.get<string>('containerImage') || 'yaccob/pandia:latest';
  containerManager = new ContainerManager({ image, port });

  const runtime = containerManager.detectRuntime();
  if (!runtime) {
    throw new Error(
      'No pandia server found and no container runtime (Docker/Podman) available.\n'
      + 'Either start a pandia server manually or install Docker/Podman.'
    );
  }

  const statusMsg = vscode.window.setStatusBarMessage('$(loading~spin) Starting pandia server...');
  try {
    await containerManager.start();

    // Wait for server to become ready (up to 30s)
    for (let i = 0; i < 60; i++) {
      if (await c.checkHealth()) {
        statusMsg.dispose();
        return c;
      }
      await new Promise(r => setTimeout(r, 500));
    }
    throw new Error('Pandia server did not become ready within 30 seconds.');
  } catch (e) {
    statusMsg.dispose();
    throw e;
  }
}

async function updatePreview(document: vscode.TextDocument) {
  if (!previewPanel || !client) return;
  if (document.languageId !== 'markdown') return;

  try {
    const config = vscode.workspace.getConfiguration('pandia');
    const krokiServer = config.get<string>('krokiServer');
    const html = await client.preview(document.getText(), {
      kroki_server: krokiServer || undefined,
    });
    if (previewPanel) {
      previewPanel.webview.html = patchHtmlForWebview(html);
    }
  } catch (err: any) {
    if (previewPanel) {
      previewPanel.webview.html = `<html><body>
        <h2>Pandia Preview Error</h2>
        <pre>${escapeHtml(err.message || String(err))}</pre>
      </body></html>`;
    }
  }
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function scheduleUpdate(document: vscode.TextDocument) {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => updatePreview(document), 1000);
}

export function activate(context: vscode.ExtensionContext) {
  const command = vscode.commands.registerCommand('pandia.openPreview', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'markdown') {
      vscode.window.showWarningMessage('Pandia Preview requires a Markdown file.');
      return;
    }

    try {
      client = await ensureServer();
    } catch (err: any) {
      vscode.window.showErrorMessage(err.message || String(err));
      return;
    }

    if (previewPanel) {
      previewPanel.reveal(vscode.ViewColumn.Beside);
    } else {
      previewPanel = vscode.window.createWebviewPanel(
        'pandiaPreview',
        'Pandia Preview',
        vscode.ViewColumn.Beside,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
        }
      );

      previewPanel.onDidDispose(() => {
        previewPanel = undefined;
      }, null, context.subscriptions);
    }

    await updatePreview(editor.document);
  });

  // Update preview on text changes (debounced)
  const onChangeText = vscode.workspace.onDidChangeTextDocument((e) => {
    if (previewPanel && e.document.languageId === 'markdown') {
      scheduleUpdate(e.document);
    }
  });

  // Update preview when switching to a different markdown file
  const onChangeEditor = vscode.window.onDidChangeActiveTextEditor((editor) => {
    if (previewPanel && editor && editor.document.languageId === 'markdown') {
      updatePreview(editor.document);
    }
  });

  context.subscriptions.push(command, onChangeText, onChangeEditor);
}

export function deactivate() {
  if (debounceTimer) clearTimeout(debounceTimer);
  if (containerManager) {
    containerManager.stop().catch(() => {});
  }
}
