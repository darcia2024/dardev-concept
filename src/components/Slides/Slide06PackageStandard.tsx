import React from 'react';
import { Check, Star, ShieldCheck, Zap, ArrowRight, UserCheck, Lock, PlayCircle } from 'lucide-react';
import { PACKAGES, PAYMENT_SCHEME } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onSelectPackage?: (id: 'starter' | 'standard' | 'pro') => void;
  onJumpToCalculator?: () => void;
}

export const Slide06PackageStandard: React.FC<SlideProps> = ({ onJumpToCalculator }) => {
  const pkg = PACKAGES[1]; // Standard

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-8 border-2 border-emerald-500 shadow-2xl shadow-emerald-500/15 bg-gradient-to-b from-slate-900/90 to-slate-950/95">
      
      {/* Top Banner with Recommended Badge */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/10 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-emerald-300 bg-emerald-500/20 px-3 py-1 rounded-full border border-emerald-500/40 flex items-center gap-1.5 font-bold">
              <Star className="w-3.5 h-3.5 fill-emerald-400 text-emerald-400" />
              <span>Paket 2: Paling Direkomendasikan (Sweet Spot)</span>
            </span>
          </div>
          <h3 className="font-display font-bold text-3xl sm:text-4xl text-white">
            Paket Standard
          </h3>
          <p className="text-sm text-slate-300 mt-1 max-w-xl">
            {pkg.bestFor}
          </p>
        </div>

        <div className="sm:text-right">
          <span className="text-xs text-slate-400 block">Investasi Paket:</span>
          <div className="font-display font-extrabold text-3xl sm:text-4xl text-emerald-400">
            {pkg.formattedPrice}
          </div>
          <span className="text-[11px] text-emerald-400 font-medium">Garansi 30 Hari + Training Admin</span>
        </div>
      </div>

      {/* 3 Core Highlights of Standard Package */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3.5 mb-6">
        <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-start gap-3">
          <UserCheck className="w-5 h-5 text-emerald-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Akun Login Mandiri</div>
            <div className="text-xs text-slate-400">Peserta punya dashboard pribadi melihat kelas yang dimiliki.</div>
          </div>
        </div>

        <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-start gap-3">
          <Lock className="w-5 h-5 text-emerald-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Proteksi Materi</div>
            <div className="text-xs text-slate-400">Materi terkunci otomatis, admin tinggal 1 klik untuk beri akses.</div>
          </div>
        </div>

        <div className="p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex items-start gap-3">
          <PlayCircle className="w-5 h-5 text-emerald-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Struktur Materi Rapi</div>
            <div className="text-xs text-slate-400">Video, teks, dan file tersusun urut per bab & pertemuan.</div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left: Complete Features (7 cols) */}
        <div className="lg:col-span-7 space-y-4">
          <h4 className="font-display font-bold text-base text-white flex items-center gap-2">
            <Zap className="w-4 h-4 text-emerald-400" />
            <span>Daftar Lengkap Fitur Paket Standard:</span>
          </h4>

          <div className="grid grid-cols-1 gap-2">
            {pkg.features.map((feat, idx) => (
              <div key={idx} className="p-2.5 rounded-xl bg-slate-900/70 border border-white/5 flex items-start gap-3">
                <div className="w-5 h-5 rounded-full bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Check className="w-3 h-3 text-emerald-400 stroke-[3]" />
                </div>
                <span className="text-xs sm:text-sm text-slate-200 leading-snug">{feat}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Right: Payment Schedule & CTA (5 cols) */}
        <div className="lg:col-span-5 flex flex-col gap-5">
          
          {/* Mengapa ini Paling Direkomendasikan */}
          <div className="p-5 rounded-2xl bg-emerald-950/40 border border-emerald-500/30">
            <h5 className="font-display font-bold text-sm text-emerald-300 mb-2">
              💡 Mengapa Ini Pilihan Paling Cerdas?
            </h5>
            <p className="text-xs text-slate-300 leading-relaxed mb-2">
              Paket ini memberikan pengalaman platform kelas modern sejati tanpa biaya tinggi. Peserta merasa sangat puas karena belajar di portal tersendiri, dan admin tidak lagi pusing mengurus manual link di WhatsApp.
            </p>
          </div>

          {/* Skema Termin 3 Tahap */}
          <div className="p-5 rounded-2xl bg-slate-900/80 border border-white/10">
            <h5 className="font-display font-bold text-sm text-white mb-3">
              Skema Pembayaran 3 Tahap (Super Aman):
            </h5>
            <div className="space-y-2 text-xs">
              {PAYMENT_SCHEME.standard.map((item, i) => (
                <div key={i} className="p-2.5 rounded-xl bg-slate-950/60 border border-white/5 flex items-center justify-between">
                  <div>
                    <span className="font-semibold text-white block">{item.step}</span>
                    <span className="text-[10px] text-slate-400">{item.description}</span>
                  </div>
                  <span className="font-mono font-bold text-emerald-400">
                    Rp {item.amount.toLocaleString('id-ID')}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Button */}
          {onJumpToCalculator && (
            <button
              onClick={() => {
                sound.playClick();
                onJumpToCalculator();
              }}
              className="w-full py-3.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs transition-all flex items-center justify-center gap-2 shadow-lg shadow-emerald-500/25"
            >
              <span>Pilih & Hitung Paket Standard di Kalkulator</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          )}

        </div>

      </div>

    </div>
  );
};
