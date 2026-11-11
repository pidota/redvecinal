/**
 * Validación E2E Reverb — 10 escenarios + revocación (desarrollo local).
 * Uso: node run-all-scenarios.mjs fixture.json
 */
import Pusher from 'pusher-js';
import { readFileSync } from 'fs';
import { randomUUID } from 'crypto';
import { execSync } from 'child_process';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const scriptDir = dirname(fileURLToPath(import.meta.url));

const cfgPath = process.argv[2] || process.env.REVERB_E2E_CONFIG;
if (!cfgPath) {
  console.error('Uso: node run-all-scenarios.mjs <fixture.json>');
  process.exit(2);
}

const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const allowedKeys = new Set(['room_id', 'message_id', 'event_type', 'version']);
const results = [];

function record(id, name, status, evidence) {
  results.push({ id, name, status, evidence });
  const tag = status === 'PASS' ? 'OK' : status === 'FAIL' ? 'FAIL' : 'SKIP';
  console.log(`[${tag}] ${id}: ${name} — ${evidence}`);
}

function failGlobal(msg) {
  console.error('ABORT:', msg);
  process.exit(1);
}

async function authChannel(token, channel, socketId) {
  const res = await fetch(`${cfg.appUrl}/broadcasting/auth`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ channel_name: channel, socket_id: socketId }),
  });
  return { ok: res.ok, status: res.status, body: await res.text() };
}

function wsHost() {
  return cfg.reverbHost === 'localhost' ? '127.0.0.1' : cfg.reverbHost;
}

function makePusher(token) {
  return new Pusher(cfg.reverbKey, {
    wsHost: wsHost(),
    wsPort: cfg.reverbPort,
    wssPort: cfg.reverbPort,
    forceTLS: cfg.reverbScheme === 'https',
    enabledTransports: ['ws', 'wss'],
    cluster: 'mt1',
    disableStats: true,
    authEndpoint: `${cfg.appUrl}/broadcasting/auth`,
    auth: {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
    },
  });
}

function waitForConnected(pusher, ms = 15000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout conexión WS')), ms);
    if (pusher.connection.state === 'connected') {
      clearTimeout(t);
      resolve();
      return;
    }
    pusher.connection.bind('connected', () => {
      clearTimeout(t);
      resolve();
    });
    pusher.connection.bind('error', (err) => {
      clearTimeout(t);
      reject(err);
    });
  });
}

function waitForSubscription(channel, ms = 15000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout suscripción')), ms);
    channel.bind('pusher:subscription_succeeded', () => {
      clearTimeout(t);
      resolve();
    });
    channel.bind('pusher:subscription_error', (status) => {
      clearTimeout(t);
      reject(new Error('subscription_error ' + JSON.stringify(status)));
    });
  });
}

function waitForChatSync(channel, ms = 35000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout chat.sync')), ms);
    channel.bind('chat.sync', (data) => {
      clearTimeout(t);
      resolve(data);
    });
  });
}

function validatePayload(data) {
  const keys = Object.keys(data);
  for (const k of keys) {
    if (!allowedKeys.has(k)) return `clave no permitida: ${k}`;
  }
  if (keys.length === 0 || keys.length > 4) return 'conjunto de claves inesperado';
  if ('body' in data) return 'contiene body';
  return null;
}

const channelName = `private-chat.room.${cfg.roomId}`;
const socketId = () => `${Math.floor(Math.random() * 1e6)}.${Math.floor(Math.random() * 1e6)}`;

// --- Escenario 4, 5, 6 (solo HTTP auth) ---
const b1Auth = await authChannel(cfg.b1Token, channelName, socketId());
record(
  '4',
  'Aislamiento entre juntas (B1)',
  b1Auth.ok ? 'FAIL' : 'PASS',
  `HTTP ${b1Auth.status}`,
);

const c1Auth = await authChannel(cfg.c1Token, channelName, socketId());
record(
  '5',
  'Aislamiento municipal (C1)',
  c1Auth.ok ? 'FAIL' : 'PASS',
  `HTTP ${c1Auth.status}`,
);

const a3Auth = await authChannel(cfg.a3SuspendedToken, channelName, socketId());
record(
  '6',
  'Usuario suspendido (A3)',
  a3Auth.ok ? 'FAIL' : 'PASS',
  `HTTP ${a3Auth.status}`,
);

// --- Escenarios 1–3, 7: conexión, recepción, REST, payload ---
const pusherA2 = makePusher(cfg.a2Token);
try {
  await waitForConnected(pusherA2);
  record('1', 'Conexión WebSocket A2', 'PASS', `estado ${pusherA2.connection.state}`);

  const ch = pusherA2.subscribe(channelName);
  await waitForSubscription(ch);
  record('1b', 'Canal privado autorizado A2', 'PASS', channelName);

  const syncPromise = waitForChatSync(ch);
  const body = `E2E WS escenarios ${Date.now()}`;
  const sendRes = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.a1Token}`,
    },
    body: JSON.stringify({ body }),
  });
  if (!sendRes.ok) failGlobal('POST mensaje A1: HTTP ' + sendRes.status);
  const sent = await sendRes.json();
  const sentId = sent?.data?.id ?? sent?.id;

  const syncData = await syncPromise;
  record('2', 'Recepción chat.sync en A2', 'PASS', JSON.stringify(syncData));

  const payloadErr = validatePayload(syncData);
  record('7', 'Payload seguro', payloadErr ? 'FAIL' : 'PASS', payloadErr || `claves: ${Object.keys(syncData).join(',')}`);

  const listRes = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    headers: { Accept: 'application/json', Authorization: `Bearer ${cfg.a2Token}` },
  });
  const list = await listRes.json();
  const found = (list.data || []).some((m) => m.body === body);
  record(
    '3',
    'Contenido vía REST',
    found ? 'PASS' : 'FAIL',
    found ? `message_id API ${sentId}` : 'cuerpo no encontrado',
  );

  if (String(syncData.message_id) !== String(sentId)) {
    record('2b', 'Coherencia message_id', 'FAIL', `${syncData.message_id} vs ${sentId}`);
  }

  // --- Escenario 8: idempotencia (conteo explícito antes/después de cada POST) ---
  const clientId = randomUUID();
  const idemBody = `E2E idempotent ${Date.now()}`;
  const idemCreatedEvents = [];
  const idemHandler = (data) => {
    if (data?.event_type === 'message_created') {
      idemCreatedEvents.push(data);
    }
  };
  ch.bind('chat.sync', idemHandler);

  const countBeforeIdem = idemCreatedEvents.length;

  const r1 = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.a1Token}`,
    },
    body: JSON.stringify({ body: idemBody, client_message_id: clientId }),
  });
  const deadline1 = Date.now() + 8000;
  while (idemCreatedEvents.length <= countBeforeIdem && Date.now() < deadline1) {
    await new Promise((r) => setTimeout(r, 100));
  }
  const afterFirstPost = idemCreatedEvents.length;
  const eventsAfterPost1 = afterFirstPost - countBeforeIdem;

  const r2 = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.a1Token}`,
    },
    body: JSON.stringify({ body: idemBody, client_message_id: clientId }),
  });
  await new Promise((r) => setTimeout(r, 2000));
  const eventsAfterPost2 = idemCreatedEvents.length - afterFirstPost;

  const m1 = await r1.json();
  const m2 = await r2.json();
  const id1 = m1?.data?.id ?? m1?.id;
  const id2 = m2?.data?.id ?? m2?.id;

  const listIdem = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    headers: { Accept: 'application/json', Authorization: `Bearer ${cfg.a2Token}` },
  });
  const listIdemJson = await listIdem.json();
  const rowsWithClient = (listIdemJson.data || []).filter((m) => m.client_message_id === clientId);

  const idemPass =
    id1 === id2 &&
    eventsAfterPost1 === 1 &&
    eventsAfterPost2 === 0 &&
    rowsWithClient.length === 1;
  record(
    '8',
    'Idempotencia client_message_id (D3 + WS)',
    idemPass ? 'PASS' : 'FAIL',
    `ids ${id1}/${id2}, WS +${eventsAfterPost1}/+${eventsAfterPost2} message_created, filas REST con UUID: ${rowsWithClient.length}`,
  );

  // --- Escenario 9: reconexión ---
  const beforeDisconnect = sentId;
  pusherA2.disconnect();
  await new Promise((r) => setTimeout(r, 500));
  const bodiesWhileOffline = [];
  for (let i = 0; i < 2; i++) {
    const b = `E2E offline ${i} ${Date.now()}`;
    bodiesWhileOffline.push(b);
    await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg.a1Token}`,
      },
      body: JSON.stringify({ body: b }),
    });
    await new Promise((r) => setTimeout(r, 1500));
  }

  const afterRes = await fetch(
    `${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages?after_id=${beforeDisconnect}`,
    { headers: { Accept: 'application/json', Authorization: `Bearer ${cfg.a2Token}` } },
  );
  const afterList = await afterRes.json();
  const recovered = bodiesWhileOffline.every((b) => (afterList.data || []).some((m) => m.body === b));
  record(
    '9',
    'Reconexión / recuperación REST',
    recovered ? 'PASS' : 'FAIL',
    recovered ? `${bodiesWhileOffline.length} mensajes tras after_id` : 'faltan mensajes',
  );

  // --- Etapa 6: revocación con WebSocket ya suscrito ---
  const pusherRevoke = makePusher(cfg.a2Token);
  await waitForConnected(pusherRevoke);
  const chRev = pusherRevoke.subscribe(channelName);
  await waitForSubscription(chRev);
  let eventsAfterSuspend = 0;
  chRev.bind('chat.sync', () => {
    eventsAfterSuspend += 1;
  });

  if (cfg.a2UserId && cfg.juntaAId) {
    execSync(`php suspend-member.php ${cfg.a2UserId} ${cfg.juntaAId}`, {
      cwd: scriptDir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  }

  const authAfter = await authChannel(cfg.a2Token, channelName, socketId());
  record(
    'R6a',
    'Revocación: /broadcasting/auth tras suspensión',
    authAfter.ok ? 'FAIL' : 'PASS',
    `HTTP ${authAfter.status}`,
  );

  const sendAfter = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.a2Token}`,
    },
    body: JSON.stringify({ body: 'suspendido no debe enviar' }),
  });
  record(
    'R6b',
    'Revocación: POST mensaje bloqueado',
    sendAfter.status === 422 || sendAfter.status === 403 ? 'PASS' : 'FAIL',
    `HTTP ${sendAfter.status}`,
  );

  const syncAfterSuspend = waitForChatSync(chRev);
  await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.a1Token}`,
    },
    body: JSON.stringify({ body: `E2E post-suspend ${Date.now()}` }),
  });
  try {
    const ev = await syncAfterSuspend;
    const pe = validatePayload(ev);
    record(
      'R6c',
      'WS previo autorizado sigue recibiendo sync',
      pe ? 'FAIL' : 'PASS',
      pe || 'evento recibido (sin revocación en tiempo real del socket)',
    );
  } catch {
    record(
      'R6c',
      'WS previo autorizado sigue recibiendo sync',
      'FAIL',
      'no llegó chat.sync tras suspensión (cola/reverb)',
    );
  }

  pusherRevoke.disconnect();
  pusherA2.disconnect();
} catch (e) {
  record('1', 'Conexión / flujo principal', 'FAIL', e.message || String(e));
  pusherA2.disconnect();
  failGlobal(e.message || String(e));
}

// --- Escenario 10: junta suspendida (sala solo lectura) ---
const suspendedChannel = `private-chat.room.${cfg.roomSuspendedId}`;
const susAuth = await authChannel(cfg.a2Token, suspendedChannel, socketId());
const susSend = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomSuspendedId}/messages`, {
  method: 'POST',
  headers: {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    Authorization: `Bearer ${cfg.a2Token}`,
  },
  body: JSON.stringify({ body: 'no debe enviar' }),
});
const susList = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomSuspendedId}/messages`, {
  headers: { Accept: 'application/json', Authorization: `Bearer ${cfg.a2Token}` },
});

// Política D3: solo lectura — historial + suscripción WS permitidos; escritura bloqueada.
record(
  '10',
  'Junta suspendida D3: POST envío bloqueado',
  susSend.status === 422 ? 'PASS' : 'FAIL',
  `HTTP ${susSend.status}`,
);
record(
  '10',
  'Junta suspendida D3: GET historial permitido',
  susList.ok ? 'PASS' : 'FAIL',
  `HTTP ${susList.status}`,
);
record(
  '10',
  'Junta suspendida D3: suscripción canal permitida (sync lectura)',
  susAuth.ok ? 'PASS' : 'FAIL',
  `HTTP ${susAuth.status}`,
);

console.log('\n--- Resumen ---');
for (const r of results) {
  console.log(`${r.status}\t${r.id}\t${r.name}`);
}
const failed = results.filter((r) => r.status === 'FAIL');
process.exit(failed.length ? 1 : 0);
