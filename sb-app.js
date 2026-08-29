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
  /* Gerbang perangkat memakai kartu terbelah yang sama dengan halaman /masuk.
     Layar ini praktis adalah halaman masuk bagi mesin kasir, jadi tidak ada
     alasan ia tampil sebagai dialog yang berbeda sendiri. */
  .sb-auth-backdrop {
    position: fixed; inset: 0; z-index: 9999;
    background: #2A0607;
    background-image: radial-gradient(120% 100% at 50% 0%, #3A0A0B 0%, #2A0607 46%, #1C0304 100%);
    display: none; align-items: center; justify-content: center;
    padding: clamp(16px, 4vw, 48px);
    overflow: auto;
  }
  .sb-auth-backdrop.is-open { display: flex; }

  .sb-auth-card {
    width: 100%; max-width: 1000px;
    background: #FFFFFF;
    border: none;
    border-radius: 28px;
    padding: 28px;
    box-shadow: 0 40px 90px rgba(0,0,0,.42), 0 4px 14px rgba(0,0,0,.22);
    display: grid;
    grid-template-columns: minmax(0, 420px) 1fr;
    gap: clamp(32px, 5vw, 68px);
    align-items: stretch;
  }

  /* Panel gambar: wordmark diukur menempati x 20,9%–78,9% dan y 47,8%–59,4%,
     sehingga aman pada 3:4 maupun 16:9. */
  .sb-auth-panel {
    border-radius: 20px; overflow: hidden; background: #EDEFF2;
    aspect-ratio: 3 / 4;
    max-height: calc(100dvh - 128px);
  }
  .sb-auth-panel img {
    width: 100%; height: 100%; display: block;
    object-fit: cover; object-position: 50% 52%;
  }

  .sb-auth-sisi {
    display: flex; flex-direction: column; justify-content: center;
    max-width: 380px; width: 100%; min-width: 0; padding: 8px 0;
  }
  /* align-self wajib: induknya flex kolom dengan align-items stretch bawaan,
     yang meregangkan logo di sumbu silang sampai gepeng. */
  .sb-auth-logo {
    height: 26px; width: auto; align-self: flex-start;
    display: block; margin-bottom: 22px;
  }
  .sb-auth-title {
    font-size: 34px; font-weight: 600; letter-spacing: -.032em;
    line-height: 1.12; color: var(--text, #16181C);
  }
  .sb-auth-sub {
    font-size: 14px; color: var(--text-dim, #767D87);
    margin-top: 8px; line-height: 1.5;
  }
  .sb-auth-garis { height: 1px; background: var(--border, #E1E5EA); margin: 26px 0; }

  .sb-auth-field { display: flex; flex-direction: column; gap: 7px; margin-bottom: 16px; }
  .sb-auth-label {
    font-family: var(--sans, sans-serif); font-size: 13.5px; letter-spacing: 0;
    text-transform: none; color: var(--text-mid, #565C66);
  }
  .sb-auth-card input {
    background: var(--surface, #FFFFFF);
    border: 1px solid var(--border, #E1E5EA);
    border-radius: 12px; color: var(--text, #16181C);
    height: 50px; padding: 0 15px;
    font-size: 15.5px; font-family: inherit; outline: none; width: 100%;
    transition: border-color .15s ease, box-shadow .15s ease;
  }
  .sb-auth-card input:focus {
    border-color: var(--brand, #BE0000);
    box-shadow: 0 0 0 3px var(--brand-wash, rgba(190,0,0,.06));
  }
  .sb-auth-btn {
    background: var(--brand, #BE0000); color: #fff;
    border: none; border-radius: 12px;
    width: 100%; height: 52px; margin-top: 10px;
    font-size: 15.5px; font-weight: 500; font-family: inherit;
    letter-spacing: -.01em; cursor: pointer;
    box-shadow: 0 8px 20px rgba(190,0,0,.24);
    transition: transform .12s ease, background .18s ease;
  }
  .sb-auth-btn:active:not(:disabled) { transform: scale(.99); }
  .sb-auth-btn:disabled {
    background: var(--surface-sunk, #EDEFF2); color: var(--text-dim, #767D87);
    box-shadow: none; cursor: default;
  }

  @media (min-width: 861px) and (max-height: 780px) {
    .sb-auth-backdrop { padding: 24px; }
    .sb-auth-card { padding: 22px; gap: clamp(28px, 4vw, 52px); }
  }
  @media (max-width: 860px) {
    .sb-auth-card {
      grid-template-columns: 1fr; gap: 26px;
      padding: 20px; border-radius: 24px; max-width: 460px;
    }
    .sb-auth-panel { aspect-ratio: 16 / 9; max-height: none; }
    .sb-auth-sisi { max-width: none; padding: 0 2px 4px; }
    .sb-auth-title { font-size: 29px; }
    .sb-auth-garis { margin: 22px 0; }
    /* Panel sudah membawa wordmark dan duduk tepat di atas formulir */
    .sb-auth-logo { display: none; }
  }

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

function sbInjectAuthUI(subtitle, judul) {
  const style = document.createElement('style');
  style.textContent = SB_LOGIN_CSS;
  document.head.appendChild(style);

  const el = document.createElement('div');
  el.className = 'sb-auth-backdrop';
  el.id = 'sbAuthBackdrop';
  el.innerHTML = `
    <form class="sb-auth-card" id="sbAuthForm" autocomplete="on">
      <div class="sb-auth-panel">
        <picture>
          <source srcset="assets/login-panel.webp" type="image/webp" />
          <img src="assets/login-panel.jpg" alt="Underrated Barbershop" width="1200" height="1200" />
        </picture>
      </div>

      <div class="sb-auth-sisi">
        <img src="assets/logo.png" alt="" class="sb-auth-logo" aria-hidden="true" />
        <div class="sb-auth-title">${judul}</div>
        <div class="sb-auth-sub">${subtitle}</div>

        <div class="sb-auth-garis"></div>

        <div class="sb-auth-err" id="sbAuthErr" hidden></div>

        <div class="sb-auth-field">
          <label class="sb-auth-label" for="sbAuthEmail">Email</label>
          <input type="email" id="sbAuthEmail" name="email" autocomplete="username"
                 placeholder="nama@underrated.com" required />
        </div>
        <div class="sb-auth-field">
          <label class="sb-auth-label" for="sbAuthPass">Kata sandi</label>
          <input type="password" id="sbAuthPass" name="password" autocomplete="current-password"
                 placeholder="&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;" required />
        </div>

        <button type="submit" class="sb-auth-btn" id="sbAuthBtn">Masuk</button>
      </div>
    </form>
  `;
  document.body.appendChild(el);
  return el;
}

/**
 * Menahan halaman sampai pengguna terautentikasi.
 * Mengembalikan { user, profile } setelah login berhasil.
 */
/**
 * Menahan halaman sampai perangkat terautentikasi.
 * @param {string} subtitle - keterangan kecil di bawah judul
 * @param {string} [judul]  - judul gerbang. Layar POS memakai kalimat yang
 *   menyebut ini pendaftaran perangkat, bukan login harian: kasir sudah
 *   diberi tahu bahwa mereka cukup memakai PIN, sehingga judul "Masuk untuk
 *   melanjutkan" membuat mereka mengira sistemnya salah atau mereka salah
 *   diberi tahu. Layar ini hanya muncul sekali per perangkat.
 */
async function sbRequireAuth(subtitle, judul) {
  const backdrop = sbInjectAuthUI(subtitle || 'Sistem Kasir & Membership', judul || 'Masuk untuk melanjutkan');
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
    background: #2A0607;
    background-image: radial-gradient(120% 100% at 50% 0%, #3A0A0B 0%, #2A0607 46%, #1C0304 100%);
    display: none; align-items: center; justify-content: center; padding: 20px;
  }
  .sb-pin-backdrop.is-open { display: flex; }
  .sb-pin-card {
    width: 100%; max-width: 372px;
    background: #FFFFFF;
    border-radius: 28px;
    padding: 30px 26px 26px;
    box-shadow: 0 40px 90px rgba(0,0,0,.42), 0 4px 14px rgba(0,0,0,.22);
    display: flex; flex-direction: column; gap: 18px; align-items: center;
  }
  .sb-pin-logo { height: 26px; width: auto; display: block; margin-bottom: 4px; }
  .sb-pin-title {
    font-size: 26px; font-weight: 600; letter-spacing: -.028em;
    color: var(--text, #16181C); text-align: center; line-height: 1.15;
  }
  .sb-pin-sub {
    font-family: var(--sans, sans-serif); font-size: 13.5px; letter-spacing: 0;
    text-transform: none; color: var(--text-dim, #767D87); text-align: center;
    /* Positif, bukan negatif: judul dan subjudul berada dalam satu pembungkus
       tanpa gap, sehingga margin negatif membuat keduanya bertumpuk 8px. */
    margin-top: 6px; line-height: 1.45;
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
    color: var(--text, #16181C); border-radius: 14px;
    font-family: var(--sans, sans-serif); font-size: 22px; font-weight: 500;
    font-variant-numeric: tabular-nums;
    padding: 16px 0; cursor: pointer; user-select: none;
    transition: background .1s ease, border-color .1s ease;
  }
  .sb-pin-key:active { background: var(--brand, #BE0000); color: #fff; border-color: var(--brand, #BE0000); }
  .sb-pin-key.is-muted { font-size: 15px; color: var(--text-dim, #767D87); }
  /* OK menyala begitu panjang PIN mencukupi. Tanpa penanda ini kasir tidak
     punya isyarat kapan ketikannya sudah boleh dikirim, karena panjang PIN
     tidak seragam antar-kasir. */
  .sb-pin-key.is-siap {
    color: #fff; background: var(--brand, #BE0000); border-color: var(--brand, #BE0000);
  }
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
    const okBtn = padEl.querySelector('[data-key="ok"]');
    if (okBtn) okBtn.classList.toggle('is-siap', buffer.length >= 4);
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
      // Dulu baris ini mengirim begitu buffer mencapai 4 digit. Itu benar
      // selama seluruh PIN 4 digit, dan diam-diam rusak begitu ada PIN yang
      // lebih panjang: ketikan terkirim di digit keempat, ditolak, lalu
      // buffer dikosongkan — digit kelima tidak pernah sempat masuk, dan
      // PIN yang benar pun mustahil diketik. Tiap tembakan itu juga
      // menambah hitungan gagal, sehingga lima kali mencoba mengunci
      // perangkat 60 detik. Panjang PIN tidak seragam (upsert_cashier
      // menerima 4 sampai 8 digit) sehingga pad tidak dapat menebaknya;
      // pengiriman kini menunggu OK, kecuali pada 8 digit yang memang
      // tidak menyisakan kemungkinan ketikan lain.
      if (buffer.length === 8) kirim();
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
