import React from 'react';
import { ChevronLeft, ChevronRight, Grid, Keyboard } from 'lucide-react';
import { sound } from '../utils/audio';

interface SlideControlBarProps {
  currentSlide: number;
  totalSlides: number;
  onPrev: () => void;
  onNext: () => void;
  onJump: (index: number) => void;
  onOpenThumbnails: () => void;
}

export const SlideControlBar: React.FC<SlideControlBarProps> = ({
  currentSlide,
  totalSlides,
  onPrev,
  onNext,
  onJump,
  onOpenThumbnails,
}) => {
  const progressPercent = ((currentSlide + 1) / totalSlides) * 100;

  return (
    <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-40 w-[95%] max-w-2xl no-print">
      <div className="glass-panel rounded-2xl px-3 sm:px-5 py-2.5 shadow-2xl flex items-center justify-between gap-3 border border-white/10 backdrop-blur-xl">
        
        {/* Prev Button */}
        <button
          onClick={() => {
            sound.playSlide();
            onPrev();
          }}
          disabled={currentSlide === 0}
          className={`flex items-center gap-1 px-3 py-1.5 rounded-xl text-xs font-semibold transition-all ${
            currentSlide === 0
              ? 'opacity-30 cursor-not-allowed text-slate-500'
              : 'text-slate-200 hover:text-white hover:bg-white/10 active:scale-95'
          }`}
          title="Slide Sebelumnya (Panah Kiri / Backspace)"
        >
          <ChevronLeft className="w-4 h-4" />
          <span className="hidden sm:inline">Sebelumnya</span>
        </button>

        {/* Center: Slide Indicators & Progress */}
        <div className="flex flex-col items-center gap-1.5 flex-1 max-w-[260px]">
          <div className="flex items-center gap-1.5 overflow-x-auto py-1 max-w-full no-scrollbar">
            {Array.from({ length: totalSlides }).map((_, i) => (
              <button
                key={i}
                onClick={() => {
                  sound.playSlide();
                  onJump(i);
                }}
                className={`transition-all duration-300 rounded-full ${
                  i === currentSlide
                    ? 'w-6 h-2 bg-gradient-to-r from-emerald-400 to-cyan-400 shadow-sm shadow-emerald-400/50'
                    : 'w-2 h-2 bg-slate-700 hover:bg-slate-500'
                }`}
                title={`Lompat ke Slide ${i + 1}`}
              />
            ))}
          </div>

          <div className="flex items-center gap-2 text-[11px] font-mono text-slate-400">
            <span>
              Slide <strong className="text-emerald-400">{currentSlide + 1}</strong> dari {totalSlides}
            </span>
            <span className="text-slate-600">•</span>
            <span className="text-slate-400">{Math.round(progressPercent)}%</span>
          </div>
        </div>

        {/* Right: Next Button & Grid button */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => {
              sound.playClick();
              onOpenThumbnails();
            }}
            className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-white/10 transition-all hidden xs:flex"
            title="Daftar Semua Slide (M)"
          >
            <Grid className="w-4 h-4" />
          </button>

          <button
            onClick={() => {
              sound.playSlide();
              onNext();
            }}
            disabled={currentSlide === totalSlides - 1}
            className={`flex items-center gap-1 px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all ${
              currentSlide === totalSlides - 1
                ? 'opacity-30 cursor-not-allowed text-slate-500'
                : 'bg-emerald-500 hover:bg-emerald-400 text-slate-950 shadow-md shadow-emerald-500/20 active:scale-95'
            }`}
            title="Slide Berikutnya (Panah Kanan / Spasi)"
          >
            <span>{currentSlide === totalSlides - 1 ? 'Selesai' : 'Lanjut'}</span>
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>

      </div>

      {/* Keyboard Shortcuts Pill (Subtle hint) */}
      <div className="hidden md:flex items-center justify-center gap-4 mt-2 text-[10px] text-slate-400 font-mono">
        <span className="flex items-center gap-1">
          <Keyboard className="w-3 h-3 text-slate-400" />
          <span>Navigasi: <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">←</kbd> <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">→</kbd> / <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">Spasi</kbd></span>
        </span>
        <span>•</span>
        <span>Layar Penuh: <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">F</kbd></span>
        <span>•</span>
        <span>Daftar Slide: <kbd className="px-1.5 py-0.5 rounded bg-slate-900 border border-white/10 text-slate-300">G</kbd></span>
      </div>
    </div>
  );
};
