(function () {
  'use strict';
  const P=Payroll, e=P.escape, $=id=>document.getElementById(id);
  let summary=null, requestKey=null, requestContent=null, loading=0, busy=false, active=false;
  function message(text,error=false) { $('cashMessage').textContent=text; $('cashMessage').className='payroll-message'+(error?' error':''); }
  async function load() {
    active=true; const version=++loading;
    try {
      const {data,error}=await sb.rpc('my_cash_advances');
      if (version!==loading) return;
      if (error) throw error;
      summary=data.summary;
      $('cashPeriod').textContent=P.monthLabel(summary.period);
      $('cashDays').textContent=summary.jumlah_hari_masuk+' hari';
      $('cashAvailable').textContent=P.rupiah(Math.max(0,Number(summary.sisa_limit_kasbon_tersedia)));
      $('cashApply').disabled=Number(summary.sisa_limit_kasbon_tersedia)<=0 || busy;
      $('cashAmount').max=String(Math.max(0,Number(summary.sisa_limit_kasbon_tersedia)));
      $('cashHistory').innerHTML=(data.requests||[]).map(r=>{
        const label=r.disbursed_at?'Dicairkan':({pending:'Menunggu',approved:'Disetujui',rejected:'Ditolak'}[r.status]);
        return `<div class="cuti-row"><div class="cuti-main"><div class="cuti-kind">${P.rupiah(r.amount)}</div><div class="cuti-tgl">${e(new Date(r.created_at).toLocaleDateString('id-ID',{timeZone:'Asia/Jakarta'}))}</div><div class="cuti-alasan">${e(r.reason)}</div>${r.decision_note?'<div class="cuti-alasan">Owner: '+e(r.decision_note)+'</div>':''}</div><span class="payroll-status ${e(r.status)}">${label}</span></div>`;
      }).join('') || '<div class="empty">Belum ada pengajuan bulan ini.</div>';
      if (!busy) message(Number(summary.base_salary)===0?'Gaji pokok belum diatur. Hubungi owner.':'');
    } catch(err) {
      if (version!==loading) return;
      summary=null; $('cashDays').textContent='—'; $('cashAvailable').textContent='—'; $('cashApply').disabled=true;
      message('Kasbon gagal dimuat: '+(err.message||err),true);
    }
  }
  $('cashApply').addEventListener('click',async function() {
    await load();
    if (!summary || Number(summary.sisa_limit_kasbon_tersedia)<=0) return;
    $('cashForm').classList.add('buka'); $('cashAmount').focus();
  });
  $('cashCancel').addEventListener('click',()=>{ if (!busy) $('cashForm').classList.remove('buka'); });
  $('cashForm').addEventListener('submit', async function(event) {
    event.preventDefault(); if (busy) return;
    busy=true; $('cashSend').disabled=true; $('cashCancel').disabled=true; $('cashApply').disabled=true;
    try {
      const amount=P.parseMoney($('cashAmount').value), reason=$('cashReason').value.trim();
      if (!amount) throw new Error('Nominal harus lebih dari nol.');
      if (!reason || reason.length>500) throw new Error('Isi alasan 1–500 karakter.');
      await load();
      if (!summary) throw new Error('Limit belum bisa diperiksa. Coba lagi setelah koneksi pulih.');
      const content=JSON.stringify([amount,reason]);
      // Jawaban jaringan bisa hilang sesudah INSERT berhasil. Kunci lama
      // tetap boleh dicoba: server mengembalikan pengajuan yang sama.
      if (requestContent!==content && amount>Number(summary.sisa_limit_kasbon_tersedia)) throw new Error('Nominal melebihi limit tersedia.');
      if (requestContent!==content) { requestKey=crypto.randomUUID(); requestContent=content; }
      const {error}=await sb.rpc('request_cash_advance',{p_amount:amount,p_reason:reason,p_request_key:requestKey});
      if (error) throw error;
      requestKey=null; requestContent=null;
      $('cashForm').classList.remove('buka'); $('cashAmount').value=''; $('cashReason').value='';
      await load(); message('Pengajuan terkirim. Menunggu persetujuan owner.');
    } catch(err) { message(err.message||String(err),true); }
    finally {
      busy=false; $('cashSend').disabled=false; $('cashCancel').disabled=false;
      $('cashApply').disabled=!summary || Number(summary.sisa_limit_kasbon_tersedia)<=0;
    }
  });
  // Non-kapster juga diperbarui; saat melewati tanggal 1, server mengembalikan bulan baru.
  document.addEventListener('visibilitychange',()=>{ if (active && !busy && document.visibilityState==='visible') load(); });
  setInterval(()=>{ if (active && !busy && document.visibilityState==='visible' && SBConn.online) load(); },60000);
  window.EmployeeCash={load};
})();
