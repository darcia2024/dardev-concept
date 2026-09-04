import React from 'react';
import { ShieldCheck, CheckCircle2, Clock, Wrench, GraduationCap, Sparkles } from 'lucide-react';

export const Slide10WorkflowPayment: React.FC = () => {
  const steps = [
    {
      num: '01',
      title: 'Kick-off & DP 50%',
      desc: 'Diskusi struktur kelas, silabus awal, logo/branding, dan pembayaran komitmen awal.',
      status: 'Awal Proyek'
    },
    {
      num: '02',
      title: 'Development & Desain',
      desc: 'Pembuatan website utama, sistem database, katalog, dan halaman manajemen kelas.',
      status: 'Fase Pengerjaan'
    },
    {
      num: '03',
      title: 'Demo Versi Beta (30%)',
      desc: 'Platform siap dicoba langsung oleh tim Al Madroj untuk penyesuaian konten dan review alur.',
      status: 'Checkpoint Demo'
    },
    {
      num: '04',
      title: 'Training & Go-Live (20%)',
      desc: 'Sesi bimbingan admin sampai mahir, penyerahan akun master, dan website resmi diluncurkan.',
      status: 'Serah Terima'
    },
    {
      num: '05',
      title: 'Garansi Bug Fixing',
      desc: 'Pendampingan 14 hingga 30 hari penuh untuk memastikan sistem berjalan stabil dan lancar.',
      status: 'Purna Jual'
    }
  ];

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-10 border border-white/10 shadow-2xl">
      
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto mb-8">
        <span className="text-xs font-mono uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-3 py-1 rounded-full border border-emerald-500/20">
          Keamanan & Kepastian Kerja
        </span>
        <h3 className="font-display font-bold text-2xl sm:text-3xl text-white mt-3">
          Alur Pengerjaan Transparan & Skema Termin Aman
        </h3>
        <p className="text-sm text-slate-300 mt-2">
          Kami membagi pengerjaan menjadi tahapan jelas. Anda selalu memegang kendali atas progres sebelum melakukan pelunasan.
        </p>
      </div>

      {/* 5 Steps Process Timeline */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-3.5 mb-8">
        {steps.map((step, idx) => (
          <div
            key={idx}
            className="p-4 rounded-2xl bg-slate-900/70 border border-white/10 relative flex flex-col justify-between group hover:border-emerald-500/40 transition-colors"
          >
            <div>
              <div className="flex items-center justify-between mb-3">
                <span className="font-mono font-extrabold text-xl text-emerald-400">
                  {step.num}
                </span>
                <span className="text-[9px] font-mono uppercase px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 border border-white/5">
                  {step.status}
                </span>
              </div>
              <h4 className="font-display font-bold text-sm text-white mb-1.5">{step.title}</h4>
              <p className="text-xs text-slate-400 leading-relaxed">{step.desc}</p>
            </div>

            <div className="mt-4 pt-3 border-t border-white/5 flex items-center gap-1.5 text-[11px] text-emerald-400 font-medium">
              <CheckCircle2 className="w-3.5 h-3.5" />
              <span>Terstruktur</span>
            </div>
          </div>
        ))}
      </div>

      {/* 2 Key Guarantees */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        
        <div className="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-start gap-3.5">
          <div className="p-2.5 rounded-xl bg-emerald-500/20 text-emerald-400 flex-shrink-0">
            <GraduationCap className="w-5 h-5" />
          </div>
          <div>
            <h5 className="font-display font-bold text-sm text-white">Training Admin Sampai Mahir</h5>
            <p className="text-xs text-slate-300 mt-1 leading-relaxed">
              Tidak perlu khawatir gaptek. Kami berikan panduan praktis dan sesi praktik langsung menginput materi, approve murid, dan mengelola kelas.
            </p>
          </div>
        </div>

        <div className="p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/20 flex items-start gap-3.5">
          <div className="p-2.5 rounded-xl bg-cyan-500/20 text-cyan-400 flex-shrink-0">
            <Wrench className="w-5 h-5" />
          </div>
          <div>
            <h5 className="font-display font-bold text-sm text-white">Garansi 14 - 30 Hari Purna Jual</h5>
            <p className="text-xs text-slate-300 mt-1 leading-relaxed">
              Jika ada kendala error, tombol macet, atau penyesuaian minor pasca-launch, kami perbaiki tanpa tambahan biaya apapun.
            </p>
          </div>
        </div>

      </div>

    </div>
  );
};
