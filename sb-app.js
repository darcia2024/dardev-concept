/* =============================================================================
   Barber Membership & Loyalty — Lapisan Data Bersama (Supabase)
   Dipakai oleh pos.html (kasir) dan rekap.html (owner).

   Kunci di bawah adalah PUBLISHABLE key: memang dirancang untuk publik dan
   aman berada di HTML. Yang menjaga data adalah Row Level Security di
   database — tanpa login, seluruh tabel mengembalikan kosong dan setiap
   penulisan ditolak. Jangan pernah menaruh service_role / secret key di sini.
   ============================================================================= */

const SB_URL = 'https://grzjfnqljjzjkvmgtohe.supabase.co';
const SB_KEY = 'sb_publishable_AzRYnslGL0V71KfhQ1tRBg_5wLjfQ6I';

const sb = window.supabase.createClient(SB_URL, SB_KEY, {
  auth: {
    persistSession: true,      // kasir tidak perlu login ulang tiap buka
    autoRefreshToken: true,
    storageKey: 'barber_auth_v1'
  }
});

/* ---------------------------------------------------------------------------
   STATUS KONEKSI
   --------------------------------------------------------------------------- */

const SBConn = {
  online: navigator.onLine,
  listeners: [],
  onChange(fn) { this.listeners.push(fn); fn(this.online); },
  set(v) {
    if (this.online === v) return;
    this.online = v;
    this.listeners.forEach(fn => fn(v));
  }
};

window.addEventListener('online',  () => SBConn.set(true));
window.addEventListener('offline', () => SBConn.set(false));

/* ---------------------------------------------------------------------------
   GERBANG LOGIN
   Overlay disuntikkan lewat JS agar kedua halaman memakai tampilan yang sama.
   --------------------------------------------------------------------------- */

const SB_LOGIN_CSS = `
  .sb-auth-backdrop {
    position: fixed; inset: 0; z-index: 9999;
    background: var(--bg, #F4F5F7);
    display: none; align-items: center; justify-content: center; padding: 20px;
  }
  .sb-auth-backdrop.is-open { display: flex; }
  .sb-auth-card {
    width: 100%; max-width: 380px;
    background: var(--surface, #FFFFFF);
    border: 1px solid var(--border, #E1E5EA);
    border-radius: var(--r-lg, 18px);
    padding: 28px 26px;
    display: flex; flex-direction: column; gap: 16px;
    box-shadow: var(--shadow-lg, 0 18px 44px rgba(22,24,28,.10));
  }
  .sb-auth-brand { display: flex; align-items: center; gap: 11px; }
  .sb-auth-logo { height: 26px; width: auto; flex: none; display: block; }
  .sb-auth-title { font-size: 16px; font-weight: 600; color: var(--text, #16181C); line-height: 1.25; }
  .sb-auth-sub { font-size: 12px; color: var(--text-dim, #767D87); margin-top: 2px; }
  .sb-auth-field { display: flex; flex-direction: column; gap: 6px; }
  .sb-auth-label {
    font-family: var(--mono, monospace); font-size: 10.5px; letter-spacing: .12em;
    text-transform: uppercase; color: var(--text-dim, #767D87);
  }
  .sb-auth-card input {
    background: var(--surface-sunk, #EDEFF2); border: 1px solid var(--border, #E1E5EA);
    border-radius: var(--r-sm, 6px); color: var(--text, #16181C);
    padding: 11px 13px; font-size: 14.5px; font-family: inherit; outline: none; width: 100%;
  }
  .sb-auth-card input:focus { border-color: var(--brand, #BE0000); }
  .sb-auth-btn {
    background: var(--brand, #BE0000); color: #fff;
    border: none; border-radius: var(--r-sm, 6px);
    padding: 12px; font-size: 14px; font-weight: 600; font-family: inherit;
    cursor: pointer; transition: opacity .15s ease;
  }
  .sb-auth-btn:disabled { opacity: .55; cursor: default; }
  .sb-auth-err {
    font-size: 12.5px; color: var(--brand, #BE0000); line-height: 1.45;
    background: var(--brand-wash, rgba(190,0,0,.055));
    border: 1px solid var(--brand, #BE0000); border-radius: var(--r-sm, 6px);
    padding: 9px 11px;
  }
  .sb-auth-err[hidden] { display: none; }
  .sb-conn-pill {
    display: inline-flex; align-items: center; gap: 6px;
    font-family: var(--mono, monospace); font-size: 10.5px; letter-spacing: .08em;
    padding: 4px 9px; border-radius: 99px; border: 1px solid var(--border, #E1E5EA);
    color: var(--text-dim, #767D87); white-space: nowrap;
  }
  .sb-conn-pill.is-online { color: var(--ok, #0F7355); border-color: var(--ok, #0F7355); }
  .sb-conn-pill.is-offline { color: var(--brand, #BE0000); border-color: var(--brand, #BE0000); }
  .sb-conn-pill.is-pending { color: var(--warn, #8A5A00); border-color: var(--warn, #8A5A00); }
`;

function sbInjectAuthUI(subtitle) {
  const style = document.createElement('style');
  style.textContent = SB_LOGIN_CSS;
  document.head.appendChild(style);

  const el = document.createElement('div');
  el.className = 'sb-auth-backdrop';
  el.id = 'sbAuthBackdrop';
  el.innerHTML = `
    <form class="sb-auth-card" id="sbAuthForm" autocomplete="on">
      <div class="sb-auth-brand">
        <img src="assets/logo.png" alt="Underrated Barbershop" class="sb-auth-logo" />
        <div>
          <div class="sb-auth-title">Masuk untuk melanjutkan</div>
          <div class="sb-auth-sub">${subtitle}</div>
        </div>
      </div>
      <div class="sb-auth-field">
        <label class="sb-auth-label" for="sbAuthEmail">Email</label>
        <input type="email" id="sbAuthEmail" name="email" autocomplete="username" required />
      </div>
      <div class="sb-auth-field">
        <label class="sb-auth-label" for="sbAuthPass">Kata Sandi</label>
        <input type="password" id="sbAuthPass" name="password" autocomplete="current-password" required />
      </div>
      <div class="sb-auth-err" id="sbAuthErr" hidden></div>
      <button type="submit" class="sb-auth-btn" id="sbAuthBtn">Masuk</button>
    </form>
  `;
  document.body.appendChild(el);
  return el;
}

/**
 * Menahan halaman sampai pengguna terautentikasi.
 * Mengembalikan { user, profile } setelah login berhasil.
 */
async function sbRequireAuth(subtitle) {
  const backdrop = sbInjectAuthUI(subtitle || 'Sistem Kasir & Membership');
  const form = document.getElementById('sbAuthForm');
  const errEl = document.getElementById('sbAuthErr');
  const btn = document.getElementById('sbAuthBtn');

  const { data: { session } } = await sb.auth.getSession();
  if (session) return sbLoadProfile(session.user);

  backdrop.classList.add('is-open');

  const user = await new Promise((resolve) => {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      errEl.hidden = true;
      btn.disabled = true;
      btn.textContent = 'Memeriksa…';

      const email = document.getElementById('sbAuthEmail').value.trim();
      const password = document.getElementById('sbAuthPass').value;
      const { data, error } = await sb.auth.signInWithPassword({ email, password });

      btn.disabled = false;
      btn.textContent = 'Masuk';

      if (error) {
        errEl.textContent = /invalid/i.test(error.message)
          ? 'Email atau kata sandi salah.'
          : 'Gagal masuk: ' + error.message;
        errEl.hidden = false;
        return;
      }
      backdrop.classList.remove('is-open');
      resolve(data.user);
    });
  });

  return sbLoadProfile(user);
}

async function sbLoadProfile(user) {
  const { data } = await sb.from('profiles').select('full_name, role').eq('id', user.id).maybeSingle();
  return { user, profile: data || { full_name: user.email, role: 'kasir' } };
}

async function sbSignOut() {
  await sb.auth.signOut();
  localStorage.removeItem(SB_CASHIER_KEY);
  location.reload();
}

/* ---------------------------------------------------------------------------
   GERBANG PIN KASIR

   Perangkat POS diautentikasi sekali (akun perangkat / owner). PIN di sini
   TIDAK menjaga database — tugasnya menentukan kasir mana yang bertugas,
   sehingga setiap transaksi punya penanggung jawab. Verifikasi dilakukan di
   server: daftar PIN tidak pernah dikirim ke browser.
   --------------------------------------------------------------------------- */

const SB_CASHIER_KEY = 'barber_cashier_v1';

const SB_PIN_CSS = `
  .sb-pin-backdrop {
    position: fixed; inset: 0; z-index: 9998;
    background: var(--bg, #F4F5F7);
    display: none; align-items: center; justify-content: center; padding: 20px;
  }
  .sb-pin-backdrop.is-open { display: flex; }
  .sb-pin-card {
    width: 100%; max-width: 340px;
    display: flex; flex-direction: column; gap: 18px; align-items: center;
  }
  .sb-pin-logo { height: 26px; width: auto; display: block; margin-bottom: 4px; }
  .sb-pin-title { font-size: 17px; font-weight: 600; color: var(--text, #16181C); text-align: center; }
  .sb-pin-sub {
    font-family: var(--mono, monospace); font-size: 11px; letter-spacing: .12em;
    text-transform: uppercase; color: var(--text-dim, #767D87); text-align: center;
  }
  .sb-pin-dots { display: flex; gap: 14px; height: 18px; align-items: center; }
  .sb-pin-dot {
    width: 13px; height: 13px; border-radius: 50%;
    border: 1.5px solid var(--border, #E1E5EA); transition: all .12s ease;
  }
  .sb-pin-dot.is-filled { background: var(--brand, #BE0000); border-color: var(--brand, #BE0000); }
  .sb-pin-pad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; width: 100%; }
  .sb-pin-key {
    background: var(--surface, #FFFFFF); border: 1px solid var(--border, #E1E5EA);
    color: var(--text, #16181C); border-radius: var(--r-md, 10px);
    font-family: var(--mono, monospace); font-size: 22px; font-weight: 600;
    padding: 16px 0; cursor: pointer; user-select: none;
    transition: background .1s ease, border-color .1s ease;
  }
  .sb-pin-key:active { background: var(--brand, #BE0000); color: #fff; border-color: var(--brand, #BE0000); }
  .sb-pin-key.is-muted { font-size: 15px; color: var(--text-dim, #767D87); }
  .sb-pin-err {
    font-size: 13px; color: var(--brand, #BE0000); text-align: center;
    min-height: 18px; line-height: 1.4;
  }
  .sb-cashier-chip {
    display: inline-flex; align-items: center; gap: 7px;
    font-size: 12.5px; font-weight: 600; color: var(--text, #16181C);
    background: var(--surface, #FFFFFF); border: 1px solid var(--border, #E1E5EA);
    border-radius: 99px; padding: 5px 12px; cursor: pointer; white-space: nowrap;
  }
  .sb-cashier-chip:hover { border-color: var(--brand, #BE0000); }
  .sb-cashier-chip .dot {
    width: 6px; height: 6px; border-radius: 50%; background: var(--ok, #0F7355); flex: none;
  }
`;

function sbInjectPinUI() {
  const style = document.createElement('style');
  style.textContent = SB_PIN_CSS;
  document.head.appendChild(style);

  const keys = ['1','2','3','4','5','6','7','8','9','hapus','0','ok'];
  const el = document.createElement('div');
  el.className = 'sb-pin-backdrop';
  el.id = 'sbPinBackdrop';
  el.innerHTML = `
    <div class="sb-pin-card">
      <img src="assets/logo.png" alt="Underrated Barbershop" class="sb-pin-logo" />
      <div>
        <div class="sb-pin-title">Masukkan PIN Kasir</div>
        <div class="sb-pin-sub" id="sbPinSub">Setiap transaksi tercatat atas nama Anda</div>
      </div>
      <div class="sb-pin-dots" id="sbPinDots"></div>
      <div class="sb-pin-err" id="sbPinErr"></div>
      <div class="sb-pin-pad" id="sbPinPad">
        ${keys.map(k => `<button type="button" class="sb-pin-key${k === 'hapus' || k === 'ok' ? ' is-muted' : ''}" data-key="${k}">${k === 'hapus' ? '⌫' : k === 'ok' ? 'OK' : k}</button>`).join('')}
      </div>
    </div>
  `;
  document.body.appendChild(el);
  return el;
}

function sbGetActiveCashier() {
  try { return JSON.parse(localStorage.getItem(SB_CASHIER_KEY)); }
  catch { return null; }
}

/**
 * Menahan POS sampai PIN kasir dikenali.
 * @param {boolean} paksa - true untuk mengganti kasir walau sudah ada sesi
 */
async function sbRequirePin(paksa) {
  if (!paksa) {
    const tersimpan = sbGetActiveCashier();
    if (tersimpan && tersimpan.id) return tersimpan;
  }

  const backdrop = document.getElementById('sbPinBackdrop') || sbInjectPinUI();
  const dotsEl = document.getElementById('sbPinDots');
  const errEl = document.getElementById('sbPinErr');
  const padEl = document.getElementById('sbPinPad');

  let buffer = '';
  let sibuk = false;

  const paint = () => {
    const n = Math.max(4, buffer.length);
    dotsEl.innerHTML = Array.from({ length: n }, (_, i) =>
      `<div class="sb-pin-dot${i < buffer.length ? ' is-filled' : ''}"></div>`).join('');
  };
  paint();
  backdrop.classList.add('is-open');

  return new Promise((resolve) => {
    const kirim = async () => {
      if (sibuk || buffer.length < 4) {
        if (buffer.length < 4) errEl.textContent = 'PIN minimal 4 digit.';
        return;
      }
      sibuk = true;
      errEl.textContent = 'Memeriksa…';

      const { data, error } = await sb.rpc('verify_cashier_pin', { p_pin: buffer });
      sibuk = false;

      if (error) {
        errEl.textContent = error.message || 'Gagal memeriksa PIN.';
        buffer = ''; paint();
        return;
      }
      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        errEl.textContent = 'PIN tidak dikenali.';
        buffer = ''; paint();
        return;
      }

      const kasir = { id: row.cashier_id, name: row.cashier_name };
      localStorage.setItem(SB_CASHIER_KEY, JSON.stringify(kasir));
      errEl.textContent = '';
      buffer = ''; paint();
      backdrop.classList.remove('is-open');
      padEl.removeEventListener('click', onPad);
      document.removeEventListener('keydown', onKey);
      resolve(kasir);
    };

    const tekan = (k) => {
      errEl.textContent = '';
      if (k === 'hapus') buffer = buffer.slice(0, -1);
      else if (k === 'ok') return kirim();
      else if (buffer.length < 8) buffer += k;
      paint();
      if (buffer.length === 4) kirim();   // PIN 4 digit langsung dikirim
    };

    const onPad = (e) => {
      const btn = e.target.closest('[data-key]');
      if (btn) tekan(btn.dataset.key);
    };
    // Kasir yang memakai tablet berkeyboard atau laptop tetap bisa mengetik
    const onKey = (e) => {
      if (/^[0-9]$/.test(e.key)) tekan(e.key);
      else if (e.key === 'Backspace') tekan('hapus');
      else if (e.key === 'Enter') tekan('ok');
    };

    padEl.addEventListener('click', onPad);
    document.addEventListener('keydown', onKey);
  });
}

/* ---------------------------------------------------------------------------
   ANTREAN OFFLINE
   localStorage tidak lagi menjadi database — perannya kini murni sebagai
   penyangga tulis. Transaksi yang gagal terkirim disimpan di sini, lalu
   dikirim ulang otomatis begitu koneksi pulih. client_uuid membuat pengiriman
   ulang aman: server mengembalikan transaksi yang sama, bukan duplikat.
   --------------------------------------------------------------------------- */

const SB_QUEUE_KEY = 'barber_outbox_v1';

const SBQueue = {
  all() {
    try { return JSON.parse(localStorage.getItem(SB_QUEUE_KEY)) || []; }
    catch { return []; }
  },
  save(list) { localStorage.setItem(SB_QUEUE_KEY, JSON.stringify(list)); },
  add(payload) {
    const list = this.all();
    list.push(payload);
    this.save(list);
    return list.length;
  },
  remove(clientUuid) {
    this.save(this.all().filter(p => p.p_client_uuid !== clientUuid));
  },
  /** Catat kegagalan tanpa membuang transaksinya — ini catatan omzet, bukan
      data sekali pakai. Kegagalan yang berulang perlu terlihat orang, bukan
      diulang diam-diam selamanya. */
  markFailed(clientUuid, message) {
    const list = this.all();
    const item = list.find(p => p.p_client_uuid === clientUuid);
    if (!item) return;
    item._gagal = (item._gagal || 0) + 1;
    item._pesan = message;
    this.save(list);
  },
  count() { return this.all().length; },
  /** Item yang sudah berkali-kali gagal — butuh campur tangan, bukan tunggu. */
  stuck() { return this.all().filter(p => (p._gagal || 0) >= 3); }
};

/** Kirim satu transaksi. Bila gagal karena jaringan, masuk antrean. */
async function sbSubmitTransaction(payload) {
  if (!SBConn.online) {
    SBQueue.add(payload);
    return { queued: true };
  }
  try {
    const { data, error } = await sb.rpc('create_transaction', payload);
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    return { queued: false, tx: row };
  } catch (err) {
    // Kegagalan validasi/izin tidak boleh diantrekan — akan gagal selamanya
    const permanent = err && (err.code === '42501' || err.code === '23514' || err.code === '22P02');
    if (permanent) return { error: err };
    SBQueue.add(payload);
    return { queued: true, error: err };
  }
}

/** Kirim ulang seluruh antrean. Mengembalikan jumlah yang berhasil terkirim. */
async function sbFlushQueue() {
  if (!SBConn.online) return 0;
  const list = SBQueue.all();
  let sent = 0;
  for (const payload of list) {
    // Buang penanda diagnostik sebelum dikirim — bukan bagian dari argumen RPC
    const { _gagal, _pesan, ...args } = payload;
    try {
      const { error } = await sb.rpc('create_transaction', args);
      if (error) {
        // Pengiriman ulang transaksi yang sama sudah aman di sisi server
        // (client_uuid unik), jadi kegagalan di sini berarti masalah nyata:
        // kasir dihapus, izin dicabut, atau data tidak sah. Transaksinya
        // TIDAK dibuang — hanya ditandai supaya bisa ditangani manusia.
        SBQueue.markFailed(payload.p_client_uuid, error.message || String(error));
        continue;
      }
      SBQueue.remove(payload.p_client_uuid);
      sent++;
    } catch (err) {
      // Kegagalan jaringan: biarkan mengantre, dicoba lagi nanti
      SBQueue.markFailed(payload.p_client_uuid, err && err.message ? err.message : 'gangguan jaringan');
    }
  }
  return sent;
}

/* ---------------------------------------------------------------------------
   INDIKATOR KONEKSI
   --------------------------------------------------------------------------- */

function sbRenderConnPill(el) {
  const paint = () => {
    const pending = SBQueue.count();
    const macet = SBQueue.stuck();

    // Antrean yang gagal berulang tidak boleh terlihat sama dengan antrean
    // yang sekadar menunggu koneksi — yang satu selesai sendiri, yang lain tidak.
    if (macet.length) {
      el.className = 'sb-conn-pill is-offline';
      el.textContent = `${macet.length} TRANSAKSI GAGAL KIRIM`;
      el.title = 'Gagal berulang: ' + macet[0]._pesan +
                 '\nTransaksi tetap tersimpan di perangkat ini. Perbaiki penyebabnya, lalu coba lagi.';
      return;
    }
    el.title = 'Status koneksi ke server';
    if (!SBConn.online) {
      el.className = 'sb-conn-pill is-offline';
      el.textContent = pending ? `OFFLINE · ${pending} MENUNGGU` : 'OFFLINE';
    } else if (pending) {
      el.className = 'sb-conn-pill is-pending';
      el.textContent = `SINKRON · ${pending} MENUNGGU`;
    } else {
      el.className = 'sb-conn-pill is-online';
      el.textContent = 'TERSAMBUNG';
    }
  };
  SBConn.onChange(async (online) => {
    paint();
    if (online && SBQueue.count()) {
      const n = await sbFlushQueue();
      paint();
      if (n && typeof showToast === 'function') showToast(`${n} transaksi tertunda berhasil disinkronkan.`);
    }
  });
  return paint;
}

/* Tanggal operasional WIB — dipakai rekap agar sepadan dengan business_date. */
function sbJakartaToday() {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jakarta' });
}
