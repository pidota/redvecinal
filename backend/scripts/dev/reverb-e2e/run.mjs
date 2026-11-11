/**
 * E2E local: suscripción private-chat.room.{id} + evento chat.sync (sin body).
 * Entrada: variables de entorno (ver prepare-fixture.php).
 */
import Pusher from 'pusher-js';
import { readFileSync } from 'fs';

const cfgPath = process.argv[2] || process.env.REVERB_E2E_CONFIG;
if (!cfgPath) {
  console.error('Uso: node run.mjs <fixture.json>');
  process.exit(2);
}

const cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
const allowedKeys = new Set(['room_id', 'message_id', 'event_type', 'version']);

function fail(msg) {
  console.error('FAIL:', msg);
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

const channelName = `private-chat.room.${cfg.roomId}`;
const socketId = `${Math.floor(Math.random() * 1e6)}.${Math.floor(Math.random() * 1e6)}`;

const denied = await authChannel(cfg.intruderToken, channelName, socketId);
if (denied.ok) {
  fail('Usuario de otra junta obtuvo auth de canal');
}
console.log('OK: intruso denegado en /broadcasting/auth (HTTP', denied.status + ')');

const wsHost = cfg.reverbHost === 'localhost' ? '127.0.0.1' : cfg.reverbHost;

const eventPromise = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('Timeout esperando chat.sync (30s)')), 30000);

  const pusher = new Pusher(cfg.reverbKey, {
    wsHost,
    wsPort: cfg.reverbPort,
    wssPort: cfg.reverbPort,
    forceTLS: cfg.reverbScheme === 'https',
    enabledTransports: ['ws', 'wss'],
    cluster: 'mt1',
    disableStats: true,
    authEndpoint: `${cfg.appUrl}/broadcasting/auth`,
    auth: {
      headers: {
        Authorization: `Bearer ${cfg.receiverToken}`,
        Accept: 'application/json',
      },
    },
  });

  pusher.connection.bind('error', (err) => {
    clearTimeout(timeout);
    reject(err);
  });

  const ch = pusher.subscribe(channelName);
  ch.bind('pusher:subscription_error', (status) => {
    clearTimeout(timeout);
    reject(new Error('subscription_error ' + JSON.stringify(status)));
  });
  ch.bind('pusher:subscription_succeeded', async () => {
    console.log('OK: suscripción a', channelName);
    const body = `E2E WS ${Date.now()}`;
    const sendRes = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${cfg.senderToken}`,
      },
      body: JSON.stringify({ body }),
    });
    if (!sendRes.ok) {
      clearTimeout(timeout);
      reject(new Error('POST mensaje: HTTP ' + sendRes.status + ' ' + (await sendRes.text())));
      return;
    }
    const sent = await sendRes.json();
    cfg._expectedBody = body;
    cfg._sentMessageId = sent?.data?.id ?? sent?.id;
  });

  ch.bind('chat.sync', (data) => {
    clearTimeout(timeout);
    resolve({ data, pusher });
  });
});

try {
  const { data, pusher } = await eventPromise;
  const keys = Object.keys(data);
  for (const k of keys) {
    if (!allowedKeys.has(k)) {
      fail(`Payload WS contiene clave no permitida: ${k}`);
    }
  }
  if (keys.length === 0 || keys.length > 4) {
    fail('Payload WS con conjunto de claves inesperado: ' + keys.join(', '));
  }
  if ('body' in data) {
    fail('Payload WS contiene body');
  }
  console.log('OK: chat.sync recibido', JSON.stringify(data));

  const listRes = await fetch(`${cfg.appUrl}/api/v1/chat/rooms/${cfg.roomId}/messages`, {
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${cfg.receiverToken}`,
    },
  });
  if (!listRes.ok) {
    fail('GET mensajes: HTTP ' + listRes.status);
  }
  const list = await listRes.json();
  const bodies = (list.data || []).map((m) => m.body);
  if (!bodies.includes(cfg._expectedBody)) {
    fail('REST no devolvió el cuerpo del mensaje enviado');
  }
  console.log('OK: contenido recuperado solo por REST');

  if (cfg._sentMessageId && String(data.message_id) !== String(cfg._sentMessageId)) {
    fail(`message_id WS (${data.message_id}) no coincide con API (${cfg._sentMessageId})`);
  }
  console.log('OK: message_id coherente entre WS y API');

  pusher.disconnect();
  console.log('PASS: prueba WebSocket E2E completada');
  process.exit(0);
} catch (e) {
  fail(e.message || String(e));
}
