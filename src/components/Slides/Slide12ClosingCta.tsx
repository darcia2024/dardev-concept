import React from 'react';
import { MessageCircle, Printer, ArrowRight, Sparkles, CheckCircle2, ShieldCheck } from 'lucide-react';
import confetti from 'canvas-confetti';
import { PROPOSAL_META } from '../../data/proposalData';
import { sound } from '../../utils/audio';

interface SlideProps {
  onJumpToCalculator?: () => void;
}

export const Slide12ClosingCta: React.FC<SlideProps> = ({ onJumpToCalculator }) => {
  const handleWhatsApp = () => {
    sound.playSuccess();
    try {
      confetti({
        particleCount: 100,
        spread: 80,
        origin: { y: 0.6 }
      });
    } catch {
      // Fallback
    }

    const message = encodeURIComponent(
      `Halo, kami dari Al Madroj telah meninjau proposal website penawaran platform kelas. Kami ingin menjadwalkan diskusi singkat untuk membahas langkah berikutnya.`
    );
    window.open(`https://wa.me/${PROPOSAL_META.contactWhatsApp}?text=${message}`, '_blank');
  };

  const handlePrint = () => {
    sound.playClick();
    window.print();
  };

  return (
    <div className="w-full max-w-4xl mx-auto flex flex-col items-center justify-center text-center py-6 sm:py-10">
      
      {/* Eyebrow badge */}
      <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-xs font-mono uppercase tracking-widest mb-6">
        <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
        <span>Langkah Selanjutnya</span>
      </div>

      {/* Headline */}
      <h2 className="font-display font-extrabold text-3xl sm:text-5xl text-white max-w-3xl leading-tight mb-4">
        Siap Membawa Platform Kelas{' '}
        <span className="bg-gradient-to-r from-emerald-400 via-teal-300 to-cyan-400 bg-clip-text text-transparent">
          Al Madroj
        </span>{' '}
        ke Level Berikutnya?
      </h2>

      <p className="text-sm sm:text-base text-slate-300 max-w-xl leading-relaxed mb-8">
        Mari diskusikan kebutuhan spesifik Anda. Kami siap membantu mewujudkan portal kelas digital yang rapi, aman, dan mudah dioperasikan.
      </p>

      {/* 3 Simple Next Steps */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 w-full mb-10 text-left">
        <div className="p-4 rounded-2xl bg-slate-900/70 border border-white/10">
          <div className="text-xs font-mono text-emerald-400 font-bold mb-1">LANGKAH 1</div>
          <div className="font-semibold text-sm text-white mb-1">Pilih Paket</div>
          <p className="text-xs text-slate-400 leading-relaxed">
            Tentukan paket yang sesuai budget dan kebutuhan operasional saat ini.
          </p>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/70 border border-white/10">
          <div className="text-xs font-mono text-cyan-400 font-bold mb-1">LANGKAH 2</div>
          <div className="font-semibold text-sm text-white mb-1">Diskusi Singkat</div>
          <p className="text-xs text-slate-400 leading-relaxed">
            Penyelarasan silabus materi, jadwal kelas, dan branding warna Al Madroj.
          </p>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/70 border border-white/10">
          <div className="text-xs font-mono text-amber-400 font-bold mb-1">LANGKAH 3</div>
          <div className="font-semibold text-sm text-white mb-1">Mulai Pengerjaan</div>
          <p className="text-xs text-slate-400 leading-relaxed">
            Pembayaran DP 50%, kick-off pengerjaan, dan demo versi beta dalam hitungan hari.
          </p>
        </div>
      </div>

      {/* Big Action Buttons */}
      <div className="flex flex-col sm:flex-row items-center gap-4 w-full max-w-md justify-center mb-8">
        
        <button
          onClick={handleWhatsApp}
          className="w-full sm:w-auto px-8 py-4 rounded-2xl bg-gradient-to-r from-emerald-500 to-teal-400 hover:from-emerald-400 hover:to-teal-300 text-slate-950 font-display font-bold text-sm sm:text-base shadow-xl shadow-emerald-500/25 flex items-center justify-center gap-2.5 transition-all transform hover:-translate-y-0.5 active:scale-95 group"
        >
          <MessageCircle className="w-5 h-5 transition-transform group-hover:scale-110" />
          <span>Hubungi via WhatsApp</span>
        </button>

        {onJumpToCalculator && (
          <button
            onClick={() => {
              sound.playClick();
              onJumpToCalculator();
            }}
            className="w-full sm:w-auto px-6 py-4 rounded-2xl bg-slate-900 hover:bg-slate-800 text-white font-semibold text-xs sm:text-sm border border-white/10 transition-all flex items-center justify-center gap-2"
          >
            <span>Buka Kalkulator Harga</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        )}

      </div>

      {/* Print PDF trigger */}
      <div className="flex items-center gap-2 text-xs text-slate-400">
        <button
          onClick={handlePrint}
          className="hover:text-emerald-400 underline underline-offset-4 flex items-center gap-1.5 transition-colors"
        >
          <Printer className="w-3.5 h-3.5" />
          <span>Cetak atau Simpan Dokumen Ini sebagai PDF</span>
        </button>
      </div>

    </div>
  );
};
