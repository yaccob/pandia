import http from 'http';
import { URL } from 'url';

export interface RenderOptions {
  format?: 'html' | 'pdf';
  math?: 'mathjax' | 'mathml';
  maxwidth?: string;
  center_math?: boolean;
  kroki_server?: string;
}

export class PandiaClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async checkHealth(): Promise<boolean> {
    try {
      const res = await this.request('GET', '/health');
      return res.status === 200;
    } catch {
      return false;
    }
  }

  async render(content: string, opts: RenderOptions = {}): Promise<string> {
    if (!content.trim()) {
      throw new Error('Empty content');
    }

    const params = new URLSearchParams();
    if (opts.format) params.set('format', opts.format);
    if (opts.math) params.set('math', opts.math);
    if (opts.maxwidth) params.set('maxwidth', opts.maxwidth);
    if (opts.center_math) params.set('center_math', 'true');
    if (opts.kroki_server) params.set('kroki_server', opts.kroki_server);

    const query = params.toString();
    const path = '/render' + (query ? `?${query}` : '');

    const res = await this.request('POST', path, content);

    if (res.status === 400 || res.status === 500) {
      const errorBody = res.body;
      try {
        const parsed = JSON.parse(errorBody);
        throw new Error(parsed.error || `Server returned ${res.status}`);
      } catch (e) {
        if (e instanceof SyntaxError) {
          throw new Error(`Server returned ${res.status}: ${errorBody}`);
        }
        throw e;
      }
    }

    return res.body;
  }

  private request(method: string, path: string, body?: string): Promise<{ status: number; body: string }> {
    return new Promise((resolve, reject) => {
      const url = new URL(path, this.baseUrl);

      const opts: http.RequestOptions = {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method,
        timeout: 60000,
      };

      const req = http.request(opts, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          resolve({ status: res.statusCode || 0, body: data });
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timed out'));
      });

      if (body) {
        req.write(body);
      }
      req.end();
    });
  }
}
