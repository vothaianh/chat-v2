const { io } = require('socket.io-client');
const BASE = 'http://localhost:3000'; const API = BASE + '/api';
async function post(p, b, t) {
  const r = await fetch(API + p, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) }, body: JSON.stringify(b) });
  const x = await r.text(); if (!r.ok) throw new Error(p + ' ' + r.status + ' ' + x); return JSON.parse(x);
}
async function get(p, t) { const r = await fetch(API + p, { headers: { Authorization: 'Bearer ' + t } }); return JSON.parse(await r.text()); }
(async () => {
  const s = Date.now();
  const a = await post('/auth/register', { username: 'ga_' + s, fullName: 'GA', email: 'ga_' + s + '@x.com', password: 'password123' });
  const b = await post('/auth/register', { username: 'gb_' + s, fullName: 'GB', email: 'gb_' + s + '@x.com', password: 'password123' });
  const c = await post('/auth/register', { username: 'gc_' + s, fullName: 'GC', email: 'gc_' + s + '@x.com', password: 'password123' });
  const bUser = await get('/users/' + b.user.username, a.accessToken);
  const cUser = await get('/users/' + c.user.username, a.accessToken);
  const conv = await post('/conversations/group', { title: 'Team ' + s, memberIds: [bUser.id, cUser.id] }, a.accessToken);
  console.log('group created:', conv.id, 'members:', conv.members.length, 'title:', conv.title);

  // Register FCM device tokens for the offline users B and C so the push fan-out has targets.
  await post('/devices/register', { token: 'FAKE_FCM_TOKEN_B_' + s, platform: 'android' }, b.accessToken);
  await post('/devices/register', { token: 'FAKE_FCM_TOKEN_C_' + s, platform: 'ios' }, c.accessToken);
  console.log('registered device tokens for B and C');
  // Only A connects; B and C are OFFLINE -> should trigger FCM stub push for both
  const sockA = io(BASE, { transports: ['websocket'], auth: { token: a.accessToken } });
  await new Promise(r => sockA.on('connect', r));
  await new Promise(r => setTimeout(r, 400));
  sockA.emit('message:send', { conversationId: conv.id, type: 'text', text: 'hi team @gb_' + s + ' @gc_' + s, clientId: 'm' + s });
  await new Promise(r => setTimeout(r, 1000));
  sockA.disconnect();
  console.log('DONE (offline push should have fired for B and C)');
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });