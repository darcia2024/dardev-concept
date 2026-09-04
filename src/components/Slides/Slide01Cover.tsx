import React from 'react';
import { ArrowRight, Sparkles, ShieldCheck, Zap, Laptop, BookOpen, MonitorPlay } from 'lucide-react';
import { PROPOSAL_META } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onNext?: () => void;
  onSelectPackage?: (id: 'starter' | 'standard' | 'pro') => void;
  onOpenDemo?: () => void;
}

export const Slide01Cover: React.FC<SlideProps> = ({ onNext, onOpenDemo }) => {
  return (
    <div className="w-full max-w-5xl mx-auto flex flex-col items-center justify-center text-center py-6 sm:py-12">
      
      {/* Eyebrow badge */}
      <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-xs font-mono uppercase tracking-widest mb-6 animate-pulse">
        <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
        <span>Dokumen Resmi Penawaran Platform Digital</span>
      </div>

      {/* Main Title */}
      <h1 className="font-display font-extrabold text-4xl sm:text-6xl lg:text-7xl tracking-tight text-white max-w-4xl leading-[1.1] mb-6">
        Platform Belajar Modern untuk{' '}
        <span className="bg-gradient-to-r from-emerald-400 via-teal-300 to-cyan-400 bg-clip-text text-transparent">
          Al Madroj
        </span>
      </h1>

      {/* Subtitle / Value prop in layman terms */}
      <p className="text-base sm:text-xl text-slate-300 max-w-2xl leading-relaxed mb-8 font-light">
        Ubah pengelolaan kelas manual yang memakan waktu menjadi <strong className="text-white font-semibold">sistem mandiri yang rapi, profesional, dan otomatis</strong>, mulai dari pendaftaran hingga akses materi belajar.
      </p>

      {/* 3 Core Pillars */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 w-full max-w-3xl mb-10 text-left">
        
        <div className="p-4 rounded-2xl bg-slate-900/60 border border-white/10 hover:border-emerald-500/30 transition-colors">
          <div className="w-8 h-8 rounded-xl bg-emerald-500/15 text-emerald-400 flex items-center justify-center mb-3">
            <Zap className="w-4 h-4" />
          </div>
          <h4 className="font-display font-bold text-sm text-white mb-1">Mulai Fleksibel</h4>
          <p className="text-xs text-slate-400 leading-relaxed">
            Pilihan paket mulai <strong>Rp 2,2 Juta</strong>, siap upgrade bertahap seiring pertumbuhan program.
          </p>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/60 border border-white/10 hover:border-cyan-500/30 transition-colors">
          <div className="w-8 h-8 rounded-xl bg-cyan-500/15 text-cyan-400 flex items-center justify-center mb-3">
            <Laptop className="w-4 h-4" />
          </div>
          <h4 className="font-display font-bold text-sm text-white mb-1">Akses Mandiri Peserta</h4>
          <p className="text-xs text-slate-400 leading-relaxed">
            Peserta punya akun sendiri, video materi aman terkunci, admin bebas dari kirim link manual.
          </p>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/60 border border-white/10 hover:border-amber-500/30 transition-colors">
          <div className="w-8 h-8 rounded-xl bg-amber-500/15 text-amber-400 flex items-center justify-center mb-3">
            <ShieldCheck className="w-4 h-4" />
          </div>
          <h4 className="font-display font-bold text-sm text-white mb-1">Skema Termin Aman</h4>
          <p className="text-xs text-slate-400 leading-relaxed">
            Pembayaran bertahap (DP 50% → Demo Beta 30% → Handover 20%) + garansi bug fixing.
          </p>
        </div>

      </div>

      {/* CTA Button */}
      <div className="flex flex-col sm:flex-row items-center gap-3">
      {onNext && (
        <button
          onClick={() => {
            sound.playSlide();
            onNext();
          }}
          className="group px-8 py-4 rounded-2xl bg-gradient-to-r from-emerald-500 to-teal-400 hover:from-emerald-400 hover:to-teal-300 text-slate-950 font-display font-bold text-base shadow-xl shadow-emerald-500/25 flex items-center gap-3 transition-all transform hover:-translate-y-0.5 active:scale-95"
        >
          <span>Pelajari Rincian Penawaran</span>
          <ArrowRight className="w-5 h-5 group-hover:translate-x-1.5 transition-transform" />
        </button>
      )}
      {onOpenDemo && (
        <button
          onClick={() => {
            sound.playClick();
            onOpenDemo();
          }}
          className="px-7 py-4 rounded-2xl bg-slate-900 hover:bg-slate-800 text-white font-display font-bold text-base border border-white/10 flex items-center gap-3 transition-all active:scale-95"
        >
          <MonitorPlay className="w-5 h-5 text-emerald-400" />
          <span>Lihat Demo Pro LMS</span>
        </button>
      )}
      </div>

      {/* Proposal meta info */}
      <div className="mt-10 flex items-center gap-4 text-xs text-slate-500 font-mono">
        <span>Ditujukan untuk: <strong>Tim Manajemen Al Madroj</strong></span>
        <span>•</span>
        <span>Masa Berlaku: 30 Hari</span>
      </div>

    </div>
  );
};
