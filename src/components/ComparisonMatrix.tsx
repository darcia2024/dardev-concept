import React, { useState } from 'react';
import { Check, Minus, Info, HelpCircle } from 'lucide-react';
import { COMPARISON_TABLE } from '../data/proposalData';
import { sound } from '../utils/audio';

export const ComparisonMatrix: React.FC = () => {
  const [selectedCategory, setSelectedCategory] = useState<string>('Semua');
  const [activeTooltip, setActiveTooltip] = useState<string | null>(null);

  const categories = ['Semua', ...Array.from(new Set(COMPARISON_TABLE.map((row) => row.category)))];

  const filteredRows = selectedCategory === 'Semua'
    ? COMPARISON_TABLE
    : COMPARISON_TABLE.filter((r) => r.category === selectedCategory);

  const renderValue = (val: boolean | string, isPro: boolean = false) => {
    if (typeof val === 'boolean') {
      return val ? (
        <div className="flex items-center justify-center">
          <div className="w-6 h-6 rounded-full bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center">
            <Check className="w-3.5 h-3.5 text-emerald-400 stroke-[3]" />
          </div>
        </div>
      ) : (
        <div className="flex items-center justify-center">
          <Minus className="w-4 h-4 text-slate-600" />
        </div>
      );
    }
    return (
      <span className={`text-[11px] font-mono px-2 py-0.5 rounded-md text-center inline-block ${
        isPro 
          ? 'bg-amber-500/15 text-amber-300 border border-amber-500/20' 
          : 'bg-slate-800 text-slate-300 border border-white/5'
      }`}>
        {val}
      </span>
    );
  };

  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-5 sm:p-8 border border-white/10 shadow-2xl">
      
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-white/10 pb-5 mb-5">
        <div>
          <h3 className="font-display font-bold text-xl sm:text-2xl text-white">
            Matriks Perbandingan Fitur Lengkap
          </h3>
          <p className="text-xs sm:text-sm text-slate-400 mt-1">
            Penjelasan transparan perbedaan kemampuan di setiap tingkatan paket.
          </p>
        </div>

        {/* Category Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 max-w-full no-scrollbar">
          {categories.map((cat) => (
            <button
              key={cat}
              onClick={() => {
                sound.playClick();
                setSelectedCategory(cat);
              }}
              className={`px-3 py-1 rounded-xl text-xs whitespace-nowrap transition-all ${
                selectedCategory === cat
                  ? 'bg-emerald-500 text-slate-950 font-bold shadow-sm'
                  : 'bg-slate-900/60 text-slate-400 hover:text-white border border-white/5'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* Table Container */}
      <div className="overflow-x-auto rounded-2xl border border-white/10">
        <table className="w-full text-left border-collapse min-w-[620px]">
          <thead>
            <tr className="border-b border-white/10 bg-slate-900/90 text-xs font-mono uppercase text-slate-400">
              <th className="py-3.5 px-4 font-semibold text-slate-300 w-2/5">Fitur & Manfaat</th>
              <th className="py-3.5 px-3 text-center w-1/5">
                <div className="text-cyan-400 font-bold">Starter</div>
                <div className="text-[10px] text-slate-500 font-normal">Rp 2,2 Jt</div>
              </th>
              <th className="py-3.5 px-3 text-center w-1/5 bg-emerald-500/10 border-x border-emerald-500/20">
                <div className="text-emerald-300 font-bold flex items-center justify-center gap-1">
                  <span>Standard</span>
                  <span className="text-[9px] bg-emerald-500 text-slate-950 px-1.5 rounded-full">Rec</span>
                </div>
                <div className="text-[10px] text-emerald-400/80 font-normal">Rp 3,5 Jt</div>
              </th>
              <th className="py-3.5 px-3 text-center w-1/5">
                <div className="text-amber-400 font-bold">Pro LMS</div>
                <div className="text-[10px] text-slate-500 font-normal">Rp 5 Jt</div>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5 text-xs text-slate-300 bg-slate-950/40">
            {filteredRows.map((row, index) => (
              <tr key={index} className="hover:bg-white/[0.03] transition-colors group">
                <td className="py-3.5 px-4">
                  <div className="flex items-start gap-2">
                    <div>
                      <div className="font-semibold text-white group-hover:text-emerald-300 transition-colors">
                        {row.name}
                      </div>
                      <div className="text-[11px] text-slate-400 mt-0.5 leading-relaxed">
                        {row.laymanDescription}
                      </div>
                    </div>
                  </div>
                </td>
                <td className="py-3.5 px-3 text-center align-middle">
                  {renderValue(row.starter)}
                </td>
                <td className="py-3.5 px-3 text-center align-middle bg-emerald-500/5 border-x border-emerald-500/15">
                  {renderValue(row.standard)}
                </td>
                <td className="py-3.5 px-3 text-center align-middle">
                  {renderValue(row.pro, true)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Sweet Spot Highlight Callout */}
      <div className="mt-5 p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-2.5 text-emerald-300">
          <Info className="w-4 h-4 flex-shrink-0 text-emerald-400" />
          <span>
            <strong>Kesimpulan Rekomendasi:</strong> Paket Standard (Rp 3,5jt) memiliki rasio manfaat terbaik karena peserta sudah memiliki akun dan dashboard mandiri tanpa beban biaya berlebih.
          </span>
        </div>
      </div>

    </div>
  );
};
