import React from 'react';
import { Layers, ArrowUpRight, CheckCircle, ShieldCheck, Zap } from 'lucide-react';

export const Slide03Philosophy: React.FC = () => {
  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-10 border border-white/10 shadow-2xl">
      
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto mb-10">
        <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 bg-cyan-500/10 px-3 py-1 rounded-full border border-cyan-500/20">
          Konsep & Filosofi Penawaran
        </span>
        <h3 className="font-display font-bold text-2xl sm:text-3xl text-white mt-3">
          Tumbuh Bertahap: Mulai dari yang Pas, Kembangkan Saat Siap
        </h3>
        <p className="text-sm text-slate-300 mt-2">
          Kami memahami setiap program memiliki fase perkembangannya. Anda tidak dipaksa mengeluarkan biaya besar di awal untuk fitur yang belum tentu dibutuhkan sekarang.
        </p>
      </div>

      {/* 3 Growth Stages Visual Flow */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-5 relative mb-8">
        
        {/* Stage 1 */}
        <div className="p-6 rounded-3xl bg-slate-900/80 border border-white/10 relative flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs font-mono font-bold text-cyan-400 bg-cyan-500/10 px-2.5 py-1 rounded-lg border border-cyan-500/20">
                FASE 1: ETALASE
              </span>
              <span className="text-xs text-slate-500">Starter</span>
            </div>
            <h4 className="font-display font-bold text-lg text-white mb-2">Website Kelas Profesional</h4>
            <p className="text-xs text-slate-400 leading-relaxed">
              Fokus pada branding terpercaya, katalog program yang rapi, formulir pendaftaran, dan penerimaan transfer manual.
            </p>
          </div>

          <div className="mt-6 pt-4 border-t border-white/5 text-xs text-slate-300 font-medium">
            🎯 Target: Validasi pasar & hemat waktu rekap pendaftar.
          </div>
        </div>

        {/* Stage 2 (Recommended Highlight) */}
        <div className="p-6 rounded-3xl bg-emerald-950/40 border-2 border-emerald-500/60 relative flex flex-col justify-between shadow-xl shadow-emerald-500/10">
          <div className="absolute -top-3 left-1/2 -translate-x-1/2 text-[10px] font-bold uppercase tracking-wider px-3 py-0.5 rounded-full bg-emerald-500 text-slate-950 shadow-md">
            TITIK AWAL TERBAIK
          </div>

          <div>
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs font-mono font-bold text-emerald-300 bg-emerald-500/20 px-2.5 py-1 rounded-lg border border-emerald-500/30">
                FASE 2: PORTAL MANDIRI
              </span>
              <span className="text-xs text-emerald-400 font-semibold">Standard</span>
            </div>
            <h4 className="font-display font-bold text-lg text-white mb-2">Platform Belajar Peserta</h4>
            <p className="text-xs text-slate-300 leading-relaxed">
              Peserta login sendiri ke dashboard, materi video/teks terkunci rapi per bab, admin verifikasi dengan 1 klik.
            </p>
          </div>

          <div className="mt-6 pt-4 border-t border-emerald-500/20 text-xs text-emerald-300 font-medium">
            🎯 Target: Otomasi materi & proteksi konten pembelajaran.
          </div>
        </div>

        {/* Stage 3 */}
        <div className="p-6 rounded-3xl bg-slate-900/80 border border-white/10 relative flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <span className="text-xs font-mono font-bold text-amber-400 bg-amber-500/10 px-2.5 py-1 rounded-lg border border-amber-500/20">
                FASE 3: LMS PENUH
              </span>
              <span className="text-xs text-slate-500">Pro LMS</span>
            </div>
            <h4 className="font-display font-bold text-lg text-white mb-2">Otomasi Sertifikat & Kuis</h4>
            <p className="text-xs text-slate-400 leading-relaxed">
              Sertifikat terbit instan, kuis evaluasi otomatis, absensi kehadiran, dan multi-mentor untuk skala ratusan siswa.
            </p>
          </div>

          <div className="mt-6 pt-4 border-t border-white/5 text-xs text-slate-300 font-medium">
            🎯 Target: Operasional autopilot tanpa tambah tenaga staf.
          </div>
        </div>

      </div>

      {/* Reassurance Banner */}
      <div className="p-4 sm:p-5 rounded-2xl bg-gradient-to-r from-slate-900 to-slate-950 border border-white/10 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-emerald-500/15 text-emerald-400 flex items-center justify-center flex-shrink-0">
            <Zap className="w-5 h-5" />
          </div>
          <div>
            <div className="font-display font-bold text-sm text-white">Arsitektur Modular Siap Upgrade</div>
            <div className="text-xs text-slate-400">
              Jika hari ini Al Madroj memilih Paket Starter atau Standard, nanti saat program bertambah besar, website dapat di-upgrade tanpa bongkar ulang dari nol.
            </div>
          </div>
        </div>
      </div>

    </div>
  );
};
