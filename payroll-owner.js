(function () {
  'use strict';
  const P = Payroll, e = P.escape, $ = id => document.getElementById(id);
  let employees = [], month = sbJakartaToday().slice(0,7), requests = [], cashVersion = 0, slipVersion = 0;
  let action = null, printHtml = '', active = false;
  const statusLabel = row => row.disbursed_at ? 'Dicairkan' : ({pending:'Menunggu',approved:'Disetujui',rejected:'Ditolak'}[row.status] || row.status);
  function message(id, text, error=false) { $(id).textContent=text; $(id).className='payroll-message'+(error?' error':''); }
  function fields(c, editor=false) {
    const id=editor?'editor':c.capster_id, days=c.working_days || [1,2,3,4,5,6,7];
    const save=part=>editor?'':`<button type="button" class="btn-hdr" data-payroll-save="${part}">Simpan</button>`;
    const feedback=part=>editor?'':`<div class="payroll-message" data-payroll-message="${part}" role="status"></div>`;
    return `<div class="payroll-fields" data-payroll-id="${e(id)}">
      <div class="kelola-label">Hari masuk kerja</div>
      <div class="payroll-presets">${[[5,'Senin–Jumat'],[6,'Senin–Sabtu'],[7,'Senin–Minggu']].map(([n,l])=>`<button type="button" data-days-preset="${n}">${l}</button>`).join('')}</div>
      <fieldset class="payroll-days" aria-label="Hari kerja ${e(c.name||'karyawan')}">${P.DAYS.map((d,i)=>`<label><input type="checkbox" value="${i+1}" data-working-day ${days.includes(i+1)?'checked':''}>${d}</label>`).join('')}</fieldset>
      ${save('days')}${feedback('days')}
      <label><span class="kelola-label">Gaji pokok bulanan (Rp)</span><input type="text" inputmode="numeric" data-base-salary value="${e(c.base_salary||0)}" autocomplete="off"></label>${save('salary')}${feedback('salary')}
      <div class="kelola-label">Rekening bank</div>
      <label>Nama bank<input list="payrollBankNames" data-bank-name value="${e(c.bank_name||'')}" maxlength="60" placeholder="Pilih atau ketik nama bank"></label>
      <label>Nomor rekening<input type="text" inputmode="numeric" data-bank-number value="${e(c.bank_account_number||'')}" maxlength="34" autocomplete="off"></label>
      <label>Atas nama rekening<input type="text" data-bank-holder value="${e(c.bank_account_holder||'')}" maxlength="150" autocomplete="off"></label>
      ${save('bank')}${feedback('bank')}</div>`;
  }
  function readFields(scope, part) {
    const patch={};
    if (!part || part==='days') {
      patch.working_days=Array.from(scope.querySelectorAll('[data-working-day]:checked'),x=>Number(x.value));
      if (!patch.working_days.length) throw new Error('Pilih minimal satu hari kerja.');
    }
    if (!part || part==='salary') patch.base_salary=P.parseMoney(scope.querySelector('[data-base-salary]').value);
    if (!part || part==='bank') {
      patch.bank_name=scope.querySelector('[data-bank-name]').value.trim();
      patch.bank_account_number=scope.querySelector('[data-bank-number]').value.trim();
      patch.bank_account_holder=scope.querySelector('[data-bank-holder]').value.trim();
      if (patch.bank_name || patch.bank_account_number || patch.bank_account_holder) {
        if (!patch.bank_name || !/^[0-9]{5,34}$/.test(patch.bank_account_number) || !patch.bank_account_holder) throw new Error('Lengkapi nama bank, nomor rekening 5–34 digit, dan atas nama.');
      }
    }
    return patch;
  }
  function invalidateSlip() {
    slipVersion++; printHtml=''; $('payrollPrint').disabled=true; $('payrollPreview').hidden=true;
    $('payrollPreview').innerHTML='';
  }
  async function loadCash(quiet=false) {
    const version=++cashVersion;
    if (!quiet) $('ownerCashBody').innerHTML='<tr><td colspan="7">Memuat pengajuan…</td></tr>';
    try {
      const {data,error}=await sb.rpc('owner_cash_advances',{p_month:month+'-01'});
      if (version!==cashVersion) return;
      if (error) throw error;
      requests=data || [];
      $('ownerCashBody').innerHTML=requests.map(r=>{
        const s=r.summary;
        const buttons=r.status==='pending'
          ? `<button class="btn-hdr" data-cash-action="approve" data-request="${e(r.id)}">Setujui</button> <button class="btn-hdr" data-cash-action="reject" data-request="${e(r.id)}">Tolak</button>`
          : r.status==='approved' && !r.disbursed_at ? `<button class="btn-hdr" data-cash-action="disburse" data-request="${e(r.id)}">Catat pencairan</button>` : '—';
        return `<tr><td>${e(r.name)}<div class="payroll-note">${e(r.jabatan)}</div></td><td>${e(new Date(r.created_at).toLocaleDateString('id-ID',{timeZone:'Asia/Jakarta'}))}</td><td>${P.rupiah(r.amount)}</td><td>${e(r.reason)}${r.decision_note?'<div class="payroll-note">Owner: '+e(r.decision_note)+'</div>':''}</td><td class="payroll-note">Sudah kerja: ${s.jumlah_hari_masuk} hari bulan ini<br>Maks 30%: ${P.rupiah(s.limit_kasbon_30_persen)}</td><td><span class="payroll-status ${e(r.status)}">${statusLabel(r)}</span>${r.disbursed_at?'<div class="payroll-note">'+e(new Date(r.disbursed_at).toLocaleDateString('id-ID',{timeZone:'Asia/Jakarta'}))+'</div>':''}</td><td>${buttons}</td></tr>`;
      }).join('') || '<tr><td colspan="7">Belum ada pengajuan pada periode ini.</td></tr>';
      message('ownerCashMessage','');
    } catch(err) {
      if (version!==cashVersion) return;
      requests=[];
      $('ownerCashBody').innerHTML='<tr><td colspan="7">Pengajuan belum dapat ditampilkan.</td></tr>';
      message('ownerCashMessage','Gagal memuat kasbon: '+(err.message||err),true);
    }
  }
  function resetAdjustments() {
    $('payrollAdditionalLabel').value='';
    ['payrollAdditional','payrollTip','payrollBonus','payrollOther'].forEach(id=>$(id).value='0');
  }
  function setMonth(value) {
    P.monthLabel(value);
    if (month!==value) { month=value; resetAdjustments(); invalidateSlip(); message('payrollMessage',''); }
    $('payrollPayDate').value=month+'-25';
    $('payrollPeriodLabel').textContent=P.monthLabel(month);
    if (active) loadCash();
  }
  function setEmployees(rows) {
    const selected=$('payrollEmployee').value;
    const previous=employees.find(c=>c.capster_id===selected);
    const next=rows.find(c=>c.capster_id===selected);
    const financial=c=>JSON.stringify(c && [c.name,c.jabatan,c.base_salary,c.bank_name,c.bank_account_number,c.bank_account_holder]);
    const optionsChanged=JSON.stringify(employees.map(c=>[c.capster_id,c.name,c.is_active]))!==JSON.stringify(rows.map(c=>[c.capster_id,c.name,c.is_active]));
    employees=rows;
    if (optionsChanged) {
      $('payrollEmployee').innerHTML='<option value="">Pilih karyawan</option>'+rows.map(c=>`<option value="${e(c.capster_id)}">${e(c.name)}${c.is_active?'':' (nonaktif)'}</option>`).join('');
      if (next) $('payrollEmployee').value=selected;
    }
    if (financial(previous)!==financial(next)) invalidateSlip();
    if (!active) { active=true; setMonth(month); }
  }
  document.addEventListener('click', async function(event) {
    const preset=event.target.closest('[data-days-preset]');
    if (preset) {
      preset.closest('[data-payroll-id]').querySelectorAll('[data-working-day]').forEach(x=>{ x.checked=Number(x.value)<=Number(preset.dataset.daysPreset); });
      return;
    }
    const save=event.target.closest('[data-payroll-save]');
    if (save) {
      const scope=save.closest('[data-payroll-id]'), part=save.dataset.payrollSave;
      const msg=scope.querySelector('[data-payroll-message="'+part+'"]');
      save.disabled=true;
      try {
        const patch=readFields(scope,part);
        const {error}=await sb.rpc('owner_set_employee_payroll',{p_id:scope.dataset.payrollId,p_patch:patch});
        if (error) throw error;
        msg.textContent='Tersimpan.'; msg.classList.remove('error');
        document.dispatchEvent(new CustomEvent('payroll:changed'));
      } catch(err) { msg.textContent=err.message||String(err); msg.classList.add('error'); }
      finally { save.disabled=false; }
      return;
    }
    const button=event.target.closest('[data-cash-action]');
    if (!button) return;
    const row=requests.find(r=>r.id===button.dataset.request);
    if (!row) return;
    action={row,kind:button.dataset.cashAction};
    const payout=action.kind==='disburse';
    $('cashDecisionTitle').textContent=payout?'Catat pencairan kasbon':action.kind==='approve'?'Setujui kasbon':'Tolak kasbon';
    $('cashDecisionDetail').textContent=row.name+' — '+P.rupiah(row.amount);
    $('cashDecisionHelp').textContent=payout
      ? 'Gunakan setelah uang benar-benar diserahkan. Tombol ini hanya mencatat pencairan; tidak mentransfer uang. Potongan slip mengikuti bulan pencairan.'
      : 'Keputusan dicatat atas akun owner yang sedang masuk.';
    $('cashDecisionBank').textContent=payout && row.bank_name ? row.bank_name+' · '+row.bank_account_number+' · '+row.bank_account_holder : '';
    $('cashDecisionNoteLabel').textContent=payout?'Referensi / catatan pembayaran (opsional)':'Catatan keputusan (opsional)';
    $('cashDecisionNote').value=''; $('cashDecisionNote').maxLength=payout?150:500;
    $('cashDecisionSubmit').textContent=payout?'Sudah dicairkan':action.kind==='approve'?'Setujui':'Tolak';
    message('cashDecisionMessage',''); $('cashDecisionDialog').showModal();
  });
  $('cashDecisionCancel').addEventListener('click',()=>{ if (!$('cashDecisionSubmit').disabled) $('cashDecisionDialog').close(); });
  $('cashDecisionDialog').addEventListener('cancel',event=>{ if ($('cashDecisionSubmit').disabled) event.preventDefault(); });
  $('cashDecisionForm').addEventListener('submit', async function(event) {
    event.preventDefault(); if (!action || $('cashDecisionSubmit').disabled) return;
    const current=action, button=$('cashDecisionSubmit'); button.disabled=true;
    try {
      const note=$('cashDecisionNote').value.trim();
      const result=current.kind==='disburse'
        ? await sb.rpc('disburse_cash_advance',{p_id:current.row.id,p_reference:note})
        : await sb.rpc('decide_cash_advance',{p_id:current.row.id,p_approve:current.kind==='approve',p_note:note});
      if (result.error) throw result.error;
      $('cashDecisionDialog').close(); action=null; invalidateSlip(); await loadCash();
    } catch(err) { message('cashDecisionMessage',err.message||String(err),true); }
    finally { button.disabled=false; }
  });
  function readSlipInputs() {
    return {paymentDate:$('payrollPayDate').value, additionalLabel:$('payrollAdditionalLabel').value.trim(),
      additional:P.parseMoney($('payrollAdditional').value),tip:P.parseMoney($('payrollTip').value),
      bonus:P.parseMoney($('payrollBonus').value),other:P.parseMoney($('payrollOther').value)};
  }
  $('payrollGenerate').addEventListener('click', async function() {
    invalidateSlip(); const version=slipVersion;
    this.disabled=true;
    try {
      const id=$('payrollEmployee').value;
      if (!id) throw new Error('Pilih karyawan.');
      const input=readSlipInputs();
      const {data,error}=await sb.rpc('owner_payroll_data',{p_id:id,p_month:month+'-01'});
      if (version!==slipVersion) return;
      if (error) throw error;
      printHtml=P.slip(data,input);
      $('payrollPreview').innerHTML=printHtml; $('payrollPreview').hidden=false; $('payrollPrint').disabled=false;
      message('payrollMessage','Slip siap ditinjau. Kasbon yang belum dicairkan tidak dipotong.');
    } catch(err) { if (version===slipVersion) message('payrollMessage',err.message||String(err),true); }
    finally { this.disabled=false; }
  });
  $('payrollForm').addEventListener('input',invalidateSlip);
  $('payrollEmployee').addEventListener('change',()=>{ resetAdjustments(); invalidateSlip(); message('payrollMessage',''); });
  $('payrollPrint').addEventListener('click',function() {
    if (!printHtml) return;
    let root=$('payrollPrintRoot');
    if (!root) { root=document.createElement('div'); root.id='payrollPrintRoot'; root.hidden=true; document.body.appendChild(root); }
    root.innerHTML=printHtml;
    // Nama/keterangan yang panjang tetap muat A4 tanpa memotong tanda tangan.
    const preview=$('payrollPreview').querySelector('.salary-slip');
    root.style.setProperty('--slip-print-scale',Math.min(1,(267*96/25.4)/preview.offsetHeight));
    document.body.classList.add('payroll-print');
    window.print();
  });
  window.addEventListener('afterprint',()=>{ document.body.classList.remove('payroll-print'); const root=$('payrollPrintRoot'); if(root) root.innerHTML=''; });
  $('ownerCashRefresh').addEventListener('click',()=>loadCash());
  window.PayrollUI={fields,readFields,setEmployees,setMonth,invalidateSlip,loadCash};
})();
