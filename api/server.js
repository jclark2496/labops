// LabOps API Server
// Lightweight replacement for n8n — handles VM management, container health, and config.
// Runs on port 3000 inside Docker, proxied by nginx at /api/.

const http = require('http');
const https = require('https');
const { execSync } = require('child_process');
const fs = require('fs');

const PORT = 3000;

// ── Proxmox API helper ─────────────────────────────────────────────────────────

function proxmoxRequest(method, apiPath) {
  return new Promise((resolve) => {
    const url = process.env.PROXMOX_URL;
    const node = process.env.PROXMOX_NODE;
    const tokenId = process.env.PROXMOX_TOKEN_ID;
    const tokenSecret = process.env.PROXMOX_TOKEN_SECRET;

    if (!url || !node || !tokenId || !tokenSecret) {
      return resolve({ error: 'PROXMOX_URL not configured in .env' });
    }

    const fullUrl = `${url}/api2/json/nodes/${node}${apiPath}`;
    const auth = `PVEAPIToken=${tokenId}=${tokenSecret}`;

    try {
      const parsed = new URL(fullUrl);
      const opts = {
        hostname: parsed.hostname,
        port: parsed.port || 8006,
        path: parsed.pathname,
        method: method,
        headers: { 'Authorization': auth },
        rejectUnauthorized: false,
        timeout: 15000
      };

      const req = https.request(opts, (res) => {
        let d = '';
        res.on('data', (c) => d += c);
        res.on('end', () => {
          try { resolve(JSON.parse(d)); }
          catch { resolve({ error: 'Invalid JSON from Proxmox', raw: d.substring(0, 200) }); }
        });
      });
      req.on('error', (e) => resolve({ error: e.message }));
      req.on('timeout', () => { req.destroy(); resolve({ error: 'Proxmox request timed out' }); });
      req.end();
    } catch (e) {
      resolve({ error: e.message });
    }
  });
}

// ── Route handlers ──────────────────────────────────────────────────────────────

// GET /vms — List VMs from Proxmox with IP addresses
async function handleListVMs() {
  const data = await proxmoxRequest('GET', '/qemu');
  if (data.error) return { vms: [], error: data.error };

  const vms = (data.data || [])
    .filter(vm => vm.vmid >= 200 && vm.vmid < 300)
    .map(vm => ({
      vmid: vm.vmid,
      name: vm.name || 'vm-' + vm.vmid,
      status: vm.status,
      ip: null,
      uptime: vm.uptime || 0,
      tags: vm.tags || ''
    }));

  // Fetch IP addresses for running VMs via QEMU guest agent
  for (const vm of vms) {
    if (vm.status !== 'running') continue;
    try {
      const agentData = await proxmoxRequest('GET', `/qemu/${vm.vmid}/agent/network-get-interfaces`);
      if (agentData && agentData.data && agentData.data.result) {
        for (const iface of agentData.data.result) {
          if (iface.name === 'lo' || iface.name === 'Loopback Pseudo-Interface 1') continue;
          const addrs = iface['ip-addresses'] || [];
          const ipv4 = addrs.find(a => a['ip-address-type'] === 'ipv4' && !a['ip-address'].startsWith('127.'));
          if (ipv4) { vm.ip = ipv4['ip-address']; break; }
        }
      }
    } catch { /* QEMU agent not available */ }
  }

  return { vms };
}

// POST /vms/:vmid/start — Start a VM
async function handleVMAction(vmid, action) {
  const apiAction = action === 'stop' ? 'shutdown' : action;
  const method = action === 'destroy' ? 'DELETE' : 'POST';
  const path = action === 'destroy' ? `/qemu/${vmid}/` : `/qemu/${vmid}/status/${apiAction}`;

  const result = await proxmoxRequest(method, path);
  if (result.error) return { success: false, error: result.error };
  return { success: true, action, vmid: parseInt(vmid) };
}

// POST /vms/provision — Provision a new VM (runs Terraform)
async function handleProvision(body) {
  // This endpoint was referenced in the dashboard but not implemented in n8n either
  return { success: false, error: 'Use "make provision" from the command line' };
}

// GET /containers — Docker container status
function handleContainers() {
  try {
    const raw = execSync(
      'curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json?all=true',
      { encoding: 'utf-8', timeout: 10000 }
    );
    const all = JSON.parse(raw);
    const containers = all
      .filter(c => c.Names && c.Names[0] && c.Names[0].includes('labops-'))
      .map(c => {
        const name = c.Names[0].replace(/^\//, '');
        const state = c.State || 'unknown';
        const statusText = c.Status || '';
        let health = null;
        if (statusText.includes('healthy') && !statusText.includes('unhealthy')) health = 'healthy';
        else if (statusText.includes('unhealthy')) health = 'unhealthy';
        else if (statusText.includes('starting')) health = 'starting';
        else if (state === 'running') health = 'healthy';
        return { name, state, health, statusText };
      });
    return { containers };
  } catch (e) {
    return { containers: [], error: e.message };
  }
}

// GET /health — Aggregate health check
function handleHealth() {
  const expected = [
    'labops-nginx', 'labops-api', 'labops-guacamole',
    'labops-guacd', 'labops-guac-postgres', 'labops-portainer'
  ];

  try {
    const raw = execSync(
      'curl -s --unix-socket /var/run/docker.sock http://localhost/containers/json',
      { encoding: 'utf-8', timeout: 5000 }
    );
    const all = JSON.parse(raw);
    const running = all.map(c => (c.Names && c.Names[0]) ? c.Names[0].replace(/^\//, '') : '');
    const healthy = expected.filter(name => running.includes(name)).length;
    const status = healthy === expected.length ? 'healthy' : healthy > 0 ? 'degraded' : 'down';
    return { status, healthy, total: expected.length, timestamp: new Date().toISOString() };
  } catch {
    return { status: 'down', healthy: 0, total: expected.length, timestamp: new Date().toISOString() };
  }
}

// GET /config — Dashboard configuration from env vars
function handleConfig() {
  return {
    guacProxy: '/guacamole',
    guacAdmin: process.env.GUAC_ADMIN_USER || 'guacadmin',
    guacAdminPw: process.env.GUAC_ADMIN_PASSWORD || 'guacadmin',
    guacDs: 'postgresql',
    vmUser: process.env.LAB_VM_USER || 'demo',
    vmPassword: process.env.LAB_VM_PASSWORD || '',
    proxmoxUrl: process.env.PROXMOX_URL || '',
    nginxPort: process.env.NGINX_PORT || '8080',
    guacPort: process.env.GUAC_PORT || '8085',
    portainerPort: process.env.PORTAINER_PORT || '9000'
  };
}

// ── HTTP Server ─────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  const url = req.url.replace(/\?.*$/, ''); // strip query params

  try {
    let result;

    if (req.method === 'GET' && url === '/vms') {
      result = await handleListVMs();
    } else if (req.method === 'GET' && url === '/containers') {
      result = handleContainers();
    } else if (req.method === 'GET' && url === '/health') {
      result = handleHealth();
    } else if (req.method === 'GET' && url === '/config') {
      result = handleConfig();
    } else if (req.method === 'POST' && url.match(/^\/vms\/(\d+)\/(start|stop)$/)) {
      const [, vmid, action] = url.match(/^\/vms\/(\d+)\/(start|stop)$/);
      result = await handleVMAction(vmid, action);
    } else if (req.method === 'DELETE' && url.match(/^\/vms\/(\d+)\/destroy$/)) {
      const [, vmid] = url.match(/^\/vms\/(\d+)\/destroy$/);
      result = await handleVMAction(vmid, 'destroy');
    } else if (req.method === 'POST' && url === '/vms/provision') {
      result = handleProvision();
    } else {
      res.writeHead(404);
      return res.end(JSON.stringify({ error: 'Not found' }));
    }

    res.writeHead(200);
    res.end(JSON.stringify(result));
  } catch (e) {
    res.writeHead(500);
    res.end(JSON.stringify({ error: e.message }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[LabOps API] Listening on port ${PORT}`);
  console.log(`[LabOps API] Proxmox: ${process.env.PROXMOX_URL || 'not configured'}`);
});
