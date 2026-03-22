import { execSync, exec } from 'child_process';

export interface ContainerOptions {
  image?: string;
  port?: number;
  containerName?: string;
}

export class ContainerManager {
  private image: string;
  private port: number;
  private containerName: string;

  constructor(opts: ContainerOptions = {}) {
    this.image = opts.image || 'yaccob/pandia:latest';
    this.port = opts.port || 3300;
    this.containerName = opts.containerName || 'pandia-preview';
  }

  detectRuntime(): string | null {
    for (const rt of ['podman', 'docker']) {
      try {
        execSync(`${rt} --version`, { stdio: 'ignore' });
        return rt;
      } catch {}
    }
    return null;
  }

  buildRunCommand(runtime: string): string {
    return `${runtime} run --rm -d --name ${this.containerName}`
      + ` -p ${this.port}:${this.port}`
      + ` ${this.image}`
      + ` --serve ${this.port}`;
  }

  buildStopCommand(runtime: string): string {
    return `${runtime} stop ${this.containerName}`;
  }

  async start(): Promise<string> {
    const runtime = this.detectRuntime();
    if (!runtime) {
      throw new Error('Neither Docker nor Podman found. Install one to use Pandia Preview.');
    }

    // Stop any leftover container
    try {
      execSync(this.buildStopCommand(runtime), { stdio: 'ignore' });
    } catch {}

    const cmd = this.buildRunCommand(runtime);
    return new Promise((resolve, reject) => {
      exec(cmd, (err, stdout) => {
        if (err) reject(new Error(`Failed to start container: ${err.message}`));
        else resolve(stdout.trim());
      });
    });
  }

  async stop(): Promise<void> {
    const runtime = this.detectRuntime();
    if (!runtime) return;

    try {
      execSync(this.buildStopCommand(runtime), { stdio: 'ignore' });
    } catch {}
  }
}
