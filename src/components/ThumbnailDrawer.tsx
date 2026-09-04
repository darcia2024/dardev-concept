import React from 'react';
import { X, Layers, ArrowRight } from 'lucide-react';
import { SLIDES } from '../data/proposalData';
import { sound } from '../utils/audio';

interface ThumbnailDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  currentSlide: number;
  onSelectSlide: (index: number) => void;
}

export const ThumbnailDrawer: React.FC<ThumbnailDrawerProps> = ({
  isOpen,
  onClose,
  currentSlide,
  onSelectSlide,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-slate-950/80 backdrop-blur-md animate-fade-in no-print">
      <div 
        className="w-full max-w-4xl max-h-[85vh] glass-panel rounded-3xl p-6 sm:p-8 flex flex-col gap-6 shadow-2xl border border-white/10 overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-white/10 pb-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-2xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
              <Layers className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-display font-bold text-lg text-white">Daftar Slide Presentasi</h3>
              <p className="text-xs text-slate-400">Pilih slide untuk melompat langsung ke topik tertentu</p>
            </div>
          </div>
          <button
            onClick={() => {
              sound.playClick();
              onClose();
            }}
            className="p-2 rounded-xl bg-slate-900/80 text-slate-400 hover:text-white hover:bg-white/10 transition-all border border-white/10"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Slides Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3.5 overflow-y-auto pr-1 py-1">
          {SLIDES.map((slide, index) => {
            const isActive = index === currentSlide;
            return (
              <div
                key={slide.id}
                onClick={() => {
                  sound.playSlide();
                  onSelectSlide(index);
                  onClose();
                }}
                className={`group relative p-4 rounded-2xl border text-left cursor-pointer transition-all duration-200 ${
                  isActive
                    ? 'bg-emerald-500/15 border-emerald-500/60 shadow-lg shadow-emerald-500/10'
                    : 'bg-slate-900/60 border-white/5 hover:border-emerald-500/40 hover:bg-slate-900/90'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <span className={`text-[10px] font-mono px-2 py-0.5 rounded-full ${
                    isActive
                      ? 'bg-emerald-500 text-slate-950 font-bold'
                      : 'bg-slate-800 text-slate-400 border border-white/5'
                  }`}>
                    SLIDE {String(index + 1).padStart(2, '0')}
                  </span>
                  <span className="text-[10px] uppercase font-mono text-slate-400">{slide.category}</span>
                </div>

                <h4 className={`font-display font-semibold text-sm leading-snug mb-1 transition-colors ${
                  isActive ? 'text-emerald-300' : 'text-slate-200 group-hover:text-white'
                }`}>
                  {slide.title}
                </h4>
                <p className="text-xs text-slate-400 line-clamp-1">{slide.subtitle}</p>

                <div className="mt-3 flex items-center justify-end text-[11px] font-medium text-emerald-400 opacity-0 group-hover:opacity-100 transition-opacity">
                  <span>Buka slide</span>
                  <ArrowRight className="w-3.5 h-3.5 ml-1 transform group-hover:translate-x-1 transition-transform" />
                </div>
              </div>
            );
          })}
        </div>

        {/* Footer info */}
        <div className="flex items-center justify-between text-xs text-slate-400 pt-2 border-t border-white/5">
          <span>Tekan <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">ESC</kbd> untuk menutup</span>
          <span className="text-emerald-400 font-medium">12 Slide Lengkap Terstruktur</span>
        </div>
      </div>
    </div>
  );
};
