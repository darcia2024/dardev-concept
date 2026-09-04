import React from 'react';
import { Check, ShieldCheck, Clock, Zap, ArrowRight } from 'lucide-react';
import { PACKAGES, PAYMENT_SCHEME } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onSelectPackage?: (id: 'starter' | 'standard' | 'pro') => void;
  onJumpToCalculator?: () => void;
}

export const Slide05PackageStarter: React.FC<SlideProps> = ({ onJumpToCalculator }) => {
  const pkg = PACKAGES[0]; // Starter

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-8 border border-cyan-500/30 shadow-2xl">
      
      {/* Top Banner */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/10 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 bg-cyan-500/10 px-3 py-1 rounded-full border border-cyan-500/20">
              Paket 1: Paling Ringan Untuk Mulai
            </span>
          </div>
          <h3 className="font-display font-bold text-3xl sm:text-4xl text-white">
            Paket Starter
          </h3>
          <p className="text-sm text-slate-300 mt-1 max-w-xl">
            {pkg.bestFor}
          </p>
        </div>

        <div className="sm:text-right">
          <span className="text-xs text-slate-400 block">Investasi Paket:</span>
          <div className="font-display font-extrabold text-3xl sm:text-4xl text-cyan-400">
            {pkg.formattedPrice}
          </div>
          <span className="text-[11px] text-slate-400">Termasuk Garansi 14 Hari</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left: Complete Features (7 cols) */}
        <div className="lg:col-span-7 space-y-4">
          <h4 className="font-display font-bold text-base text-white flex items-center gap-2">
            <Zap className="w-4 h-4 text-cyan-400" />
            <span>Semua Fitur yang Anda Dapatkan:</span>
          </h4>

          <div className="grid grid-cols-1 gap-2.5">
            {pkg.features.map((feat, idx) => (
              <div key={idx} className="p-3 rounded-xl bg-slate-900/60 border border-white/5 flex items-start gap-3">
                <div className="w-5 h-5 rounded-full bg-cyan-500/15 border border-cyan-500/30 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Check className="w-3 h-3 text-cyan-400 stroke-[3]" />
                </div>
                <span className="text-xs sm:text-sm text-slate-200 leading-snug">{feat}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Right: Payment Breakdown & Verdict (5 cols) */}
        <div className="lg:col-span-5 flex flex-col gap-5">
          
          {/* Skenario Cocok */}
          <div className="p-5 rounded-2xl bg-cyan-950/30 border border-cyan-500/20">
            <h5 className="font-display font-bold text-sm text-cyan-300 mb-2">
              Kapan Memilih Paket Ini?
            </h5>
            <p className="text-xs text-slate-300 leading-relaxed mb-3">
              Cocok jika Al Madroj ingin segera memiliki alamat website resmi yang profesional untuk memajang profil pengajar, katalog kelas, dan menerima pendaftaran online secara rapi tanpa perlu mengelola sistem login peserta yang rumit.
            </p>
            <div className="text-[11px] text-cyan-400/90 font-medium">
              💡 Akses materi tetap aman diberikan melalui halaman private terkontrol.
            </div>
          </div>

          {/* Skema Termin */}
          <div className="p-5 rounded-2xl bg-slate-900/80 border border-white/10">
            <h5 className="font-display font-bold text-sm text-white mb-3">
              Skema Pembayaran Bertahap (Aman & Transparan):
            </h5>
            <div className="space-y-2 text-xs">
              {PAYMENT_SCHEME.starter.map((item, i) => (
                <div key={i} className="p-2.5 rounded-xl bg-slate-950/60 border border-white/5 flex items-center justify-between">
                  <div>
                    <span className="font-semibold text-white block">{item.step}</span>
                    <span className="text-[10px] text-slate-400">{item.description}</span>
                  </div>
                  <span className="font-mono font-bold text-cyan-400">
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
              className="w-full py-3 rounded-xl bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold text-xs transition-all flex items-center justify-center gap-2 shadow-lg shadow-cyan-500/20"
            >
              <span>Simulasikan Paket Ini di Kalkulator</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          )}

        </div>

      </div>

    </div>
  );
};
