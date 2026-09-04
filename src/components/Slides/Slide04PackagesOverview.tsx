import React from 'react';
import { Check, ArrowRight, Star, ShieldCheck } from 'lucide-react';
import { PACKAGES } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onSelectPackage?: (id: 'starter' | 'standard' | 'pro') => void;
  onJumpToSlide?: (index: number) => void;
}

export const Slide04PackagesOverview: React.FC<SlideProps> = ({ onJumpToSlide }) => {
  return (
    <div className="w-full max-w-6xl mx-auto py-2 sm:py-6">
      
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto mb-8">
        <span className="text-xs font-mono uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-3 py-1 rounded-full border border-emerald-500/20">
          3 Pilihan Paket Fleksibel
        </span>
        <h3 className="font-display font-bold text-2xl sm:text-3xl text-white mt-3">
          Pilih Paket yang Paling Sesuai dengan Target Anda
        </h3>
        <p className="text-sm text-slate-300 mt-2">
          Semua paket menjamin tampilan profesional di semua perangkat (HP, tablet, komputer) dan didukung garansi perbaikan bug resmi.
        </p>
      </div>

      {/* 3 Packages Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 items-stretch mb-8">
        {PACKAGES.map((pkg, idx) => {
          const isRec = pkg.isRecommended;
          return (
            <div
              key={pkg.id}
              className={`relative rounded-3xl p-6 sm:p-7 flex flex-col justify-between transition-all duration-300 ${
                isRec
                  ? 'glass-panel border-2 border-emerald-500 shadow-2xl shadow-emerald-500/10 scale-[1.02] bg-gradient-to-b from-slate-900/90 to-slate-950/95'
                  : 'glass-card border border-white/10 bg-slate-900/60 hover:border-white/20'
              }`}
            >
              {/* Recommended Badge */}
              {isRec && (
                <div className="absolute -top-3 left-1/2 -translate-x-1/2 text-[10px] font-bold uppercase tracking-wider px-3 py-0.5 rounded-full bg-gradient-to-r from-emerald-500 to-teal-400 text-slate-950 shadow-md flex items-center gap-1">
                  <Star className="w-3 h-3 fill-slate-950" />
                  <span>PALING DIREKOMENDASIKAN</span>
                </div>
              )}

              <div>
                {/* Header info */}
                <div className="flex items-center justify-between mb-3">
                  <span className={`text-[10px] font-mono uppercase px-2.5 py-0.5 rounded-full ${pkg.colorScheme.badgeBg} ${pkg.colorScheme.badgeText}`}>
                    {pkg.tagline}
                  </span>
                  <span className="text-xs text-slate-400">Garansi {pkg.bugFixingDays} Hari</span>
                </div>

                <h4 className="font-display font-bold text-2xl text-white mb-2">{pkg.name}</h4>
                
                {/* Price Display */}
                <div className="mb-4">
                  <span className="text-xs text-slate-400 block mb-0.5">Investasi Pengerjaan:</span>
                  <div className="font-display font-extrabold text-3xl text-emerald-400">
                    {pkg.formattedPrice}
                  </div>
                </div>

                {/* Layman Best For Pitch */}
                <div className="p-3.5 rounded-2xl bg-slate-950/50 border border-white/5 mb-5 text-xs text-slate-300 leading-relaxed">
                  {pkg.laymanPitch}
                </div>

                {/* Key feature bullets */}
                <div className="space-y-2 mb-6 text-xs text-slate-300">
                  <span className="font-mono text-[10px] uppercase text-slate-400 block tracking-wider mb-2">
                    Fitur Kunci Termasuk:
                  </span>
                  {pkg.features.slice(0, 5).map((feat, i) => (
                    <div key={i} className="flex items-start gap-2">
                      <Check className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0 mt-0.5 stroke-[2.5]" />
                      <span className="leading-snug">{feat}</span>
                    </div>
                  ))}
                  {pkg.features.length > 5 && (
                    <div className="text-[11px] text-slate-400 pl-5 pt-1 italic">
                      + {pkg.features.length - 5} fitur pelengkap lainnya...
                    </div>
                  )}
                </div>
              </div>

              {/* Action Button: Jump to detailed slide */}
              <button
                onClick={() => {
                  sound.playClick();
                  // Jump to specific slide: Starter (slide index 4), Standard (index 5), Pro (index 6)
                  const targetSlide = idx === 0 ? 4 : idx === 1 ? 5 : 6;
                  if (onJumpToSlide) onJumpToSlide(targetSlide);
                }}
                className={`w-full py-3 px-4 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 ${
                  isRec
                    ? 'bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-md shadow-emerald-500/20'
                    : 'bg-slate-800 hover:bg-slate-700 text-white border border-white/10'
                }`}
              >
                <span>Lihat Rincian Paket {pkg.name}</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>

            </div>
          );
        })}
      </div>

    </div>
  );
};
