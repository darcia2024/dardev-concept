import React from 'react';
import { Check, Award, HelpCircle, ShieldCheck, Zap, ArrowRight, FileCheck, Users, BarChart3 } from 'lucide-react';
import { PACKAGES, PAYMENT_SCHEME } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onSelectPackage?: (id: 'starter' | 'standard' | 'pro') => void;
  onJumpToCalculator?: () => void;
}

export const Slide07PackagePro: React.FC<SlideProps> = ({ onJumpToCalculator }) => {
  const pkg = PACKAGES[2]; // Pro

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-8 border border-amber-500/40 shadow-2xl shadow-amber-500/10">
      
      {/* Top Banner */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/10 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-amber-300 bg-amber-500/20 px-3 py-1 rounded-full border border-amber-500/30 font-bold">
              Paket 3: LMS Penuh & Otomasi Skala Besar
            </span>
          </div>
          <h3 className="font-display font-bold text-3xl sm:text-4xl text-white">
            Paket Pro LMS
          </h3>
          <p className="text-sm text-slate-300 mt-1 max-w-xl">
            {pkg.bestFor}
          </p>
        </div>

        <div className="sm:text-right">
          <span className="text-xs text-slate-400 block">Investasi Paket:</span>
          <div className="font-display font-extrabold text-3xl sm:text-4xl text-amber-400">
            {pkg.formattedPrice}
          </div>
          <span className="text-[11px] text-amber-400 font-medium">Prioritas Revisi + Garansi 30 Hari</span>
        </div>
      </div>

      {/* 3 Core Pro Automation Highlights */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3.5 mb-6">
        <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3">
          <Award className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Sertifikat Otomatis</div>
            <div className="text-xs text-slate-400">Terbit instan dengan nama peserta saat selesai kelas.</div>
          </div>
        </div>

        <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3">
          <FileCheck className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Kuis & Absensi</div>
            <div className="text-xs text-slate-400">Uji pemahaman siswa & catat kehadiran secara otomatis.</div>
          </div>
        </div>

        <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-start gap-3">
          <Users className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-semibold text-xs sm:text-sm text-white">Role Mentor / Pengajar</div>
            <div className="text-xs text-slate-400">Akses khusus guru/ustadz untuk memantau nilai peserta.</div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left: Complete Features (7 cols) */}
        <div className="lg:col-span-7 space-y-3">
          <h4 className="font-display font-bold text-base text-white flex items-center gap-2">
            <Zap className="w-4 h-4 text-amber-400" />
            <span>Semua Fitur Paket Pro LMS:</span>
          </h4>

          <div className="grid grid-cols-1 gap-2 max-h-[340px] overflow-y-auto pr-1">
            {pkg.features.map((feat, idx) => (
              <div key={idx} className="p-2.5 rounded-xl bg-slate-900/70 border border-white/5 flex items-start gap-3">
                <div className="w-5 h-5 rounded-full bg-amber-500/20 border border-amber-500/40 flex items-center justify-center flex-shrink-0 mt-0.5">
                  <Check className="w-3 h-3 text-amber-400 stroke-[3]" />
                </div>
                <span className="text-xs sm:text-sm text-slate-200 leading-snug">{feat}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Right: Payment Breakdown & Verdict (5 cols) */}
        <div className="lg:col-span-5 flex flex-col gap-5">
          
          {/* Skenario Pro */}
          <div className="p-5 rounded-2xl bg-amber-950/30 border border-amber-500/20">
            <h5 className="font-display font-bold text-sm text-amber-300 mb-2">
              Kapan Memilih Paket Pro?
            </h5>
            <p className="text-xs text-slate-300 leading-relaxed">
              Jika Al Madroj ingin sistem pendidikan digital tanpa intervensi manual sama sekali, dengan penerbitan sertifikat tervalidasi otomatis, evaluasi kuis terjadwal, dan rekap absensi otomatis untuk skala ratusan siswa.
            </p>
          </div>

          {/* Skema Termin Pro */}
          <div className="p-5 rounded-2xl bg-slate-900/80 border border-white/10">
            <h5 className="font-display font-bold text-sm text-white mb-3">
              Skema Pembayaran 3 Tahap:
            </h5>
            <div className="space-y-2 text-xs">
              {PAYMENT_SCHEME.pro.map((item, i) => (
                <div key={i} className="p-2.5 rounded-xl bg-slate-950/60 border border-white/5 flex items-center justify-between">
                  <div>
                    <span className="font-semibold text-white block">{item.step}</span>
                    <span className="text-[10px] text-slate-400">{item.description}</span>
                  </div>
                  <span className="font-mono font-bold text-amber-400">
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
              className="w-full py-3 rounded-xl bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs transition-all flex items-center justify-center gap-2 shadow-lg shadow-amber-500/20"
            >
              <span>Hitung Paket Pro di Kalkulator</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          )}

        </div>

      </div>

    </div>
  );
};
