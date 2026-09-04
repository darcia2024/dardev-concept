import React from 'react';
import { 
  Maximize2, 
  Minimize2, 
  Volume2, 
  VolumeX, 
  Printer, 
  Layers, 
  FileText, 
  MessageCircle, 
  Grid,
  MonitorPlay
} from 'lucide-react';
import { PROPOSAL_META } from '../data/proposalData';
import { sound } from '../utils/audio';

interface NavigationProps {
  currentSlide: number;
  totalSlides: number;
  currentSlideTitle: string;
  isFullscreen: boolean;
  onToggleFullscreen: () => void;
  viewMode: 'presentation' | 'document' | 'demo';
  onToggleViewMode: (mode: 'presentation' | 'document' | 'demo') => void;
  soundEnabled: boolean;
  onToggleSound: () => void;
  onOpenThumbnails: () => void;
}

export const Navigation: React.FC<NavigationProps> = ({
  currentSlide,
  totalSlides,
  currentSlideTitle,
  isFullscreen,
  onToggleFullscreen,
  viewMode,
  onToggleViewMode,
  soundEnabled,
  onToggleSound,
  onOpenThumbnails,
}) => {
  const handlePrint = () => {
    sound.playClick();
    window.print();
  };

  const handleWhatsApp = () => {
    sound.playClick();
    const message = encodeURIComponent(
      `Halo, saya sedang meninjau website proposal Platform Kelas Al Madroj dan ingin berdiskusi lebih lanjut.`
    );
    window.open(`https://wa.me/${PROPOSAL_META.contactWhatsApp}?text=${message}`, '_blank');
  };

  return (
    <header className="sticky top-0 z-40 w-full glass-panel border-b border-white/10 px-4 lg:px-8 py-3 transition-all duration-300 no-print">
      <div className="max-w-7xl mx-auto flex items-center justify-between gap-4">
        
        {/* Brand & Client Name */}
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-emerald-500 to-cyan-500 p-0.5 shadow-lg shadow-emerald-500/20 flex items-center justify-center">
            <img src="/logo.svg" alt="Al Madroj Logo" className="w-full h-full rounded-[10px] object-cover" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-display font-bold text-lg tracking-tight text-white">AL MADROJ</span>
              <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                PROPOSAL
              </span>
            </div>
            <p className="text-xs text-slate-400 hidden sm:block">Pengembangan Platform Kelas Digital</p>
          </div>
        </div>

        {/* Current Slide Indicator (Presentation Mode) */}
        {viewMode === 'presentation' && (
          <div 
            onClick={onOpenThumbnails}
            className="hidden md:flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900/80 border border-white/10 hover:border-emerald-500/40 cursor-pointer transition-all group"
            title="Klik untuk melihat semua slide"
          >
            <Grid className="w-3.5 h-3.5 text-emerald-400 group-hover:scale-110 transition-transform" />
            <span className="text-xs font-mono text-slate-400">
              Slide <strong className="text-white">{String(currentSlide + 1).padStart(2, '0')}</strong> / {String(totalSlides).padStart(2, '0')}
            </span>
            <span className="text-slate-600">|</span>
            <span className="text-xs text-slate-300 max-w-[220px] truncate font-medium">
              {currentSlideTitle}
            </span>
          </div>
        )}

        {/* Action Controls */}
        <div className="flex items-center gap-1.5 sm:gap-2">
          
          {/* Mode Switcher */}
          <div className="flex items-center bg-slate-900/90 p-1 rounded-xl border border-white/10">
            <button
              onClick={() => {
                sound.playClick();
                onToggleViewMode('presentation');
              }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium transition-all ${
                viewMode === 'presentation'
                  ? 'bg-emerald-500 text-slate-950 font-semibold shadow-md'
                  : 'text-slate-400 hover:text-white hover:bg-white/5'
              }`}
              title="Mode Presentasi Slide"
            >
              <Layers className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Slide Deck</span>
            </button>
            <button
              onClick={() => {
                sound.playClick();
                onToggleViewMode('document');
              }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium transition-all ${
                viewMode === 'document'
                  ? 'bg-emerald-500 text-slate-950 font-semibold shadow-md'
                  : 'text-slate-400 hover:text-white hover:bg-white/5'
              }`}
              title="Mode Dokumen Scroll"
            >
              <FileText className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Dokumen</span>
            </button>
            <button
              onClick={() => {
                sound.playClick();
                onToggleViewMode('demo');
              }}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium transition-all ${
                viewMode === 'demo'
                  ? 'bg-emerald-500 text-slate-950 font-semibold shadow-md'
                  : 'text-slate-400 hover:text-white hover:bg-white/5'
              }`}
              title="Mode Demo Platform"
            >
              <MonitorPlay className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Demo Pro</span>
            </button>
          </div>

          {/* Sound Toggle */}
          <button
            onClick={() => {
              onToggleSound();
            }}
            className={`p-2 rounded-xl border transition-all ${
              soundEnabled
                ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
                : 'bg-slate-900/80 border-white/10 text-slate-400 hover:text-white'
            }`}
            title={soundEnabled ? 'Matikan Efek Suara' : 'Nyalakan Efek Suara Navigasi'}
          >
            {soundEnabled ? <Volume2 className="w-4 h-4" /> : <VolumeX className="w-4 h-4" />}
          </button>

          {/* Fullscreen Toggle */}
          <button
            onClick={() => {
              sound.playClick();
              onToggleFullscreen();
            }}
            className="p-2 rounded-xl bg-slate-900/80 border border-white/10 text-slate-400 hover:text-white hover:border-white/20 transition-all hidden sm:flex"
            title={isFullscreen ? 'Keluar Layar Penuh (F)' : 'Layar Penuh (F)'}
          >
            {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
          </button>

          {/* Print Proposal */}
          <button
            onClick={handlePrint}
            className="p-2 rounded-xl bg-slate-900/80 border border-white/10 text-slate-400 hover:text-white hover:border-white/20 transition-all hidden md:flex"
            title="Cetak / Simpan PDF"
          >
            <Printer className="w-4 h-4" />
          </button>

          {/* Direct WhatsApp CTA */}
          <button
            onClick={handleWhatsApp}
            className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-semibold text-xs transition-all shadow-md shadow-emerald-500/20 active:scale-95"
          >
            <MessageCircle className="w-4 h-4" />
            <span className="hidden xs:inline">Konsultasi</span>
          </button>

        </div>

      </div>
    </header>
  );
};
