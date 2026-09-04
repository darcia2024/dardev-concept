import React, { useState } from 'react';
import { HelpCircle, ChevronDown, AlertCircle, Info, Check } from 'lucide-react';
import { FAQS, NOT_INCLUDED_ITEMS } from '../../data/proposalData';
import { sound } from '../../utils/audio';

export const Slide11FaqScope: React.FC = () => {
  const [openFaq, setOpenFaq] = useState<number | null>(0);

  const toggleFaq = (idx: number) => {
    sound.playClick();
    setOpenFaq(openFaq === idx ? null : idx);
  };

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-6 sm:p-10 border border-white/10 shadow-2xl">
      
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto mb-8">
        <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 bg-cyan-500/10 px-3 py-1 rounded-full border border-cyan-500/20">
          Kejelasan & Integritas Kerja
        </span>
        <h3 className="font-display font-bold text-2xl sm:text-3xl text-white mt-3">
          Transparansi Scope & Hal yang Perlu Diketahui
        </h3>
        <p className="text-sm text-slate-300 mt-2">
          Kami menjunjung tinggi keterbukaan agar kerjasama berjalan lancar tanpa ada biaya siluman atau kesalahpahaman.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left: What is Not Included / Catatan Transparansi (5 cols) */}
        <div className="lg:col-span-5 p-5 sm:p-6 rounded-3xl bg-slate-900/80 border border-white/10 space-y-4">
          <div className="flex items-center gap-2 text-amber-400 font-display font-bold text-sm">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>Belum Termasuk dalam Paket Dasar:</span>
          </div>

          <div className="space-y-3">
            {NOT_INCLUDED_ITEMS.map((item, i) => (
              <div key={i} className="text-xs border-b border-white/5 pb-2.5 last:border-0 last:pb-0">
                <div className="font-semibold text-slate-200 mb-0.5">• {item.title}</div>
                <p className="text-[11px] text-slate-400 leading-relaxed">{item.desc}</p>
              </div>
            ))}
          </div>

          <div className="p-3 rounded-xl bg-slate-950/80 border border-white/5 text-[11px] text-slate-400">
            ℹ️ <em>Semua kebutuhan pihak ketiga di atas siap kami bantu dan dampingi proses pendaftarannya secara gratis.</em>
          </div>
        </div>

        {/* Right: FAQ Accordions (7 cols) */}
        <div className="lg:col-span-7 space-y-3">
          <div className="flex items-center gap-2 text-white font-display font-bold text-base mb-2">
            <HelpCircle className="w-4 h-4 text-emerald-400" />
            <span>Pertanyaan yang Sering Diajukan (FAQ):</span>
          </div>

          {FAQS.map((faq, idx) => {
            const isOpen = openFaq === idx;
            return (
              <div
                key={idx}
                className={`rounded-2xl border transition-all duration-200 overflow-hidden ${
                  isOpen
                    ? 'bg-slate-900/90 border-emerald-500/40'
                    : 'bg-slate-900/40 border-white/5 hover:border-white/15'
                }`}
              >
                <button
                  onClick={() => toggleFaq(idx)}
                  className="w-full p-4 text-left flex items-center justify-between gap-3 text-xs sm:text-sm font-semibold text-white"
                >
                  <span className={isOpen ? 'text-emerald-300' : 'text-slate-200'}>
                    {faq.question}
                  </span>
                  <ChevronDown className={`w-4 h-4 text-slate-400 flex-shrink-0 transition-transform ${
                    isOpen ? 'rotate-180 text-emerald-400' : ''
                  }`} />
                </button>

                {isOpen && (
                  <div className="px-4 pb-4 text-xs text-slate-300 leading-relaxed border-t border-white/5 pt-3 animate-fade-in">
                    {faq.answer}
                  </div>
                )}
              </div>
            );
          })}
        </div>

      </div>

    </div>
  );
};
