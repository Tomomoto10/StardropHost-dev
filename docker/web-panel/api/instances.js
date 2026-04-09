/**
 * StardropHost | web-panel/api/instances.js
 * Multi-instance peer registry
 *
 * GET  /api/instances          — public, no auth — returns self info + peer list
 * POST /api/instances/register — public, no auth — cross-instance announce (quick-start.sh)
 * POST /api/instances/peer     — authenticated  — add/update a peer from UI
 * DELETE /api/instances/peer/:idx — authenticated — remove a peer
 */

const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const config = require('../server');

const PEERS_FILE = path.join(config.DATA_DIR, 'instances.json');

function loadPeers() {
  try {
    if (!fs.existsSync(PEERS_FILE)) return [];
    return JSON.parse(fs.readFileSync(PEERS_FILE, 'utf-8'));
  } catch { return []; }
}

function savePeers(peers) {
  fs.mkdirSync(path.dirname(PEERS_FILE), { recursive: true });
  fs.writeFileSync(PEERS_FILE, JSON.stringify(peers, null, 2), 'utf-8');
}

function getSelfHost() {
  try {
    const ips = execSync('hostname -I 2>/dev/null', { encoding: 'utf-8' })
      .trim().split(/\s+/).filter(ip => ip && ip !== '127.0.0.1');
    return ips[0] || '';
  } catch { return ''; }
}

// GET /api/instances — no auth, intentionally public for cross-instance discovery
function getInstances(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.json({
    self: {
      host: getSelfHost(),
      port: config.PORT,
    },
    peers: loadPeers(),
  });
}

// POST /api/instances/register — public, no auth — used by quick-start.sh and
// cross-instance announces to add themselves without needing a token
function registerPeer(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  return addPeerInternal(req.body, res);
}

// POST /api/instances/peer — authenticated — add/update a peer from UI
function addPeer(req, res) {
  return addPeerInternal(req.body, res);
}

function addPeerInternal(body, res) {
  const { name, host, port } = body || {};
  if (!host || !port) return res.status(400).json({ error: 'host and port required' });
  const peers = loadPeers();
  const p     = parseInt(port, 10);
  const idx   = peers.findIndex(i => i.host === host && i.port === p);
  if (idx >= 0) {
    peers[idx] = { name: name || peers[idx].name || host, host, port: p };
  } else {
    peers.push({ name: name || host, host, port: p });
  }
  savePeers(peers);
  res.json({ success: true, peers });
}

// DELETE /api/instances/peer/:idx
function removePeer(req, res) {
  const idx  = parseInt(req.params.idx, 10);
  const peers = loadPeers();
  if (isNaN(idx) || idx < 0 || idx >= peers.length) {
    return res.status(404).json({ error: 'Not found' });
  }
  peers.splice(idx, 1);
  savePeers(peers);
  res.json({ success: true, peers });
}

module.exports = { getInstances, registerPeer, addPeer, removePeer };
