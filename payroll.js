/* Helper penggajian bersama; nilai kuota resmi tetap berasal dari Supabase. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Payroll = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const DAYS = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  const MONTHS = ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
  const BANKS = ['Mandiri','SeaBank','BCA','BRI','BNI','BSI','Jago','CIMB Niaga','Lainnya'];
  const escape = value => String(value == null ? '' : value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function money(value) {
    const n = Number(value);
    if (!Number.isSafeInteger(n) || n < 0 || n > 1000000000000) throw new Error('Nominal harus rupiah utuh antara 0 dan 1 triliun.');
    return n;
  }
  function parseMoney(value) {
    const s = String(value).trim();
    if (!/^\d+$/.test(s)) throw new Error('Isi nominal dalam angka tanpa titik atau koma.');
    return money(s);
  }
  function monthParts(period) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(period || '')) throw new Error('Periode bulan tidak valid.');
    return period.split('-').map(Number);
  }
  function monthLabel(period) { const [y,m] = monthParts(period); return MONTHS[m-1] + ' ' + y; }
  function weekday(date) {
    const d = new Date(String(date).slice(0,10) + 'T00:00:00Z');
    return DAYS[(d.getUTCDay()+6)%7];
  }
  function workingDaysLabel(days) {
    const d = days || [1,2,3,4,5,6,7];
    if (d.join(',') === '1,2,3,4,5') return 'Senin–Jumat';
    if (d.join(',') === '1,2,3,4,5,6') return 'Senin–Sabtu';
    if (d.join(',') === '1,2,3,4,5,6,7') return 'Senin–Minggu';
    return d.map(n => DAYS[n-1]).join(', ');
  }
  function requiredDays(period, days) {
    const [y,m] = monthParts(period);
    if (!Array.isArray(days) || !days.length || new Set(days).size !== days.length || days.some(n => !Number.isInteger(n) || n<1 || n>7)) throw new Error('Pilih hari kerja yang valid.');
    let count=0;
    const end = new Date(Date.UTC(y,m,0)).getUTCDate();
    for (let n=1;n<=end;n++) if (days.includes((new Date(Date.UTC(y,m-1,n)).getUTCDay()+6)%7+1)) count++;
    return count;
  }
  // Helper murni untuk simulasi/tes. BigInt menjaga floor pada nominal rupiah besar.
  function cashLimit(salary, required, attended, approved=0, pending=0) {
    [salary,approved,pending].forEach(money);
    if (!Number.isInteger(required) || required<1 || !Number.isInteger(attended) || attended<0) throw new Error('Jumlah hari tidak valid.');
    const limit = Number(BigInt(salary)*BigInt(attended)*30n/(BigInt(required)*100n));
    return {daily:salary/required, accrued:salary*attended/required, limit, available:limit-approved-pending};
  }
  function bankFee(bank) {
    const b = String(bank || '').trim().toLowerCase();
    if (!b) throw new Error('Lengkapi rekening bank karyawan sebelum membuat slip.');
    return b === 'mandiri' || b === 'bank mandiri' ? 0 : 2500;
  }
  const numberWords = ['','satu','dua','tiga','empat','lima','enam','tujuh','delapan','sembilan','sepuluh','sebelas'];
  function words(n) {
    if (n<12) return numberWords[n];
    if (n<20) return words(n-10)+' belas';
    if (n<100) return words(Math.floor(n/10))+' puluh '+words(n%10);
    if (n<200) return 'seratus '+words(n-100);
    if (n<1000) return words(Math.floor(n/100))+' ratus '+words(n%100);
    if (n<2000) return 'seribu '+words(n-1000);
    for (const [value,label] of [[1e12,'triliun'],[1e9,'miliar'],[1e6,'juta'],[1e3,'ribu']]) {
      if (n>=value) return words(Math.floor(n/value))+' '+label+' '+words(n%value);
    }
    return '';
  }
  function terbilang(n) {
    if (!Number.isSafeInteger(n)) throw new Error('Nominal terbilang tidak valid.');
    const text = ((n<0?'minus ':'')+(n===0?'nol':words(Math.abs(n)))).replace(/\s+/g,' ').trim()+' rupiah';
    return text.charAt(0).toUpperCase()+text.slice(1);
  }
  function totals(data, input) {
    const salary=money(data.employee.base_salary), additional=money(input.additional||0), tip=money(input.tip||0), bonus=money(input.bonus||0);
    const cash=money(data.kasbon_dicairkan||0), fee=bankFee(data.employee.bank_name), other=money(input.other||0);
    const income=salary+additional+tip+bonus, deductions=cash+fee+other;
    return {salary,additional,tip,bonus,cash,fee,other,income,deductions,net:income-deductions};
  }
  const number = n => Number(n).toLocaleString('id-ID');
  const rupiah = n => 'Rp '+number(n);
  function slip(data, input) {
    const e=escape, c=data.employee, a=data.attendance, t=totals(data,input), [y,m]=monthParts(data.period);
    if (!c.bank_account_number || !c.bank_account_holder) throw new Error('Lengkapi rekening bank karyawan sebelum membuat slip.');
    const payment=new Date(input.paymentDate+'T00:00:00Z');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(input.paymentDate||'') || Number.isNaN(payment.getTime()) || payment.toISOString().slice(0,10)!==input.paymentDate) throw new Error('Isi tanggal bayar yang valid.');
    if (t.net<0) throw new Error('Total potongan melebihi pendapatan. Periksa nominal sebelum mencetak.');
    const date=new Date(input.paymentDate+'T00:00:00Z').toLocaleDateString('id-ID',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'});
    const row=(label,value,sub='')=>`<tr${value===0?' class="slip-zero"':''}><td>${e(label)} ${sub?'<small>'+e(sub)+'</small>':''}</td><td>${value?number(value):'–'}</td></tr>`;
    const info=(label,value)=>`<div><span>${e(label)}</span><strong>${e(value)}</strong></div>`;
    return `<article class="salary-slip" aria-label="Slip gaji ${e(c.name)}">
      <header class="slip-header"><div><h1>Underrated</h1><p>Barbershop, BSD Tangerang Selatan</p></div><div class="slip-title"><h2>Slip Gaji</h2><p>Periode ${monthLabel(data.period)}</p><p>${e('UR/SG/'+y+'/'+String(m).padStart(2,'0')+'/'+c.name.toUpperCase())}</p></div></header>
      <section class="slip-identity"><div><h2>${e(c.name)}</h2><p>${e(c.jabatan)}</p></div><span>Skema gaji flat</span></section>
      <section class="slip-info">${info('Tanggal bayar',date)}${info('Bank',c.bank_name)}${info('No. rekening',c.bank_account_number)}${info('Atas nama',c.bank_account_holder)}${info('Izin disetujui',data.izin_disetujui+' hari')}${info('Terlambat',a.terlambat+' kali')}</section>
      <section class="slip-stats">${[[a.hadir,'Hari hadir'],[data.haircut,'Haircut'],[data.hairwash,'Hairwash'],[Math.floor(a.menit_kerja/60)+'j '+a.menit_kerja%60+'m','Jam kerja']].map(([n,l])=>'<div><strong>'+e(n)+'</strong><span>'+l+'</span></div>').join('')}</section>
      <table class="slip-table"><thead><tr><th>Pendapatan</th><th>Rp</th></tr></thead><tbody>${row('Gaji pokok',t.salary,'flat '+MONTHS[m-1])}${t.additional?row(input.additionalLabel||'Pendapatan tambahan / prorata',t.additional):''}${row('Tip pelanggan',t.tip)}${row('Bonus / insentif',t.bonus)}</tbody><tfoot><tr><th>Total pendapatan</th><th>${number(t.income)}</th></tr></tfoot></table>
      <table class="slip-table"><thead><tr><th>Potongan</th><th>Rp</th></tr></thead><tbody>${row('Kasbon',t.cash)}${row('Biaya admin bank',t.fee)}${row('Potongan lain',t.other)}</tbody><tfoot><tr><th>Total potongan</th><th>${number(t.deductions)}</th></tr></tfoot></table>
      <section class="slip-net"><div><span>Gaji bersih diterima</span><em>${e(terbilang(t.net))}</em></div><strong>${rupiah(t.net)}</strong></section>
      <section class="slip-signatures"><div><p>Diserahkan oleh</p><div class="slip-sign-space"></div><strong>Owner</strong><small>Underrated Barbershop</small></div><div><p>Diterima oleh</p><div class="slip-sign-space"></div><strong>${e(c.bank_account_holder)}</strong></div></section>
      <footer class="slip-footer"><span>Rahasia. Hanya untuk ${c.jabatan.toLowerCase()==='kapster'?'kapster':'karyawan'} yang bersangkutan.</span><span>Underrated Barbershop</span></footer>
    </article>`;
  }
  return {DAYS,BANKS,escape,money,parseMoney,monthLabel,weekday,workingDaysLabel,requiredDays,cashLimit,bankFee,terbilang,totals,slip,number,rupiah};
});
