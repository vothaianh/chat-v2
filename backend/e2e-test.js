// End-to-end realtime test: register two users, create a private conversation,
// connect both via Socket.io, send a text message with an @mention, and assert
// the recipient receives it live and gets a mention event.
const { io } = require('socket.io-client');

const BASE = 'http://localhost:3000';
const API = BASE + '/api';

async function post(path, body, token) {
  const res = await fetch(API + path, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} ${res.status}: ${text}`);
  return JSON.parse(text);
}

async function get(path, token) {
  const res = await fetch(API + path, { headers: { Authorization: 'Bearer ' + token } });
  return JSON.parse(await res.text());
}

(async () => {
  const stamp = Date.now();
  const a = await post('/auth/register', {
    username: 'e2ea_' + stamp, fullName: 'E2E A', email: 'e2ea_' + stamp + '@x.com', password: 'password123',
  });
  const b = await post('/auth/register', {
    username: 'e2eb_' + stamp, fullName: 'E2E B', email: 'e2eb_' + stamp + '@x.com', password: 'password123',
  });
  console.log('registered:', a.user.username, b.user.username);

  const bUser = await get('/users/' + b.user.username, a.accessToken);
  const conv = await post('/conversations/private', { userId: bUser.id }, a.accessToken);
  console.log('conversation created:', conv.id, 'type:', conv.type);

  // Connect both sockets
  const sockA = io(BASE, { transports: ['websocket'], auth: { token: a.accessToken } });
  const sockB = io(BASE, { transports: ['websocket'], auth: { token: b.accessToken } });

  await Promise.all([
    new Promise((r) => sockA.on('connect', r)),
    new Promise((r) => sockB.on('connect', r)),
  ]);
  console.log('both sockets connected');
  // Give the server's async handleConnection (auto-join rooms) time to complete.
  await new Promise((r) => setTimeout(r, 500));

  let receivedNew = false, receivedMention = false, gotAck = false;
  const received = {};
  sockB.on('message:new', (m) => { received.new = m; receivedNew = true; console.log('B got message:new:', m.type, JSON.stringify(m.text)); });
  sockB.on('mention:new', (m) => { received.mention = m; receivedMention = true; console.log('B got mention:new for @', m.username); });
  sockA.on('message:ack', (m) => { gotAck = true; console.log('A got ack:', m.id); });

  // A sends a message mentioning B
  sockA.emit('message:send', {
    conversationId: conv.id,
    type: 'text',
    text: 'hey @' + b.user.username + ' check this out',
    clientId: 'msg-' + stamp,
  });

  // Also test a sticker
  sockA.emit('message:send', {
    conversationId: conv.id,
    type: 'sticker',
    media: '😀',
    clientId: 'stk-' + stamp,
  });

  // wait for delivery
  await new Promise((r) => setTimeout(r, 800));

  console.log('\n=== RESULTS ===');
  console.log('message:ack received by A:', gotAck);
  console.log('message:new received by B:', receivedNew);
  console.log('mention:new received by B:', receivedMention);
  console.log('sticker delivered:', received.new && received.new.type === 'text' ? '(text first, sticker next expected)' : received.new?.type);
  console.log('B received text matches:', received.new && received.new.text && received.new.text.includes('@' + b.user.username));

  // Verify NO persistence: the message should not appear in any conversation REST response.
  const convs = await get('/conversations', a.accessToken);
  const stillThere = JSON.stringify(convs).includes('hey @' + b.user.username);
  console.log('message persisted anywhere (should be false):', stillThere);

  sockA.disconnect(); sockB.disconnect();
  const ok = gotAck && receivedNew && receivedMention && !stillThere;
  console.log('\n' + (ok ? 'PASS ✅' : 'FAIL ❌'));
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error('ERR', e); process.exit(1); });