import React, { useState } from 'react';
import { Check, MessageCircle, Sparkles, HelpCircle, ShieldCheck } from 'lucide-react';
import confetti from 'canvas-confetti';
import { PACKAGES, ADD_ONS, PROPOSAL_META } from '../data/proposalData';
import { sound } from '../utils/audio';

export const InteractiveCalculator: React.FC = () => {
  const [selectedPackageId, setSelectedPackageId] = useState<'starter' | 'standard' | 'pro'>('standard');
  const [selectedAddOns, setSelectedAddOns] = useState<string[]>(['wa_notification']);

  const currentPackage = PACKAGES.find((p) => p.id === selectedPackageId) || PACKAGES[1];

  const toggleAddOn = (id: string) => {
    sound.playClick();
    setSelectedAddOns((prev) =>
      prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]
    );
  };

  // Calculate totals
  const addOnsTotal = selectedAddOns.reduce((sum, addOnId) => {
    const item = ADD_ONS.find((a) => a.id === addOnId);
    return sum + (item ? item.price : 0);
  }, 0);

  const grandTotal = currentPackage.price + addOnsTotal;

  // Calculate milestone payments based on package rules
  const isStarter = currentPackage.id === 'starter';
  const dpAmount = Math.round(grandTotal * 0.5);
  const betaAmount = isStarter ? 0 : Math.round(grandTotal * 0.3);
  const handoverAmount = isStarter ? Math.round(grandTotal * 0.5) : grandTotal - dpAmount - betaAmount;

  const handleOrderWhatsApp = () => {
    sound.playSuccess();
    try {
      confetti({
        particleCount: 80,
        spread: 70,
        origin: { y: 0.7 }
      });
    } catch {
      // Fallback if canvas-confetti is not loaded
    }

    const selectedAddOnNames = selectedAddOns
      .map((id) => ADD_ONS.find((a) => a.id === id)?.name)
      .filter(Boolean);

    const message = `Halo Pengembang Platform Al Madroj,

Saya telah menghitung simulasi di website proposal dan tertarik untuk mendiskusikan paket berikut:

Paket Utama: Paket ${currentPackage.name} (${currentPackage.formattedPrice})
${selectedAddOnNames.length > 0 ? `Add-on Pilihan:\n${selectedAddOnNames.map((n) => `   - ${n}`).join('\n')}\n` : ''}
Estimasi Total Investasi: Rp ${grandTotal.toLocaleString('id-ID')}
Rincian Skema Bertahap:
   1. DP 50%: Rp ${dpAmount.toLocaleString('id-ID')}
   ${!isStarter ? `2. Uji Coba Beta (30%): Rp ${betaAmount.toLocaleString('id-ID')}\n   ` : ''}${isStarter ? '2. Sebelum Handover (50%)' : '3. Sebelum Handover (20%)'}: Rp ${handoverAmount.toLocaleString('id-ID')}

Mohon informasi langkah selanjutnya untuk penjadwalan diskusi dan persiapan project ini. Terima kasih!`;

    const encoded = encodeURIComponent(message);
    window.open(`https://wa.me/${PROPOSAL_META.contactWhatsApp}?text=${encoded}`, '_blank');
  };

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-5 sm:p-8 border border-white/10 shadow-2xl">
      
      {/* Title & Explainer */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-white/10 pb-6 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-2.5 py-0.5 rounded-full border border-emerald-500/20">
              Kalkulator Interaktif
            </span>
            <span className="text-xs text-slate-400">• Hitung Langsung di Sini</span>
          </div>
          <h3 className="font-display font-bold text-xl sm:text-2xl text-white">
            Simulasi Paket & Rincian Termin Pembayaran
          </h3>
          <p className="text-sm text-slate-300 mt-1">
            Pilih paket utama dan tambahkan fitur opsional sesuai target operasional Al Madroj.
          </p>
        </div>

        <div className="flex items-center gap-2 px-3.5 py-2 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-300 text-xs font-medium">
          <ShieldCheck className="w-4 h-4 text-emerald-400" />
          <span>Skema Bertahap & 100% Transparan</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left Col: Step 1 & Step 2 (7 cols) */}
        <div className="lg:col-span-7 flex flex-col gap-6">
          
          {/* Step 1: Choose Base Package */}
          <div>
            <label className="text-xs font-mono uppercase tracking-wider text-slate-400 block mb-3">
              Langkah 1: Pilih Paket Utama
            </label>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {PACKAGES.map((pkg) => {
                const isSelected = selectedPackageId === pkg.id;
                return (
                  <div
                    key={pkg.id}
                    onClick={() => {
                      sound.playClick();
                      setSelectedPackageId(pkg.id);
                    }}
                    className={`relative p-4 rounded-2xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-slate-900/90 border-emerald-500 shadow-lg shadow-emerald-500/10 ring-2 ring-emerald-500/30'
                        : 'bg-slate-900/40 border-white/10 hover:border-white/20 hover:bg-slate-900/70'
                    }`}
                  >
                    {pkg.isRecommended && (
                      <span className="absolute -top-2.5 left-1/2 -translate-x-1/2 text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-gradient-to-r from-emerald-500 to-cyan-500 text-slate-950 shadow-sm">
                        Rekomendasi
                      </span>
                    )}

                    <div className="flex items-center justify-between mb-2">
                      <span className="font-display font-bold text-base text-white">{pkg.name}</span>
                      <div className={`w-4 h-4 rounded-full border flex items-center justify-center ${
                        isSelected ? 'border-emerald-500 bg-emerald-500' : 'border-slate-600'
                      }`}>
                        {isSelected && <Check className="w-2.5 h-2.5 text-slate-950 stroke-[3]" />}
                      </div>
                    </div>

                    <div className="text-emerald-400 font-display font-bold text-lg mb-1">
                      {pkg.formattedPrice}
                    </div>
                    <p className="text-[11px] text-slate-400 line-clamp-2 leading-tight">
                      {pkg.tagline}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Step 2: Choose Add-ons */}
          <div>
            <label className="text-xs font-mono uppercase tracking-wider text-slate-400 block mb-3">
              Langkah 2: Tambahan Fitur Opsional (Add-ons)
            </label>
            <div className="flex flex-col gap-2.5">
              {ADD_ONS.map((addon) => {
                const isChecked = selectedAddOns.includes(addon.id);
                return (
                  <div
                    key={addon.id}
                    onClick={() => toggleAddOn(addon.id)}
                    className={`p-3.5 rounded-2xl border cursor-pointer transition-all flex items-start justify-between gap-3 ${
                      isChecked
                        ? 'bg-emerald-500/10 border-emerald-500/40 text-white'
                        : 'bg-slate-900/40 border-white/5 hover:border-white/15 text-slate-300'
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className={`mt-0.5 w-4 h-4 rounded-md border flex items-center justify-center flex-shrink-0 transition-colors ${
                        isChecked ? 'border-emerald-500 bg-emerald-500' : 'border-slate-600'
                      }`}>
                        {isChecked && <Check className="w-3 h-3 text-slate-950 stroke-[3]" />}
                      </div>
                      <div>
                        <div className="font-semibold text-xs sm:text-sm text-white flex items-center gap-1.5 flex-wrap">
                          <span>{addon.name}</span>
                        </div>
                        <p className="text-xs text-slate-400 mt-0.5 leading-relaxed">
                          {addon.description}
                        </p>
                        <p className="text-[11px] text-emerald-400/90 mt-1 flex items-center gap-1">
                          <Sparkles className="w-3 h-3" />
                          <span>{addon.benefit}</span>
                        </p>
                      </div>
                    </div>

                    <div className="text-right flex-shrink-0">
                      <span className="font-mono text-xs sm:text-sm font-semibold text-emerald-400 block">
                        {addon.formattedPrice}
                      </span>
                      {addon.isThirdPartyNote && (
                        <span className="text-[9px] text-slate-500 block">*biaya provider</span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

        </div>

        {/* Right Col: Calculation Summary & Payment Schedule (5 cols) */}
        <div className="lg:col-span-5 glass-card rounded-3xl p-5 sm:p-6 border border-emerald-500/30 bg-gradient-to-b from-slate-900/90 to-slate-950/90 flex flex-col justify-between gap-5 sticky top-20">
          
          <div>
            <div className="flex items-center justify-between border-b border-white/10 pb-3 mb-4">
              <h4 className="font-display font-bold text-white text-base">Rangkuman Estimasi</h4>
              <span className="text-[11px] font-mono text-slate-400">Termin Bertahap</span>
            </div>

            {/* Breakdown item list */}
            <div className="flex flex-col gap-2 text-xs border-b border-white/10 pb-4 mb-4">
              <div className="flex items-center justify-between text-slate-300">
                <span>Paket {currentPackage.name}</span>
                <span className="font-mono font-medium text-white">{currentPackage.formattedPrice}</span>
              </div>
              
              {selectedAddOns.map((id) => {
                const item = ADD_ONS.find((a) => a.id === id);
                if (!item) return null;
                return (
                  <div key={id} className="flex items-center justify-between text-slate-400">
                    <span className="truncate pr-2">• {item.name.split('(')[0]}</span>
                    <span className="font-mono font-medium text-emerald-400 flex-shrink-0">
                      +{item.formattedPrice.replace('+', '')}
                    </span>
                  </div>
                );
              })}

              {selectedAddOns.length === 0 && (
                <div className="text-[11px] text-slate-500 italic">Tidak ada add-on dipilih</div>
              )}
            </div>

            {/* Total Display */}
            <div className="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 mb-5">
              <span className="text-xs text-slate-400 uppercase font-mono tracking-wider block mb-1">
                Total Investasi Proyek
              </span>
              <div className="flex items-baseline justify-between">
                <div className="font-display font-extrabold text-2xl sm:text-3xl text-emerald-400">
                  Rp {grandTotal.toLocaleString('id-ID')}
                </div>
                <span className="text-[11px] text-slate-400">Nett / Sesuai Scope</span>
              </div>
            </div>

            {/* Payment Milestones (Bertahap) */}
            <div className="flex flex-col gap-2 mb-5">
              <div className="flex items-center justify-between text-xs text-slate-400 mb-1">
                <span className="font-mono uppercase">Rencana Pembayaran Bertahap:</span>
                <HelpCircle className="w-3.5 h-3.5 text-slate-500" />
              </div>

              {/* Termin 1 DP */}
              <div className="p-2.5 rounded-xl bg-slate-900/90 border border-white/5 flex items-center justify-between text-xs">
                <div>
                  <div className="font-semibold text-white">Termin 1 (DP 50%)</div>
                  <div className="text-[10px] text-slate-400">Saat kick-off & perancangan</div>
                </div>
                <span className="font-mono font-bold text-cyan-400">
                  Rp {dpAmount.toLocaleString('id-ID')}
                </span>
              </div>

              {/* Termin 2 Beta */}
              {!isStarter && (
                <div className="p-2.5 rounded-xl bg-slate-900/90 border border-white/5 flex items-center justify-between text-xs">
                  <div>
                    <div className="font-semibold text-white">Termin 2 (Beta 30%)</div>
                    <div className="text-[10px] text-slate-400">Saat platform siap diuji coba</div>
                  </div>
                  <span className="font-mono font-bold text-amber-400">
                    Rp {betaAmount.toLocaleString('id-ID')}
                  </span>
                </div>
              )}

              {/* Termin 3 Handover */}
              <div className="p-2.5 rounded-xl bg-slate-900/90 border border-white/5 flex items-center justify-between text-xs">
                <div>
                  <div className="font-semibold text-white">
                    {isStarter ? 'Termin 2 (Handover 50%)' : 'Termin 3 (Handover 20%)'}
                  </div>
                  <div className="text-[10px] text-slate-400">Sebelum serah terima & live</div>
                </div>
                <span className="font-mono font-bold text-emerald-400">
                  Rp {handoverAmount.toLocaleString('id-ID')}
                </span>
              </div>
            </div>
          </div>

          {/* WhatsApp CTA */}
          <button
            onClick={handleOrderWhatsApp}
            className="w-full py-3.5 px-4 rounded-2xl bg-gradient-to-r from-emerald-500 to-teal-400 hover:from-emerald-400 hover:to-teal-300 text-slate-950 font-bold text-sm transition-all shadow-lg shadow-emerald-500/25 flex items-center justify-center gap-2 group active:scale-[0.98]"
          >
            <MessageCircle className="w-5 h-5 transition-transform group-hover:scale-110" />
            <span>Kirim Rincian Ini ke WhatsApp</span>
          </button>

        </div>

      </div>

    </div>
  );
};
