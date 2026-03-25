import * as vscode from 'vscode';
import { PandiaClient } from './client';

let previewPanel: vscode.WebviewPanel | undefined;
let client: PandiaClient | undefined;
let debounceTimer: ReturnType<typeof setTimeout> | undefined;

function getServerUrl(): string {
  const config = vscode.workspace.getConfiguration('pandia');
  const url = config.get<string>('serverUrl');
  if (!url) {
    throw new Error(
      'No pandia server URL configured.\n'
      + 'Set "pandia.serverUrl" in your VS Code settings (e.g. http://localhost:3300).'
    );
  }
  return url;
}

async function ensureServer(): Promise<PandiaClient> {
  const url = getServerUrl();
  const c = new PandiaClient(url);
  if (await c.checkHealth()) {
    return c;
  }
  throw new Error(`Pandia server at ${url} is not responding.`);
}

async function updatePreview(document: vscode.TextDocument) {
  if (!previewPanel || !client) return;
  if (document.languageId !== 'markdown') return;

  try {
    const html = await client.render(document.getText(), {
      math: 'mathml',
    });
    if (previewPanel) {
      previewPanel.webview.html = html;
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
}
