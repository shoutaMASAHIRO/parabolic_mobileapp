// server.js

// ✅ dotenv はローカルでは便利だが、prod/EC2で未インストールでも落ちないようにする
try {
  require('dotenv').config();
} catch (e) {
  console.warn('[WARN] dotenv not available (this is OK on production if env vars are set).');
}

const express = require('express');
const cors = require('cors');
const path = require('path');
const http = require('http');
const session = require('express-session');
const bcrypt = require('bcrypt');
const nodemailer = require('nodemailer');
const { Pool } = require('pg');
const { Server } = require('socket.io');
const { BollingerBands, EMA } = require('technicalindicators');
const { SSMClient, GetParametersCommand } = require('@aws-sdk/client-ssm');

const app = express();
const server = http.createServer(app);

// =====================
// Config / Env
// =====================
const PORT = process.env.PORT || 3000;

const COOKIE_SECURE = process.env.COOKIE_SECURE === 'true'; // https運用なら true
const COOKIE_SAMESITE = process.env.COOKIE_SAMESITE || (COOKIE_SECURE ? 'none' : 'lax'); // 開発時は 'none' を設定可能
const SESSION_SECRET = process.env.SESSION_SECRET || 'dev_secret_change_me';

// フロント別オリジンの場合は CORS_ORIGIN="https://example.com,https://www.example.com"
const CORS_ORIGIN = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map((s) => s.trim()).filter(Boolean)
  : null;

const corsOptions = {
  origin: CORS_ORIGIN || true,
  credentials: true,
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '1mb' }));
// ✅ フォーム送信でも req.body が入るように（400対策）
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// ✅ 静的配信（注意：__dirname 公開はセキュリティ上リスクがある。可能なら public/ や dist/ のみに）
app.use(express.static(__dirname));

// ✅ Flutterアプリ配信（/app パス）
app.use('/app', express.static(path.join(__dirname, 'parabolic_app/build/web')));
// Flutter SPAのルーティング対応
app.get('/app/*', (req, res) => {
  res.sendFile(path.join(__dirname, 'parabolic_app/build/web/index.html'));
});

const sessionMiddleware = session({
  name: 'connect.sid',
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: COOKIE_SECURE,
    sameSite: COOKIE_SAMESITE === 'false' ? false : COOKIE_SAMESITE,
    maxAge: 1000 * 60 * 60 * 24 * 14, // 14 days
  },
});

app.use(sessionMiddleware);

// =====================
// Socket.IO
// =====================
const io = new Server(server, {
  cors: { ...corsOptions, methods: ['GET', 'POST'] },
});

io.use((socket, next) => {
  // express-session を socket にも適用
  sessionMiddleware(socket.request, {}, next);
});

function userRoom(userId) {
  return `user:${userId}`;
}

io.on('connection', (socket) => {
  // クライアントが connect しただけでは room に入れない（auth_sync を待つ）
  socket.on('auth_sync', () => {
    const sess = socket.request.session;
    const uid = sess?.userId;
    if (uid) {
      socket.join(userRoom(uid));
    }
  });

  socket.on('disconnect', () => {});
});

// =====================
// DB
// =====================
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // SSL が必要な環境では env に合わせて調整
  ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined,
});

async function ensureTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      email TEXT NOT NULL,
      username TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 既存のUNIQUE制約を削除（重複を許可）
  await pool.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;`);
  await pool.query(`ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;`);

  // ✅ emails: user_id + symbol + email の3キーで独立させる（銘柄別）
  // 新規DBではこれで作成、既存DBには下の ALTER で追従させる
  await pool.query(`
    CREATE TABLE IF NOT EXISTS emails (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id) ON DELETE CASCADE,
      symbol TEXT NOT NULL DEFAULT 'GLOBAL',
      email TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // 既存のemailsが古い場合のマイグレーション（安全に実行できる形）
  await pool.query(`ALTER TABLE emails ADD COLUMN IF NOT EXISTS symbol TEXT;`);
  await pool.query(`UPDATE emails SET symbol = 'GLOBAL' WHERE symbol IS NULL;`);
  await pool.query(`ALTER TABLE emails ALTER COLUMN symbol SET DEFAULT 'GLOBAL';`);
  await pool.query(`ALTER TABLE emails ALTER COLUMN symbol SET NOT NULL;`);

  // 旧UNIQUEを落とす（存在しなければスキップ）
  await pool.query(`ALTER TABLE emails DROP CONSTRAINT IF EXISTS emails_email_key;`);
  await pool.query(`ALTER TABLE emails DROP CONSTRAINT IF EXISTS emails_user_id_email_key;`);
  await pool.query(`ALTER TABLE emails DROP CONSTRAINT IF EXISTS emails_user_id_email_uq;`);

  // ✅ (user_id, symbol, email) の UNIQUE を保証（既にあれば何もしない）
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'emails_user_symbol_email_uq'
      ) THEN
        ALTER TABLE emails
          ADD CONSTRAINT emails_user_symbol_email_uq UNIQUE (user_id, symbol, email);
      END IF;
    END$$;
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS emails_user_symbol_idx
    ON emails (user_id, symbol);
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_settings (
      user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      settings JSONB NOT NULL DEFAULT '{}'::jsonb,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // ✅ これを追加（既存DBが古くても ON CONFLICT(user_id) が必ず成立する）
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS user_settings_user_id_uq
    ON user_settings (user_id);
  `);

  // ✅ memos（server.js 側でも必ず作る）
  await pool.query(`
    CREATE TABLE IF NOT EXISTS memos (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      symbol TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await pool.query(`
    CREATE INDEX IF NOT EXISTS memos_user_symbol_updated_idx
    ON memos (user_id, symbol, updated_at DESC);
  `);

  // ✅ updated_at 自動更新トリガ（memos用）
  await pool.query(`
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.updated_at = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
  `);

  await pool.query(`DROP TRIGGER IF EXISTS update_memos_updated_at ON memos;`);
  await pool.query(`
    CREATE TRIGGER update_memos_updated_at
    BEFORE UPDATE ON memos
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  `);
}

function getSessionUserId(req) {
  return req.session?.userId ?? null;
}

function requireAuth(req, res, next) {
  const uid = getSessionUserId(req);
  if (!uid) {
    console.log('[requireAuth] Failed - no session userId. Path:', req.path);
    return res.status(401).json({ error: 'Not authenticated.' });
  }
  next();
}

function normalizeSymbol(raw, fallback = 'GLOBAL') {
  const s = String(raw ?? '').trim();
  return s ? s : fallback;
}

// =====================
// Gmail / Email (SSM or ENV)
// =====================
let transporter = null;
let gmailUserForFrom = null;

async function initMailerIfNeeded() {
  if (transporter) return;

  // SSM を使う場合
  const region = process.env.AWS_REGION;
  const ssmUserParam = process.env.SSM_GMAIL_USER_PARAM;
  const ssmPassParam = process.env.SSM_GMAIL_PASS_PARAM;

  let gmailUser = process.env.GMAIL_USER || null;
  let gmailPass = process.env.GMAIL_APP_PASSWORD || null;

  if (region && ssmUserParam && ssmPassParam) {
    try {
      const client = new SSMClient({ region });
      const cmd = new GetParametersCommand({
        Names: [ssmUserParam, ssmPassParam],
        WithDecryption: true,
      });
      const out = await client.send(cmd);

      const params = new Map();
      for (const p of out.Parameters || []) params.set(p.Name, p.Value);

      gmailUser = params.get(ssmUserParam) || gmailUser;
      gmailPass = params.get(ssmPassParam) || gmailPass;
    } catch (e) {
      console.warn('[WARN] Failed to load Gmail creds from SSM. Falling back to env if present.');
    }
  }

  if (!gmailUser || !gmailPass) {
    console.warn('[WARN] Gmail credentials are not configured. Email sending will be disabled.');
    return;
  }

  gmailUserForFrom = gmailUser;

  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: { user: gmailUser, pass: gmailPass },
  });
}

async function sendMail({ to, subject, text }) {
  await initMailerIfNeeded();
  if (!transporter) return;

  await transporter.sendMail({
    from: gmailUserForFrom,
    to,
    subject,
    text,
  });
}

// =====================
// Yahoo Finance helpers
// =====================
function pickRangeByInterval(interval) {
  // Yahoo は interval によって取得できる期間が違うのでざっくり最適化
  if (interval.endsWith('m')) return '5d';
  if (interval.endsWith('h')) return '60d';
  if (interval === '1d') return '5y';    // 日足: 5年分
  if (interval === '5d') return '10y';   // 5日足: 10年分
  if (interval === '1wk') return '10y';  // 週足: 10年分
  if (interval === '1mo') return 'max';  // 月足: 最大期間
  if (interval === '3mo') return 'max';  // 四半期足: 最大期間
  return '5y';
}

function normalizeInterval(interval) {
  return String(interval || '1d');
}

async function fetchYahooChart(ticker, interval) {
  const iv = normalizeInterval(interval);
  const range = pickRangeByInterval(iv);

  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(
    ticker
  )}?interval=${encodeURIComponent(iv)}&range=${encodeURIComponent(range)}`;

  const r = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0' } });
  if (!r.ok) throw new Error(`Yahoo chart fetch failed: HTTP ${r.status}`);
  const j = await r.json();

  const result = j?.chart?.result?.[0];
  if (!result) throw new Error('Yahoo chart: empty result');

  const timestamps = result.timestamp || [];
  const quote = result.indicators?.quote?.[0] || {};
  const opens = quote.open || [];
  const highs = quote.high || [];
  const lows = quote.low || [];
  const closes = quote.close || [];

  const candles = [];
  for (let i = 0; i < timestamps.length; i++) {
    const t = timestamps[i];
    const o = opens[i];
    const h = highs[i];
    const l = lows[i];
    const c = closes[i];
    if (t == null || o == null || h == null || l == null || c == null) continue;
    candles.push({ time: t, open: o, high: h, low: l, close: c });
  }

  candles.sort((a, b) => a.time - b.time);
  return candles;
}

function aggregateCandles(candles, targetInterval) {
  if (!candles || candles.length === 0) return [];
  const hours = parseInt(String(targetInterval).replace('h', ''), 10);
  if (!Number.isFinite(hours) || hours <= 1) return candles;

  const out = [];
  let cur = null;
  let curStart = null;

  for (const c of candles) {
    const d = new Date(c.time * 1000);
    const hour = d.getUTCHours();
    const startHour = Math.floor(hour / hours) * hours;

    const startDate = new Date(d);
    startDate.setUTCHours(startHour, 0, 0, 0);
    const start = Math.floor(startDate.getTime() / 1000);

    if (!cur || start !== curStart) {
      if (cur) out.push(cur);
      cur = { time: start, open: c.open, high: c.high, low: c.low, close: c.close };
      curStart = start;
    } else {
      cur.high = Math.max(cur.high, c.high);
      cur.low = Math.min(cur.low, c.low);
      cur.close = c.close;
    }
  }
  if (cur) out.push(cur);
  return out;
}

// 簡易キャッシュ（同一ticker/intervalを短時間に多重取得しない）
const CANDLE_CACHE = new Map(); // key => { ts, candles }
const CACHE_TTL_MS = 15_000;

async function getCandlesWithCache(ticker, interval) {
  const key = `${ticker}|${interval}`;
  const now = Date.now();
  const hit = CANDLE_CACHE.get(key);
  if (hit && now - hit.ts < CACHE_TTL_MS) return hit.candles;

  let candles;
  if (interval === '4h' || interval === '8h') {
    const base = await fetchYahooChart(ticker, '1h');
    candles = aggregateCandles(base, interval);
  } else {
    candles = await fetchYahooChart(ticker, interval);
  }

  CANDLE_CACHE.set(key, { ts: now, candles });
  return candles;
}

// =====================
// Real-time State helpers
// =====================
function nowIso() {
  return new Date().toISOString();
}

function normalizeXValue(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  if (n <= 0) return null;
  return n;
}

function ensureObj(o) {
  return o && typeof o === 'object' ? o : {};
}

function ensureRealTimeState(settings) {
  const s = ensureObj(settings);
  if (!s.realTimeState || typeof s.realTimeState !== 'object') s.realTimeState = {};
  if (!s.realTimeState.crossHistory || typeof s.realTimeState.crossHistory !== 'object') {
    s.realTimeState.crossHistory = {};
  }
  if (
    !s.realTimeState.cryptoCrossHistoryByTicker ||
    typeof s.realTimeState.cryptoCrossHistoryByTicker !== 'object'
  ) {
    s.realTimeState.cryptoCrossHistoryByTicker = {};
  }
  return s.realTimeState;
}

function ensureIntervalMap(root, interval) {
  const iv = String(interval || 'unknown');
  if (!root[iv] || typeof root[iv] !== 'object') root[iv] = {};
  return root[iv];
}

// --- USDJPY crossHistory clear helpers ---
function clearBbCrossHistory(realTimeState) {
  const ch = realTimeState?.crossHistory;
  if (!ch || typeof ch !== 'object') return;
  const bands = ['upper2', 'upper1', 'middle', 'lower1', 'lower2'];
  for (const [iv, map] of Object.entries(ch)) {
    if (!map || typeof map !== 'object') continue;
    for (const k of bands) map[k] = null;
  }
}

function clearEmaCrossHistory(realTimeState) {
  const ch = realTimeState?.crossHistory;
  if (!ch || typeof ch !== 'object') return;
  const emas = ['ema10', 'ema25', 'ema50'];
  for (const [iv, map] of Object.entries(ch)) {
    if (!map || typeof map !== 'object') continue;
    for (const k of emas) map[k] = null;
  }
}

// --- crypto crossHistory helpers ---
function ensureCryptoPerTickerState(realTimeState) {
  // cryptoCrossHistoryByTicker[ticker][interval][indicator]
  const root = realTimeState.cryptoCrossHistoryByTicker;
  if (!root || typeof root !== 'object') realTimeState.cryptoCrossHistoryByTicker = {};
  return realTimeState.cryptoCrossHistoryByTicker;
}

function clearCryptoBbHistory(realTimeState) {
  const root = realTimeState?.cryptoCrossHistoryByTicker;
  if (!root || typeof root !== 'object') return;
  const bands = ['upper2', 'upper1', 'middle', 'lower1', 'lower2'];

  for (const ticker of Object.keys(root)) {
    const byIv = root[ticker];
    if (!byIv || typeof byIv !== 'object') continue;
    for (const iv of Object.keys(byIv)) {
      const map = byIv[iv];
      if (!map || typeof map !== 'object') continue;
      for (const k of bands) {
        if (k in map) map[k] = null;
      }
    }
  }
}

function clearCryptoEmaHistory(realTimeState) {
  const root = realTimeState?.cryptoCrossHistoryByTicker;
  if (!root || typeof root !== 'object') return;

  for (const ticker of Object.keys(root)) {
    const byIv = root[ticker];
    if (!byIv || typeof byIv !== 'object') continue;
    for (const iv of Object.keys(byIv)) {
      const map = byIv[iv];
      if (!map || typeof map !== 'object') continue;

      for (const k of Object.keys(map)) {
        if (String(k).startsWith('ema')) map[k] = null;
      }
    }
  }
}

// =====================
// Settings DB helpers
// =====================
async function getUserSettings(userId) {
  const r = await pool.query('SELECT settings FROM user_settings WHERE user_id = $1', [userId]);
  return r.rows[0]?.settings || null;
}

async function upsertUserSettings(userId, settings) {
  await pool.query(
    `
    INSERT INTO user_settings (user_id, settings, updated_at)
    VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
    ON CONFLICT (user_id) DO UPDATE
      SET settings = EXCLUDED.settings,
          updated_at = CURRENT_TIMESTAMP
    `,
    [userId, JSON.stringify(settings || {})]
  );
}

// =====================
// API: Auth
// =====================
app.post('/api/auth/register', async (req, res) => {
  try {
    const { email, username, password } = req.body || {};
    if (!email || !username || !password) return res.status(400).json({ error: 'Missing fields.' });

    const hash = await bcrypt.hash(password, 10);
    const r = await pool.query(
      `INSERT INTO users (email, username, password_hash, updated_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       RETURNING id, email, username`,
      [email, username, hash]
    );

    req.session.userId = r.rows[0].id;
    return res.json({ user: r.rows[0] });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error.' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const body = req.body || {};

    // ✅ 受け取りキーのズレ吸収（400対策）
    const identifier =
      body.identifier ||
      body.emailOrUsername ||
      body.email_or_username ||
      body.loginId ||
      body.login_id ||
      body.email ||
      body.username;

    const password = body.password;

    if (!identifier || !password) return res.status(400).json({ error: 'Missing fields.' });

    const r = await pool.query(
      `SELECT id, email, username, password_hash FROM users WHERE email = $1 OR username = $1 LIMIT 1`,
      [identifier]
    );
    const u = r.rows[0];
    if (!u) return res.status(401).json({ error: 'Invalid credentials.' });

    const ok = await bcrypt.compare(password, u.password_hash);
    if (!ok) return res.status(401).json({ error: 'Invalid credentials.' });

    req.session.userId = u.id;
    return res.json({ user: { id: u.id, email: u.email, username: u.username } });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error.' });
  }
});

app.post('/api/auth/logout', (req, res) => {
  req.session.destroy(() => {
    res.json({ message: 'Logged out.' });
  });
});

app.get('/api/auth/me', async (req, res) => {
  try {
    const uid = req.session?.userId;
    if (!uid) return res.status(401).json({ error: 'Not authenticated.' });

    const r = await pool.query('SELECT id, email, username FROM users WHERE id = $1', [uid]);
    const u = r.rows[0];
    if (!u) return res.status(401).json({ error: 'Not authenticated.' });

    return res.json({ user: u });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Server error.' });
  }
});

// =====================
// API: User Settings
// =====================
app.get('/api/user/settings', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const settings = (await getUserSettings(uid)) || {};
    // client は {settings: {...}, ...raw} をマージして読むので両方返す
    return res.json({ settings, ...settings });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to load settings.' });
  }
});

app.post('/api/user/settings', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const incoming = ensureObj(req.body);

    const existing = (await getUserSettings(uid)) || {};
    const merged = { ...existing, ...incoming };

    // ✅ realTimeState は既存を引き継ぐ（incoming に含まれても安全にマージ）
    const rtExisting = ensureRealTimeState(existing);
    const rtMerged = ensureRealTimeState(merged);

    rtMerged.crossHistory = rtMerged.crossHistory || rtExisting.crossHistory || {};
    rtMerged.cryptoCrossHistoryByTicker =
      rtMerged.cryptoCrossHistoryByTicker || rtExisting.cryptoCrossHistoryByTicker || {};

    // ✅ 非表示＝判定しない + OFFにした瞬間に該当履歴だけ消す（事故防止）
    const bbEnabled = merged.areBollingerBandsVisible !== false;
    const emaEnabled = merged.areEmaVisible !== false;

    if (!bbEnabled) {
      clearBbCrossHistory(rtMerged);
      clearCryptoBbHistory(rtMerged);
    }
    if (!emaEnabled) {
      clearEmaCrossHistory(rtMerged);
      clearCryptoEmaHistory(rtMerged);
    }

    merged.realTimeState = rtMerged;

    await upsertUserSettings(uid, merged);

    // ✅ クライアントUIも即反映できるようにクリアイベントを投げる（USDJPY）
    if (!bbEnabled) {
      const bands = ['upper2', 'upper1', 'middle', 'lower1', 'lower2'];
      for (const iv of Object.keys(rtMerged.crossHistory || {})) {
        for (const b of bands) {
          io.to(userRoom(uid)).emit('cross_history_cleared', { indicatorName: b, interval: iv });
        }
      }
    }
    if (!emaEnabled) {
      const emas = ['ema10', 'ema25', 'ema50'];
      for (const iv of Object.keys(rtMerged.crossHistory || {})) {
        for (const e of emas) {
          io.to(userRoom(uid)).emit('cross_history_cleared', { indicatorName: e, interval: iv });
        }
      }
    }

    // crypto 用（現状UIはログのみ）
    if (!bbEnabled) io.to(userRoom(uid)).emit('crypto_cross_history_cleared', { cleared: true, type: 'bb' });
    if (!emaEnabled) io.to(userRoom(uid)).emit('crypto_cross_history_cleared', { cleared: true, type: 'ema' });

    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to save settings.' });
  }
});

// =====================
// API: Memos
// =====================
app.get('/api/memos/:symbol', requireAuth, async (req, res) => {
  try {
    const { symbol } = req.params;
    const userId = req.session.userId;

    const result = await pool.query(
      'SELECT id, symbol, content, created_at, updated_at FROM memos WHERE user_id = $1 AND symbol = $2 ORDER BY updated_at DESC',
      [userId, symbol]
    );

    res.json(result.rows);
  } catch (e) {
    console.error('Failed to fetch memos:', e);
    res.status(500).json({ error: 'Failed to fetch memos.' });
  }
});

app.post('/api/memos', requireAuth, async (req, res) => {
  try {
    const { symbol, content } = req.body;
    const userId = req.session.userId;

    if (!symbol || !content) {
      return res.status(400).json({ error: 'Symbol and content are required.' });
    }

    const result = await pool.query(
      'INSERT INTO memos (user_id, symbol, content) VALUES ($1, $2, $3) RETURNING id, symbol, content, created_at, updated_at',
      [userId, symbol, content]
    );

    res.status(201).json(result.rows[0]);
  } catch (e) {
    console.error('Failed to create memo:', e);
    res.status(500).json({ error: 'Failed to create memo.' });
  }
});

app.put('/api/memos/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const { content } = req.body;
    const userId = req.session.userId;

    if (!content) {
      return res.status(400).json({ error: 'Content is required.' });
    }

    const result = await pool.query(
      'UPDATE memos SET content = $1 WHERE id = $2 AND user_id = $3 RETURNING id, symbol, content, created_at, updated_at',
      [content, id, userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Memo not found or you do not have permission to edit it.' });
    }

    res.json(result.rows[0]);
  } catch (e) {
    console.error('Failed to update memo:', e);
    res.status(500).json({ error: 'Failed to update memo.' });
  }
});

app.delete('/api/memos/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.session.userId;

    const result = await pool.query('DELETE FROM memos WHERE id = $1 AND user_id = $2', [id, userId]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Memo not found or you do not have permission to delete it.' });
    }

    res.status(204).send(); // No Content
  } catch (e) {
    console.error('Failed to delete memo:', e);
    res.status(500).json({ error: 'Failed to delete memo.' });
  }
});

// =====================
// API: Email subscriptions (user + symbol scoped)
// =====================

// ✅ 追加：userの基本メール + 追加購読先（symbol別 + GLOBALも含める）をまとめて返す
async function getRecipientsForSymbol(userId, symbol) {
  const rMail = await pool.query(`SELECT email FROM users WHERE id = $1`, [userId]);
  const userEmail = rMail.rows[0]?.email || null;

  const rSubs = await pool.query(
    `SELECT email
     FROM emails
     WHERE user_id = $1 AND (symbol = $2 OR symbol = 'GLOBAL')
     ORDER BY created_at DESC, id DESC`,
    [userId, symbol]
  );
  const extra = rSubs.rows.map((z) => z.email);

  return [userEmail, ...extra].filter(Boolean);
}

// ✅ 登録（銘柄別）
app.post('/api/subscribe', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const email = String(req.body?.email ?? '').trim();
    const symbol = normalizeSymbol(req.body?.symbol, 'GLOBAL');

    if (!email || !/^\S+@\S+\.\S+$/.test(email)) return res.status(400).json({ error: 'Invalid email.' });

    await pool.query(
      `INSERT INTO emails (user_id, symbol, email)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, symbol, email) DO NOTHING`,
      [uid, symbol, email]
    );

    return res.json({ message: `登録しました。（${symbol}）` });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to subscribe.' });
  }
});

// ✅ 一覧（銘柄別） 例: /api/emails?symbol=BTC-USD
app.get('/api/emails', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const symbol = normalizeSymbol(req.query?.symbol, 'GLOBAL');

    const r = await pool.query(
      `SELECT id, email, symbol, created_at
       FROM emails
       WHERE user_id = $1 AND symbol = $2
       ORDER BY created_at DESC, id DESC`,
      [uid, symbol]
    );

    return res.json({ emails: r.rows });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to fetch emails.' });
  }
});

// ✅ 削除（銘柄別） 例: DELETE /api/emails/test%40a.com?symbol=BTC-USD
app.delete('/api/emails/:email', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const email = decodeURIComponent(req.params.email || '');
    const symbol = normalizeSymbol(req.query?.symbol, 'GLOBAL');

    const result = await pool.query(
      `DELETE FROM emails WHERE user_id = $1 AND symbol = $2 AND email = $3`,
      [uid, symbol, email]
    );

    return res.json({ message: `削除しました。（${symbol}）`, deleted: result.rowCount });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to delete email.' });
  }
});

// 手動送信ボタン（必要なら）
// 例: POST /api/send-emails { "symbol": "BTC-USD" }
app.post('/api/send-emails', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const symbol = normalizeSymbol(req.body?.symbol ?? req.query?.symbol, 'GLOBAL');

    const recipients = await getRecipientsForSymbol(uid, symbol);
    if (recipients.length === 0) return res.json({ message: '送信先がありません。' });

    await sendMail({
      to: recipients.join(','),
      subject: `Parabolic Notification (${symbol})`,
      text: 'テスト送信です。',
    });

    return res.json({ message: `メールを送信しました。（${symbol}）` });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to send emails.' });
  }
});

// =====================
// API: Mobile App Threshold Settings
// =====================

// モバイルアプリ用：閾値設定を保存
// POST /api/mobile/threshold { "symbol": "BTC-USD", "interval": "1d", "threshold": 100 }
app.post('/api/mobile/threshold', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol, interval, threshold } = req.body;

    if (!symbol || !interval) {
      return res.status(400).json({ error: 'symbol and interval are required' });
    }

    const settings = (await getUserSettings(uid)) || {};

    // crypto_x_values[symbol][interval] = threshold の形式で保存
    if (!settings.crypto_x_values || typeof settings.crypto_x_values !== 'object') {
      settings.crypto_x_values = {};
    }
    if (!settings.crypto_x_values[symbol] || typeof settings.crypto_x_values[symbol] !== 'object') {
      settings.crypto_x_values[symbol] = {};
    }

    if (threshold != null && threshold > 0) {
      settings.crypto_x_values[symbol][interval] = threshold;
    } else {
      // 閾値が0またはnullの場合は削除
      delete settings.crypto_x_values[symbol][interval];
      // 空のオブジェクトになったら銘柄ごと削除
      if (Object.keys(settings.crypto_x_values[symbol]).length === 0) {
        delete settings.crypto_x_values[symbol];
      }
    }

    await upsertUserSettings(uid, settings);

    console.log(`[MOBILE THRESHOLD] User:${uid} set ${symbol}/${interval} = ${threshold}`);
    return res.json({ ok: true, symbol, interval, threshold });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to save threshold.' });
  }
});

// モバイルアプリ用：閾値設定を取得
// GET /api/mobile/threshold?symbol=BTC-USD&interval=1d
app.get('/api/mobile/threshold', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol, interval } = req.query;

    if (!symbol) {
      return res.status(400).json({ error: 'symbol is required' });
    }

    const settings = (await getUserSettings(uid)) || {};
    const cx = ensureObj(settings.crypto_x_values);

    if (interval) {
      // 特定のインターバルの閾値を取得
      const threshold = cx[symbol]?.[interval] ?? null;
      return res.json({ symbol, interval, threshold });
    } else {
      // 銘柄のすべてのインターバルの閾値を取得
      const thresholds = cx[symbol] || {};
      return res.json({ symbol, thresholds });
    }
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to get threshold.' });
  }
});

// モバイルアプリ用：インジケーター設定を保存（銘柄ごと）
// POST /api/mobile/indicator-settings { "symbol": "BTC-USD", "areBollingerBandsVisible": true, ... }
app.post('/api/mobile/indicator-settings', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const incoming = req.body || {};
    const symbol = incoming.symbol || 'GLOBAL'; // 銘柄指定がなければGLOBAL

    const settings = (await getUserSettings(uid)) || {};

    // 銘柄ごとのインジケーター設定を初期化
    if (!settings.indicatorSettingsBySymbol) {
      settings.indicatorSettingsBySymbol = {};
    }
    if (!settings.indicatorSettingsBySymbol[symbol]) {
      settings.indicatorSettingsBySymbol[symbol] = {};
    }

    const symbolSettings = settings.indicatorSettingsBySymbol[symbol];

    // インジケーター関連の設定をマージ
    const indicatorKeys = [
      'areBollingerBandsVisible', 'areEmaVisible',
      'bbPeriod', 'bbStdDev',
      'ema1Period', 'ema2Period', 'ema3Period',
      'emailAlertsEnabled',
      // オシレーター設定
      'rsiEnabled', 'rsiPeriod',
      'macdEnabled', 'macdFast', 'macdSlow', 'macdSignal',
      'stochasticEnabled', 'stochKPeriod', 'stochDPeriod', 'stochSmooth',
      'cciEnabled', 'cciPeriod'
    ];

    for (const key of indicatorKeys) {
      if (incoming[key] !== undefined) {
        symbolSettings[key] = incoming[key];
      }
    }

    await upsertUserSettings(uid, settings);

    console.log(`[MOBILE INDICATOR SETTINGS] User:${uid} Symbol:${symbol} updated`);
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to save indicator settings.' });
  }
});

// モバイルアプリ用：インジケーター設定を取得（銘柄ごと）
// GET /api/mobile/indicator-settings?symbol=BTC-USD
app.get('/api/mobile/indicator-settings', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const symbol = req.query.symbol || 'GLOBAL';
    const settings = (await getUserSettings(uid)) || {};

    // 銘柄ごとの設定を取得（なければデフォルト値）
    const symbolSettings = settings.indicatorSettingsBySymbol?.[symbol] || {};

    return res.json({
      areBollingerBandsVisible: symbolSettings.areBollingerBandsVisible ?? false,
      areEmaVisible: symbolSettings.areEmaVisible ?? false,
      bbPeriod: symbolSettings.bbPeriod ?? 20,
      bbStdDev: symbolSettings.bbStdDev ?? 2,
      ema1Period: symbolSettings.ema1Period ?? 10,
      ema2Period: symbolSettings.ema2Period ?? 25,
      ema3Period: symbolSettings.ema3Period ?? 50,
      emailAlertsEnabled: symbolSettings.emailAlertsEnabled ?? false,
      // オシレーター設定
      rsiEnabled: symbolSettings.rsiEnabled ?? false,
      rsiPeriod: symbolSettings.rsiPeriod ?? 14,
      macdEnabled: symbolSettings.macdEnabled ?? false,
      macdFast: symbolSettings.macdFast ?? 12,
      macdSlow: symbolSettings.macdSlow ?? 26,
      macdSignal: symbolSettings.macdSignal ?? 9,
      stochasticEnabled: symbolSettings.stochasticEnabled ?? false,
      stochKPeriod: symbolSettings.stochKPeriod ?? 14,
      stochDPeriod: symbolSettings.stochDPeriod ?? 3,
      stochSmooth: symbolSettings.stochSmooth ?? 3,
      cciEnabled: symbolSettings.cciEnabled ?? false,
      cciPeriod: symbolSettings.cciPeriod ?? 20,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to get indicator settings.' });
  }
});

// モバイルアプリ用：クロス履歴を取得（サーバーで管理している履歴）
// GET /api/mobile/cross-history?symbol=BTC-USD
app.get('/api/mobile/cross-history', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol } = req.query;

    if (!symbol) {
      return res.status(400).json({ error: 'symbol is required' });
    }

    const settings = (await getUserSettings(uid)) || {};
    const rt = ensureRealTimeState(settings);
    const root = rt.cryptoCrossHistoryByTicker || {};

    const history = root[symbol] || {};
    return res.json({ symbol, history });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to get cross history.' });
  }
});

// モバイルアプリ用：クロス履歴をクリア
// DELETE /api/mobile/cross-history?symbol=BTC-USD
app.delete('/api/mobile/cross-history', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol } = req.query;

    if (!symbol) {
      return res.status(400).json({ error: 'symbol is required' });
    }

    const settings = (await getUserSettings(uid)) || {};
    const rt = ensureRealTimeState(settings);

    if (rt.cryptoCrossHistoryByTicker && rt.cryptoCrossHistoryByTicker[symbol]) {
      delete rt.cryptoCrossHistoryByTicker[symbol];
    }

    settings.realTimeState = rt;
    await upsertUserSettings(uid, settings);

    console.log(`[MOBILE CROSS HISTORY CLEAR] User:${uid} cleared ${symbol}`);
    return res.json({ ok: true, symbol });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to clear cross history.' });
  }
});

// 閾値達成メール送信（Flutterアプリ用）
// POST /api/send-threshold-email { "symbol": "BTC-USD", "subject": "...", "body": "..." }
app.post('/api/send-threshold-email', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol, subject, body } = req.body;

    if (!symbol || !subject || !body) {
      return res.status(400).json({ error: 'symbol, subject, body are required' });
    }

    const normalizedSymbol = normalizeSymbol(symbol, 'GLOBAL');
    const recipients = await getRecipientsForSymbol(uid, normalizedSymbol);

    if (recipients.length === 0) {
      return res.json({ message: '送信先がありません。', sent: false });
    }

    await sendMail({
      to: recipients.join(','),
      subject: subject,
      text: body,
    });

    console.log(`[THRESHOLD EMAIL SENT] User:${uid} for ${normalizedSymbol}`);
    return res.json({ message: `閾値達成メールを送信しました。（${normalizedSymbol}）`, sent: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to send threshold email.' });
  }
});

// テストメール送信（Flutterアプリ用）
// POST /api/test-email { "symbol": "BTC-USD" }
app.post('/api/test-email', requireAuth, async (req, res) => {
  try {
    const uid = req.session.userId;
    const { symbol } = req.body;

    const normalizedSymbol = normalizeSymbol(symbol, 'GLOBAL');
    const recipients = await getRecipientsForSymbol(uid, normalizedSymbol);

    if (recipients.length === 0) {
      return res.status(400).json({ error: '送信先メールアドレスが登録されていません。' });
    }

    const subject = `【テスト】Parabolic通知テスト (${normalizedSymbol})`;
    const body = `これはParabolicからのテストメールです。

銘柄: ${normalizedSymbol}
送信先: ${recipients.join(', ')}
送信日時: ${new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' })}

このメールが届いていれば、メール通知は正常に動作しています。`;

    await sendMail({
      to: recipients.join(','),
      subject: subject,
      text: body,
    });

    console.log(`[TEST EMAIL SENT] User:${uid} for ${normalizedSymbol}`);
    return res.json({ message: 'テストメールを送信しました。', sent: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'テストメールの送信に失敗しました。' });
  }
});

// =====================
// API: Market data (for client charts)
// =====================
app.get('/api/data', async (req, res) => {
  try {
    const ticker = req.query.ticker;
    const interval = req.query.interval || '1d';
    if (!ticker) return res.status(400).json({ error: 'ticker required' });

    const candles = await getCandlesWithCache(ticker, interval);
    const out = candles.map((c) => ({
      date: new Date(c.time * 1000).toISOString(),
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
    }));
    return res.json(out);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to fetch data.' });
  }
});

app.get('/api/usd_jpy_data', async (req, res) => {
  try {
    const interval = req.query.interval || '1d';
    const candles = await getCandlesWithCache('USDJPY=X', interval);
    const out = candles.map((c) => ({
      date: new Date(c.time * 1000).toISOString(),
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
    }));
    return res.json(out);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to fetch USDJPY data.' });
  }
});

// 現在のUSD/JPYレートを取得
app.get('/api/forex/usdjpy', async (req, res) => {
  try {
    const candles = await getCandlesWithCache('USDJPY=X', '1d');
    if (candles && candles.length > 0) {
      const latestCandle = candles[candles.length - 1];
      return res.json({ rate: latestCandle.close });
    }
    return res.status(404).json({ error: 'No rate available' });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Failed to fetch USDJPY rate.' });
  }
});

// デフォルト暗号通貨リスト
const DEFAULT_CRYPTO = [
  { symbol: 'BTC-USD', displayName: 'Bitcoin', description: 'ビットコイン' },
  { symbol: 'ETH-USD', displayName: 'Ethereum', description: 'イーサリアム' },
  { symbol: 'BCH-USD', displayName: 'Bitcoin Cash', description: 'ビットコインキャッシュ' },
  { symbol: 'SOL-USD', displayName: 'Solana', description: 'ソラナ' },
  { symbol: 'XRP-USD', displayName: 'XRP', description: 'リップル' },
  { symbol: 'DOGE-USD', displayName: 'Dogecoin', description: 'ドージコイン' },
];

// デフォルト為替リスト
const DEFAULT_FOREX = [
  { symbol: 'USDJPY=X', displayName: 'USD/JPY', description: '米ドル/円' },
  { symbol: 'EURJPY=X', displayName: 'EUR/JPY', description: 'ユーロ/円' },
  { symbol: 'GBPJPY=X', displayName: 'GBP/JPY', description: '英ポンド/円' },
  { symbol: 'AUDJPY=X', displayName: 'AUD/JPY', description: '豪ドル/円' },
  { symbol: 'EURUSD=X', displayName: 'EUR/USD', description: 'ユーロ/米ドル' },
  { symbol: 'GBPUSD=X', displayName: 'GBP/USD', description: '英ポンド/米ドル' },
  { symbol: 'AUDUSD=X', displayName: 'AUD/USD', description: '豪ドル/米ドル' },
  { symbol: 'NZDUSD=X', displayName: 'NZD/USD', description: 'NZドル/米ドル' },
];

// 暗号通貨銘柄リスト（ユーザー設定を反映）
app.get('/api/crypto/tickers', async (req, res) => {
  const userId = getSessionUserId(req);

  if (!userId) {
    return res.json(DEFAULT_CRYPTO);
  }

  try {
    const settings = await getUserSettings(userId);
    const cryptoConfig = settings?.cryptoConfig || { hiddenCrypto: [], addedCrypto: [] };
    const hiddenCrypto = cryptoConfig.hiddenCrypto || [];
    const addedCrypto = cryptoConfig.addedCrypto || [];

    const visibleDefaults = DEFAULT_CRYPTO.filter(c => !hiddenCrypto.includes(c.symbol));
    const visibleSymbols = new Set(visibleDefaults.map(c => c.symbol));
    const uniqueAdded = addedCrypto.filter(c => !visibleSymbols.has(c.symbol));

    return res.json([...visibleDefaults, ...uniqueAdded]);
  } catch (err) {
    console.error('Error getting crypto tickers:', err);
    return res.json(DEFAULT_CRYPTO);
  }
});

// 暗号通貨検索（Yahoo Finance APIを使用）
app.get('/api/crypto/search', async (req, res) => {
  const query = req.query.q;

  if (!query || query.length < 1) {
    return res.json([]);
  }

  try {
    const searchUrl = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(query)}&quotesCount=20&newsCount=0&listsCount=0&enableFuzzyQuery=false&quotesQueryId=tss_match_phrase_query`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }
    });

    if (!response.ok) {
      return res.json([]);
    }

    const data = await response.json();
    const quotes = data.quotes || [];

    // 暗号通貨のみをフィルタリング（CRYPTOCURRENCY型）
    const cryptos = quotes
      .filter(q => q.quoteType === 'CRYPTOCURRENCY')
      .map(q => ({
        symbol: q.symbol,
        displayName: q.shortname || q.longname || q.symbol.replace('-USD', ''),
        description: q.longname || q.shortname || '',
      }));

    return res.json(cryptos);
  } catch (err) {
    console.error('Crypto search error:', err);
    return res.json([]);
  }
});

// 暗号通貨を追加
app.post('/api/user/crypto-config/add', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol, displayName, description } = req.body;

  if (!symbol) {
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    const cryptoConfig = settings.cryptoConfig || { hiddenCrypto: [], addedCrypto: [] };

    const isDefault = DEFAULT_CRYPTO.some(c => c.symbol === symbol);
    if (isDefault) {
      cryptoConfig.hiddenCrypto = (cryptoConfig.hiddenCrypto || []).filter(s => s !== symbol);
    } else {
      const alreadyAdded = (cryptoConfig.addedCrypto || []).some(c => c.symbol === symbol);
      if (!alreadyAdded) {
        cryptoConfig.addedCrypto = cryptoConfig.addedCrypto || [];
        cryptoConfig.addedCrypto.push({ symbol, displayName, description });
      }
    }

    settings.cryptoConfig = cryptoConfig;
    await upsertUserSettings(userId, settings);

    return res.json({ ok: true });
  } catch (err) {
    console.error('Error adding crypto:', err);
    return res.status(500).json({ error: 'Failed to add crypto' });
  }
});

// 暗号通貨を非表示（削除）
app.post('/api/user/crypto-config/hide', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol } = req.body;

  if (!symbol) {
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    const cryptoConfig = settings.cryptoConfig || { hiddenCrypto: [], addedCrypto: [] };

    const isDefault = DEFAULT_CRYPTO.some(c => c.symbol === symbol);
    if (isDefault) {
      cryptoConfig.hiddenCrypto = cryptoConfig.hiddenCrypto || [];
      if (!cryptoConfig.hiddenCrypto.includes(symbol)) {
        cryptoConfig.hiddenCrypto.push(symbol);
      }
    }

    cryptoConfig.addedCrypto = (cryptoConfig.addedCrypto || []).filter(c => c.symbol !== symbol);

    settings.cryptoConfig = cryptoConfig;
    await upsertUserSettings(userId, settings);

    return res.json({ ok: true });
  } catch (err) {
    console.error('Error hiding crypto:', err);
    return res.status(500).json({ error: 'Failed to hide crypto' });
  }
});

// 為替銘柄リスト（ユーザー設定を反映）
app.get('/api/forex/tickers', async (req, res) => {
  const userId = getSessionUserId(req);

  if (!userId) {
    return res.json(DEFAULT_FOREX);
  }

  try {
    const settings = await getUserSettings(userId);
    const forexConfig = settings?.forexConfig || { hiddenForex: [], addedForex: [] };
    const hiddenForex = forexConfig.hiddenForex || [];
    const addedForex = forexConfig.addedForex || [];

    const visibleDefaults = DEFAULT_FOREX.filter(f => !hiddenForex.includes(f.symbol));
    const visibleSymbols = new Set(visibleDefaults.map(f => f.symbol));
    const uniqueAdded = addedForex.filter(f => !visibleSymbols.has(f.symbol));

    return res.json([...visibleDefaults, ...uniqueAdded]);
  } catch (err) {
    console.error('Error getting forex tickers:', err);
    return res.json(DEFAULT_FOREX);
  }
});

// 為替検索（Yahoo Finance APIを使用）
app.get('/api/forex/search', async (req, res) => {
  const query = req.query.q;

  if (!query || query.length < 1) {
    return res.json([]);
  }

  try {
    const searchUrl = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(query)}&quotesCount=20&newsCount=0&listsCount=0&enableFuzzyQuery=false&quotesQueryId=tss_match_phrase_query`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }
    });

    if (!response.ok) {
      return res.json([]);
    }

    const data = await response.json();
    const quotes = data.quotes || [];

    // 為替のみをフィルタリング（CURRENCY型）
    const forex = quotes
      .filter(q => q.quoteType === 'CURRENCY')
      .map(q => {
        const symbol = q.symbol;
        const pair = symbol.replace('=X', '');
        const displayName = pair.length === 6 ? `${pair.substring(0, 3)}/${pair.substring(3)}` : symbol;
        return {
          symbol: symbol,
          displayName: displayName,
          description: q.longname || q.shortname || displayName,
        };
      });

    return res.json(forex);
  } catch (err) {
    console.error('Forex search error:', err);
    return res.json([]);
  }
});

// 為替を追加
app.post('/api/user/forex-config/add', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol, displayName, description } = req.body;

  if (!symbol) {
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    const forexConfig = settings.forexConfig || { hiddenForex: [], addedForex: [] };

    const isDefault = DEFAULT_FOREX.some(f => f.symbol === symbol);
    if (isDefault) {
      forexConfig.hiddenForex = (forexConfig.hiddenForex || []).filter(s => s !== symbol);
    } else {
      const alreadyAdded = (forexConfig.addedForex || []).some(f => f.symbol === symbol);
      if (!alreadyAdded) {
        forexConfig.addedForex = forexConfig.addedForex || [];
        forexConfig.addedForex.push({ symbol, displayName, description });
      }
    }

    settings.forexConfig = forexConfig;
    await upsertUserSettings(userId, settings);

    return res.json({ ok: true });
  } catch (err) {
    console.error('Error adding forex:', err);
    return res.status(500).json({ error: 'Failed to add forex' });
  }
});

// 為替を非表示（削除）
app.post('/api/user/forex-config/hide', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol } = req.body;

  if (!symbol) {
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    const forexConfig = settings.forexConfig || { hiddenForex: [], addedForex: [] };

    const isDefault = DEFAULT_FOREX.some(f => f.symbol === symbol);
    if (isDefault) {
      forexConfig.hiddenForex = forexConfig.hiddenForex || [];
      if (!forexConfig.hiddenForex.includes(symbol)) {
        forexConfig.hiddenForex.push(symbol);
      }
    }

    forexConfig.addedForex = (forexConfig.addedForex || []).filter(f => f.symbol !== symbol);

    settings.forexConfig = forexConfig;
    await upsertUserSettings(userId, settings);

    return res.json({ ok: true });
  } catch (err) {
    console.error('Error hiding forex:', err);
    return res.status(500).json({ error: 'Failed to hide forex' });
  }
});

// デフォルト株式リスト
const DEFAULT_STOCKS = [
  // 米国株
  { symbol: 'AAPL', displayName: 'Apple', description: 'アップル (NASDAQ)' },
  { symbol: 'GOOGL', displayName: 'Alphabet', description: 'アルファベット (NASDAQ)' },
  { symbol: 'MSFT', displayName: 'Microsoft', description: 'マイクロソフト (NASDAQ)' },
  { symbol: 'AMZN', displayName: 'Amazon', description: 'アマゾン (NASDAQ)' },
  { symbol: 'TSLA', displayName: 'Tesla', description: 'テスラ (NASDAQ)' },
  { symbol: 'NVDA', displayName: 'NVIDIA', description: 'エヌビディア (NASDAQ)' },
  { symbol: 'META', displayName: 'Meta', description: 'メタ (NASDAQ)' },
  // 日本株 (東証)
  { symbol: '7203.T', displayName: 'トヨタ自動車', description: 'Toyota (東証)' },
  { symbol: '6758.T', displayName: 'ソニーG', description: 'Sony Group (東証)' },
  { symbol: '9984.T', displayName: 'ソフトバンクG', description: 'SoftBank Group (東証)' },
  { symbol: '6861.T', displayName: 'キーエンス', description: 'Keyence (東証)' },
  { symbol: '9432.T', displayName: 'NTT', description: '日本電信電話 (東証)' },
];


// 株式銘柄リスト（ユーザー設定を反映）
app.get('/api/stock/tickers', async (req, res) => {
  const userId = getSessionUserId(req);

  // 認証なしの場合はデフォルトリストを返す
  if (!userId) {
    return res.json(DEFAULT_STOCKS);
  }

  try {
    const settings = await getUserSettings(userId);
    const stockConfig = settings?.stockConfig || { hiddenStocks: [], addedStocks: [] };
    const hiddenStocks = stockConfig.hiddenStocks || [];
    const addedStocks = stockConfig.addedStocks || [];

    // デフォルトから非表示を除外
    const visibleDefaults = DEFAULT_STOCKS.filter(s => !hiddenStocks.includes(s.symbol));

    // ユーザー追加銘柄をマージ（重複防止）
    const visibleSymbols = new Set(visibleDefaults.map(s => s.symbol));
    const uniqueAdded = addedStocks.filter(s => !visibleSymbols.has(s.symbol));

    return res.json([...visibleDefaults, ...uniqueAdded]);
  } catch (err) {
    console.error('Error getting stock tickers:', err);
    return res.json(DEFAULT_STOCKS);
  }
});

// 株式検索（Yahoo Finance APIを使用）
app.get('/api/stock/search', async (req, res) => {
  const query = req.query.q;

  if (!query || query.length < 1) {
    return res.json([]);
  }

  try {
    // Yahoo Finance Search API
    const searchUrl = `https://query1.finance.yahoo.com/v1/finance/search?q=${encodeURIComponent(query)}&quotesCount=20&newsCount=0&listsCount=0&enableFuzzyQuery=false&quotesQueryId=tss_match_phrase_query`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }
    });

    if (!response.ok) {
      console.error('Yahoo Finance search failed:', response.status);
      return res.json([]);
    }

    const data = await response.json();
    const quotes = data.quotes || [];

    // 株式のみをフィルタリング（EQUITY型）し、必要な情報を整形
    const stocks = quotes
      .filter(q => q.quoteType === 'EQUITY')
      .map(q => {
        // 取引所の表示名を決定
        let exchangeLabel = q.exchange || '';
        if (q.symbol.endsWith('.T')) {
          exchangeLabel = '東証';
        } else if (exchangeLabel === 'NMS' || exchangeLabel === 'NGM') {
          exchangeLabel = 'NASDAQ';
        } else if (exchangeLabel === 'NYQ') {
          exchangeLabel = 'NYSE';
        }

        return {
          symbol: q.symbol,
          displayName: q.shortname || q.longname || q.symbol,
          description: `${q.longname || q.shortname || ''} (${exchangeLabel})`.trim(),
        };
      });

    return res.json(stocks);
  } catch (err) {
    console.error('Stock search error:', err);
    return res.json([]);
  }
});

// ユーザーの株式設定を取得
app.get('/api/user/stock-config', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  try {
    const settings = await getUserSettings(userId);
    const stockConfig = settings?.stockConfig || { hiddenStocks: [], addedStocks: [] };
    return res.json(stockConfig);
  } catch (err) {
    console.error('Error getting stock config:', err);
    return res.status(500).json({ error: 'Failed to get stock config' });
  }
});

// 株式を追加
app.post('/api/user/stock-config/add', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol, displayName, description } = req.body;

  console.log('[stock-config/add] userId:', userId, 'symbol:', symbol, 'displayName:', displayName);

  if (!symbol) {
    console.log('[stock-config/add] Error: Symbol is required');
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    console.log('[stock-config/add] Current settings:', JSON.stringify(settings?.stockConfig || {}));
    const stockConfig = settings.stockConfig || { hiddenStocks: [], addedStocks: [] };

    // デフォルトリストにある場合はhiddenStocksから削除（復元）
    const isDefault = DEFAULT_STOCKS.some(s => s.symbol === symbol);
    if (isDefault) {
      stockConfig.hiddenStocks = (stockConfig.hiddenStocks || []).filter(s => s !== symbol);
    } else {
      // 追加済みでなければ追加
      const alreadyAdded = (stockConfig.addedStocks || []).some(s => s.symbol === symbol);
      if (!alreadyAdded) {
        stockConfig.addedStocks = stockConfig.addedStocks || [];
        stockConfig.addedStocks.push({ symbol, displayName, description });
      }
    }

    settings.stockConfig = stockConfig;
    console.log('[stock-config/add] Saving settings:', JSON.stringify(settings.stockConfig));
    await upsertUserSettings(userId, settings);
    console.log('[stock-config/add] Success');

    return res.json({ ok: true });
  } catch (err) {
    console.error('[stock-config/add] Error:', err);
    return res.status(500).json({ error: 'Failed to add stock', details: err.message });
  }
});

// 株式を非表示（削除）
app.post('/api/user/stock-config/hide', requireAuth, async (req, res) => {
  const userId = getSessionUserId(req);
  const { symbol } = req.body;

  console.log('[stock-config/hide] userId:', userId, 'symbol:', symbol);

  if (!symbol) {
    console.log('[stock-config/hide] Error: Symbol is required');
    return res.status(400).json({ error: 'Symbol is required' });
  }

  try {
    const settings = await getUserSettings(userId) || {};
    console.log('[stock-config/hide] Current settings:', JSON.stringify(settings?.stockConfig || {}));
    const stockConfig = settings.stockConfig || { hiddenStocks: [], addedStocks: [] };

    // デフォルトリストにある場合はhiddenStocksに追加
    const isDefault = DEFAULT_STOCKS.some(s => s.symbol === symbol);
    if (isDefault) {
      stockConfig.hiddenStocks = stockConfig.hiddenStocks || [];
      if (!stockConfig.hiddenStocks.includes(symbol)) {
        stockConfig.hiddenStocks.push(symbol);
      }
    }

    // addedStocksから削除
    stockConfig.addedStocks = (stockConfig.addedStocks || []).filter(s => s.symbol !== symbol);

    settings.stockConfig = stockConfig;
    console.log('[stock-config/hide] Saving settings:', JSON.stringify(settings.stockConfig));
    await upsertUserSettings(userId, settings);
    console.log('[stock-config/hide] Success');

    return res.json({ ok: true });
  } catch (err) {
    console.error('[stock-config/hide] Error:', err);
    return res.status(500).json({ error: 'Failed to hide stock', details: err.message });
  }
});

// =====================
// Cross detection helpers
// =====================
function crossed(prevClose, curClose, prevLine, curLine) {
  if (![prevClose, curClose, prevLine, curLine].every((x) => Number.isFinite(x))) return false;
  const wasBelow = prevClose < prevLine;
  const isAbove = curClose >= curLine;
  const wasAbove = prevClose > prevLine;
  const isBelow = curClose <= curLine;
  return (wasBelow && isAbove) || (wasAbove && isBelow);
}

// ✅ 追加：上抜け/下抜け（方向）を判定して保存する
function crossDirection(prevClose, curClose, prevLine, curLine) {
  if (![prevClose, curClose, prevLine, curLine].every((x) => Number.isFinite(x))) return null;
  const wasBelow = prevClose < prevLine;
  const isAbove = curClose >= curLine;
  const wasAbove = prevClose > prevLine;
  const isBelow = curClose <= curLine;
  if (wasBelow && isAbove) return 'up'; // 下→上
  if (wasAbove && isBelow) return 'down'; // 上→下
  return null;
}

// ✅ 追加：indicator を人間向けに説明する（メール用）
const BB_INDICATOR_INFO = {
  upper2: { short: 'BB +2σ', long: 'ボリンジャーバンド +2σ（上側2σ）' },
  upper1: { short: 'BB +1σ', long: 'ボリンジャーバンド +1σ（上側1σ）' },
  middle: { short: 'BB 0σ', long: 'ボリンジャーバンド 0σ（中央線）' },
  lower1: { short: 'BB -1σ', long: 'ボリンジャーバンド -1σ（下側1σ）' },
  lower2: { short: 'BB -2σ', long: 'ボリンジャーバンド -2σ（下側2σ）' },
};

function indicatorInfo(indicatorKey) {
  const key = String(indicatorKey || '');
  if (BB_INDICATOR_INFO[key]) return BB_INDICATOR_INFO[key];

  const m = /^ema(\d+)$/.exec(key);
  if (m) {
    const p = Number(m[1]);
    return { short: `EMA(${p})`, long: `指数移動平均 EMA(${p})` };
  }

  return { short: key || 'unknown', long: key || 'unknown' };
}

function directionInfo(dir) {
  if (dir === 'up') return { short: '上抜け', long: '上抜け（価格が線を下から上へクロス）' };
  if (dir === 'down') return { short: '下抜け', long: '下抜け（価格が線を上から下へクロス）' };
  return { short: '不明', long: '不明（古い履歴/判定不能）' };
}

// ✅ 修正：interval 用の表示情報（short/long を揃える）
function getIntervalInfo(interval) {
  const iv = String(interval || 'unknown');
  const map = {
    '1m': { short: '1m', long: '1分足' },
    '5m': { short: '5m', long: '5分足' },
    '15m': { short: '15m', long: '15分足' },
    '30m': { short: '30m', long: '30分足' },
    '1h': { short: '1h', long: '1時間足' },
    '4h': { short: '4h', long: '4時間足' },
    '8h': { short: '8h', long: '8時間足' },
    '1d': { short: '1d', long: '日足' },
    '1wk': { short: '1wk', long: '週足' },
  };
  return map[iv] || { short: iv, long: iv };
}

// ✅ 追加：JSTで「YYYY-MM-DD HH:mm」表示（inputはISO文字列/Date/秒/ミリ秒どれでもOK）
function formatDateTimeMinuteJST(input) {
  if (input == null) return 'unknown';

  let d;
  if (input instanceof Date) {
    d = input;
  } else if (typeof input === 'number') {
    // 1e12未満なら「秒」とみなす（Unix秒）
    d = new Date(input < 1e12 ? input * 1000 : input);
  } else {
    d = new Date(input); // ISO文字列など
  }

  if (!Number.isFinite(d.getTime())) return String(input);

  const parts = new Intl.DateTimeFormat('ja-JP', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);

  const get = (type) => parts.find((p) => p.type === type)?.value ?? '';
  const y = get('year');
  const mo = get('month');
  const da = get('day');
  const hh = get('hour');
  const mm = get('minute');

  return `${y}-${mo}-${da} ${hh}:${mm} JST`;
}

// ✅ 追加：数値を小数点以下3桁程度にフォーマットする
function fmt3(n) {
  if (!Number.isFinite(n)) return String(n);
  // toFixed(3) で3桁に丸め、Number() で末尾の不要な0を消す
  return Number(n.toFixed(3));
}

// ✅ 修正：intervalInfo() ではなく getIntervalInfo() を呼ぶ
function buildThresholdEmail({ symbol, interval, indicatorKey, ev, currentPrice, diff, threshold }) {
  const ind = indicatorInfo(indicatorKey);
  const dir = directionInfo(ev?.direction);
  const iv = getIntervalInfo(interval);

  const crossedAtStr = formatDateTimeMinuteJST(ev?.timestamp);

  return {
    subject: `${symbol} Alert - ${iv.short} - ${ind.short} ${dir.short}`,
    text:
      `${symbol} がしきい値に到達しました。\n\n` +
      `【足の間隔】\n` +
      `足間隔=${iv.long}\n\n` +
      `【クロスした線】\n` +
      `指標=${ind.long}\n` +
      `方向=${dir.long}\n` +
      `クロス時刻=${crossedAtStr}\n` +
      `クロス時価格=${fmt3(ev?.price)}\n` +
      `ライン値=${fmt3(ev?.lineValue)}\n\n` +
      `【現在値】\n` +
      `現在価格=${fmt3(currentPrice)}\n` +
      `差分(|現在-クロス時|)=${fmt3(diff)}\n` +
      `しきい値=${fmt3(threshold)}\n\n` +
      `(内部キー: ${indicatorKey})`,
  };
}

function eventObj(price, interval, extra = {}) {
  return { price, interval, timestamp: nowIso(), ...extra };
}

// =====================
// J-Quants API Helpers
// =====================
let jquantsIdToken = null;

// =====================
// J-Quants API V2 Helpers
// =====================
async function fetchJQuantsV2(endpoint) {
  const apiKey = (process.env.JQUANTS_REFRESH_TOKEN || '').trim();
  if (!apiKey) {
    console.warn('[J-Quants] API Key (JQUANTS_REFRESH_TOKEN) is not set.');
    return null;
  }

  try {
    console.log(`[J-Quants V2] Fetching: ${endpoint}`);
    const r = await fetch(`https://api.jquants.com/v2${endpoint}`, {
      headers: { 'x-api-key': apiKey },
    });

    if (!r.ok) {
      const errorText = await r.text();
      console.error(`[J-Quants V2] API Error (${endpoint}): ${r.status} - ${errorText}`);
      return null;
    }
    
    const data = await r.json();
    console.log(`[J-Quants V2] Successfully fetched data from ${endpoint}`);
    return data;
  } catch (e) {
    console.error(`[J-Quants V2] Fetch Exception (${endpoint}):`, e);
    return null;
  }
}

// =====================
// API: Stock Analysis
// =====================
app.get('/api/stock/analysis', async (req, res) => {
  const { symbol } = req.query;
  console.log(`[Analysis API] Request received for: ${symbol}`);
  if (!symbol) return res.status(400).json({ error: 'symbol required' });

  if (symbol.endsWith('.T')) {
    const code = symbol.replace('.T', '');
    try {
      console.log(`[J-Quants V2] Processing analysis for code: ${code}`);
      
      // V2 では財務情報は /equities/statements
      // 銘柄詳細は /markets/listed_info
      const [statements, listedInfo] = await Promise.all([
        fetchJQuantsV2(`/equities/statements?code=${code}`),
        fetchJQuantsV2(`/markets/listed_info?code=${code}`),
      ]);

      if (statements && (statements.statements || statements.data) && (statements.statements || statements.data).length > 0) {
        const rawList = statements.statements || statements.data;
        console.log(`[J-Quants V2] Found ${rawList.length} statements for ${code}`);
        
        const sortedStatements = rawList.sort((a, b) => 
          new Date(b.DiscloseDate || b.date) - new Date(a.DiscloseDate || a.date)
        );
        const latest = sortedStatements[0];
        const infoList = listedInfo?.info || listedInfo?.data || [];
        const info = infoList[0] || {};

        console.log(`[J-Quants V2] Data construction successful for ${symbol}`);

        return res.json({
          morningstarRating: `市場: ${info.MarketCodeName || info.market_name || '不明'}`,
          analystRating: `セクター: ${info.SectorName33 || info.sector33_name || '不明'}\n区分: ${info.SectorName17 || info.sector17_name || '不明'}`,
          earnings: `決算発表: ${latest.DiscloseDate || latest.date}\n売上高: ${Number(latest.NetSales || latest.net_sales || 0).toLocaleString()}円`,
          performance: `営業利益: ${Number(latest.OperatingProfit || latest.operating_profit || 0).toLocaleString()}円\nEPS: ${latest.EarningsPerShare || latest.eps || 0}円`,
          valuation: `自己資本比率: ${latest.EquityToAssetRatio || latest.equity_to_asset_ratio || 0}%\n純利益: ${Number(latest.Profit || latest.profit || 0).toLocaleString()}円`,
          revenueComposition: `会社名: ${info.CompanyName || info.company_name || symbol}\n${info.SectorName17 || info.sector17_name || ''}`,
          rawJQuants: { latest, info }
        });
      } else {
        console.warn(`[J-Quants V2] No data found for ${code}`);
      }
    } catch (e) {
      console.error('[Analysis API] J-Quants error:', e);
    }
  }

  console.log(`[Analysis API] Final fallback for ${symbol}. Returning null.`);
  res.json(null);
});

// =====================
// Watchers (USDJPY + Crypto)
// =====================
async function processUsdJpyForUser(userId, settings) {
  const rt = ensureRealTimeState(settings);

  // 閾値が設定されているすべてのインターバルを取得
  const intervalsToWatch = Object.keys(ensureObj(settings.x_values));
  if (intervalsToWatch.length === 0) {
    return; // 監視対象がなければ何もしない
  }

  const bbEnabled = settings.areBollingerBandsVisible !== false;
  const emaEnabled = settings.areEmaVisible !== false;
  const emailEnabled = settings.emailAlertsEnabled !== false;

  // 取得した各インターバルに対してループ処理
  for (const iv of intervalsToWatch) {
    try {
      const crossHistory = rt.crossHistory;
      const ivMap = ensureIntervalMap(crossHistory, iv);

      const candles = await getCandlesWithCache('USDJPY=X', iv);
      if (!candles || candles.length < 30) {
        continue; // データが不十分なら次のインターバルへ
      }

      const closes = candles.map((c) => c.close);
      const prevClose = closes[closes.length - 2];
      const curClose = closes[closes.length - 1];

      // price update (UIの現在値更新用) - 最初のインターバルでのみ実行（負荷軽減）
      if (intervalsToWatch.indexOf(iv) === 0) {
        io.to(userRoom(userId)).emit('usd_jpy_price_update', { price: curClose });
      }

      // ---- BB cross ----
      if (bbEnabled) {
        const bbPeriod = parseInt(settings.bbPeriod, 10) || 20;
        const bbStdDev = Number(settings.bbStdDev) || 2;
        const bb1 = BollingerBands.calculate({ period: bbPeriod, values: closes, stdDev: 1 });
        const bb2 = BollingerBands.calculate({ period: bbPeriod, values: closes, stdDev: bbStdDev });

        if (bb1.length >= 2 && bb2.length >= 2) {
          const prevIdx = bb1.length - 2;
          const curIdx = bb1.length - 1;
          const checks = [
            { key: 'upper2', prev: bb2[prevIdx].upper, cur: bb2[curIdx].upper, label: '+2σ' },
            { key: 'upper1', prev: bb1[prevIdx].upper, cur: bb1[curIdx].upper, label: '+1σ' },
            { key: 'middle', prev: bb1[prevIdx].middle, cur: bb1[curIdx].middle, label: '0σ' },
            { key: 'lower1', prev: bb1[prevIdx].lower, cur: bb1[curIdx].lower, label: '-1σ' },
            { key: 'lower2', prev: bb2[prevIdx].lower, cur: bb2[curIdx].lower, label: '-2σ' },
          ];

          for (const x of checks) {
            if (crossed(prevClose, curClose, x.prev, x.cur)) {
              const dir = crossDirection(prevClose, curClose, x.prev, x.cur);
              ivMap[x.key] = eventObj(curClose, iv, { direction: dir, lineValue: x.cur });
              io.to(userRoom(userId)).emit('bb_cross', {
                bandName: x.key,
                interval: iv,
                price: curClose,
                timestamp: ivMap[x.key].timestamp,
                message: `USD/JPY: 価格がBB ${x.label} をクロスしました (${iv})`,
              });
            }
          }
        }
      }

      // ---- EMA cross ----
      if (emaEnabled) {
        const emaPeriods = [
          parseInt(settings.ema1Period, 10) || 10,
          parseInt(settings.ema2Period, 10) || 25,
          parseInt(settings.ema3Period, 10) || 50,
        ];
        for (const p of emaPeriods) {
          const ema = EMA.calculate({ period: p, values: closes, exact: false });
          if (ema.length < 2) continue;
          const prevE = ema[ema.length - 2];
          const curE = ema[ema.length - 1];
          if (crossed(prevClose, curClose, prevE, curE)) {
            const key = `ema${p}`;
            const dir = crossDirection(prevClose, curClose, prevE, curE);
            ivMap[key] = eventObj(curClose, iv, { direction: dir, lineValue: curE });
            io.to(userRoom(userId)).emit('ema_cross', {
              emaName: key,
              interval: iv,
              price: curClose,
              timestamp: ivMap[key].timestamp,
              message: `USD/JPY: 価格がEMA(${p})をクロスしました (${iv})`,
            });
          }
        }
      }

      // ---- Threshold email + clear ----
      if (emailEnabled) {
        const x = normalizeXValue(settings.x_values?.[iv]);
        if (x != null) {
          const recipients = await getRecipientsForSymbol(userId, 'USDJPY=X');
          if (recipients.length > 0) {
            for (const [name, ev] of Object.entries(ivMap || {})) {
              if (!ev || typeof ev !== 'object' || !Number.isFinite(ev.price) || ev.interval !== iv) continue;

              const isEma = String(name).startsWith('ema');
              if ((isEma && !emaEnabled) || (!isEma && !bbEnabled)) continue;

              const diff = Math.abs(curClose - ev.price);
              if (diff >= x) {
                console.log(`[EMAIL SENT] User:${userId} for ${name}(${iv})`); // メール送信ログ
                const mail = buildThresholdEmail({
                  symbol: 'USD/JPY',
                  interval: iv,
                  indicatorKey: name,
                  ev,
                  currentPrice: curClose,
                  diff,
                  threshold: x,
                });
                await sendMail({ to: recipients.join(','), subject: mail.subject, text: mail.text });
                ivMap[name] = null;
                io.to(userRoom(userId)).emit('cross_history_cleared', { indicatorName: name, interval: iv });
              }
            }
          }
        }
      }
    } catch (e) {
      console.error(`[processUsdJpyForUser] Error during processing interval '${iv}' for user ${userId}:`, e);
    }
  }

  // すべてのインターバルの処理が終わった後で、変更をDBに保存
  settings.realTimeState = rt;
  await upsertUserSettings(userId, settings);
}

async function processCryptoForUser(userId, settings) {
  const rt = ensureRealTimeState(settings);
  const root = ensureCryptoPerTickerState(rt);
  const cx = ensureObj(settings.crypto_x_values);

  const tickersToWatch = Object.keys(cx);
  if (tickersToWatch.length === 0) {
    return; // 監視対象がなければ何もしない
  }

  const bbEnabled = settings.areBollingerBandsVisible !== false;
  const emaEnabled = settings.areEmaVisible !== false;
  const emailEnabled = settings.emailAlertsEnabled !== false;

  for (const ticker of tickersToWatch) {
    const intervalsToWatch = Object.keys(ensureObj(cx[ticker]));
    if (intervalsToWatch.length === 0) {
      continue;
    }

    for (const iv of intervalsToWatch) {
      try {
        if (!root[ticker] || typeof root[ticker] !== 'object') root[ticker] = {};
        const byIv = root[ticker];
        const ivMap = ensureIntervalMap(byIv, iv);

        const candles = await getCandlesWithCache(ticker, iv);
        if (!candles || candles.length < 30) {
          continue;
        }

        const closes = candles.map((c) => c.close);
        const prevClose = closes[closes.length - 2];
        const curClose = closes[closes.length - 1];

        // ---- BB cross ----
        if (bbEnabled) {
          const bbPeriod = parseInt(settings.bbPeriod, 10) || 20;
          const bbStdDev = Number(settings.bbStdDev) || 2;
          const bb1 = BollingerBands.calculate({ period: bbPeriod, values: closes, stdDev: 1 });
          const bb2 = BollingerBands.calculate({ period: bbPeriod, values: closes, stdDev: bbStdDev });

          if (bb1.length >= 2 && bb2.length >= 2) {
            const checks = [
              { key: 'upper2', prev: bb2[bb1.length - 2].upper, cur: bb2[bb1.length - 1].upper, label: '+2σ' },
              { key: 'upper1', prev: bb1[bb1.length - 2].upper, cur: bb1[bb1.length - 1].upper, label: '+1σ' },
              { key: 'middle', prev: bb1[bb1.length - 2].middle, cur: bb1[bb1.length - 1].middle, label: '0σ' },
              { key: 'lower1', prev: bb1[bb1.length - 2].lower, cur: bb1[bb1.length - 1].lower, label: '-1σ' },
              { key: 'lower2', prev: bb2[bb1.length - 2].lower, cur: bb2[bb1.length - 1].lower, label: '-2σ' },
            ];
            for (const x of checks) {
              if (crossed(prevClose, curClose, x.prev, x.cur)) {
                const dir = crossDirection(prevClose, curClose, x.prev, x.cur);
                ivMap[x.key] = eventObj(curClose, iv, { direction: dir, lineValue: x.cur });
                io.to(userRoom(userId)).emit('crypto_bb_cross', {
                  ticker,
                  bandName: x.key,
                  interval: iv,
                  price: curClose,
                  timestamp: ivMap[x.key].timestamp,
                  message: `${ticker}: 価格がBB ${x.label} をクロスしました (${iv})`,
                });
              }
            }
          }
        }

        // ---- EMA cross ----
        if (emaEnabled) {
          const emaPeriods = [
            parseInt(settings.ema1Period, 10) || 10,
            parseInt(settings.ema2Period, 10) || 25,
            parseInt(settings.ema3Period, 10) || 50,
          ];
          for (const p of emaPeriods) {
            const ema = EMA.calculate({ period: p, values: closes, exact: false });
            if (ema.length < 2) continue;
            const prevE = ema[ema.length - 2];
            const curE = ema[ema.length - 1];
            if (crossed(prevClose, curClose, prevE, curE)) {
              const key = `ema${p}`;
              const dir = crossDirection(prevClose, curClose, prevE, curE);
              ivMap[key] = eventObj(curClose, iv, { direction: dir, lineValue: curE });
              io.to(userRoom(userId)).emit('crypto_ema_cross', {
                ticker,
                emaName: key,
                interval: iv,
                price: curClose,
                timestamp: ivMap[key].timestamp,
                message: `${ticker}: 価格がEMA(${p})をクロスしました (${iv})`,
              });
            }
          }
        }

        // ---- Threshold email + clear ----
        if (emailEnabled) {
          const threshold = normalizeXValue(cx?.[ticker]?.[iv]);
          if (threshold != null) {
            const recipients = await getRecipientsForSymbol(userId, ticker);
            if (recipients.length > 0) {
              for (const [name, ev] of Object.entries(ivMap || {})) {
                if (!ev || typeof ev !== 'object' || !Number.isFinite(ev.price) || ev.interval !== iv) continue;
                
                const isEma = String(name).startsWith('ema');
                if ((isEma && !emaEnabled) || (!isEma && !bbEnabled)) continue;

                const diff = Math.abs(curClose - ev.price);
                if (diff >= threshold) {
                  console.log(`[EMAIL SENT] User:${userId} for ${ticker} ${name}(${iv})`); // メール送信ログ
                  const mail = buildThresholdEmail({
                    symbol: ticker,
                    interval: iv,
                    indicatorKey: name,
                    ev,
                    currentPrice: curClose,
                    diff,
                    threshold,
                  });
                  await sendMail({ to: recipients.join(','), subject: mail.subject, text: mail.text });
                  ivMap[name] = null;
                  io.to(userRoom(userId)).emit('crypto_cross_history_cleared', {
                    ticker,
                    interval: iv,
                    indicatorName: name,
                  });
                }
              }
            }
          }
        }
      } catch (e) {
        console.error(`[processCryptoForUser] Error processing ${ticker}/${iv} for user ${userId}:`, e);
      }
    }
  }

  // すべての処理が終わった後で、変更をDBに保存
  settings.realTimeState = rt;
  await upsertUserSettings(userId, settings);
}

async function watcherTick() {
  try {
    const r = await pool.query(
      `SELECT u.id AS user_id, s.settings
       FROM users u
       LEFT JOIN user_settings s ON s.user_id = u.id`
    );

    for (const row of r.rows) {
      const userId = row.user_id;
      const settings = ensureObj(row.settings);

      // realTimeState を必ず初期化しておく
      ensureRealTimeState(settings);

      // USDJPY は x_values がある or dataType が usd_jpy の時に動かす
      const hasUsdX =
        settings.x_values && typeof settings.x_values === 'object' && Object.keys(settings.x_values).length > 0;
      const wantsUsd = settings.currentDataType === 'usd_jpy' || hasUsdX;
      if (wantsUsd) {
        await processUsdJpyForUser(userId, settings);
      }

      // crypto は crypto_x_values がある or dataType が crypto の時に動かす
      const hasCryptoX =
        settings.crypto_x_values &&
        typeof settings.crypto_x_values === 'object' &&
        Object.keys(settings.crypto_x_values).length > 0;
      const wantsCrypto = settings.currentDataType === 'crypto' || hasCryptoX;
      if (wantsCrypto) {
        await processCryptoForUser(userId, settings);
      }
    }
  } catch (e) {
    console.error('[watcherTick] error:', e);
  }
}

let watcherStarted = false;
function startWatchers() {
  if (watcherStarted) return;
  watcherStarted = true;

  // 15秒おき（必要なら調整）
  setInterval(watcherTick, 15_000);
}

// =====================
// Boot
// =====================
(async () => {
  try {
    await ensureTables();
    startWatchers();
    server.listen(PORT, () => {
      console.log(`Server listening on :${PORT}`);
    });
  } catch (e) {
    console.error('Failed to boot server:', e);
    process.exit(1);
  }
})();
