import React from 'react';
import { Clock, ShieldAlert, CheckCircle2, TrendingUp, Sparkles, Users } from 'lucide-react';

export const RoiSimulator: React.FC = () => {
  return (
    <div className="w-full max-w-5xl mx-auto glass-panel rounded-3xl p-5 sm:p-8 border border-white/10 shadow-2xl">
      
      {/* Header */}
      <div className="text-center max-w-2xl mx-auto mb-8">
        <span className="text-xs font-mono uppercase tracking-wider text-emerald-400 bg-emerald-500/10 px-3 py-1 rounded-full border border-emerald-500/20">
          Dampak Nyata Terhadap Operasional
        </span>
        <h3 className="font-display font-bold text-2xl sm:text-3xl text-white mt-3">
          Mengapa Platform Ini adalah Investasi Menguntungkan?
        </h3>
        <p className="text-sm text-slate-300 mt-2">
          Bukan sekadar biaya membuat website, melainkan aset digital yang membebaskan waktu tim dan melipatgandakan nilai kelas Al Madroj.
        </p>
      </div>

      {/* Comparison Grid: Old Manual Way vs New Platform Way */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        
        {/* Old Way: Manual Chat & Drive */}
        <div className="p-6 rounded-3xl bg-rose-950/20 border border-rose-500/20 flex flex-col justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 text-rose-400 font-display font-bold text-lg mb-4">
              <ShieldAlert className="w-5 h-5 flex-shrink-0" />
              <span>Cara Manual Lama (Tanpa Platform)</span>
            </div>

            <ul className="flex flex-col gap-3 text-xs sm:text-sm text-slate-300">
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-rose-400 mt-2 flex-shrink-0" />
                <span><strong>Admin Lelah & Keteteran:</strong> Harus membalas chat WA satu per satu untuk kirim nomor rekening, rekap transfer di Excel, dan kirim link Google Drive.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-rose-400 mt-2 flex-shrink-0" />
                <span><strong>Materi Rawan Bocor:</strong> Link Google Drive atau rekaman Zoom sangat mudah di-forward/disebarkan gratis ke orang yang tidak membayar.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-rose-400 mt-2 flex-shrink-0" />
                <span><strong>Peserta Bingung & Komplain:</strong> Peserta sering menanyakan ulang link pertemuan dan rekaman bab sebelumnya yang tertimbun chat grup WA.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-rose-400 mt-2 flex-shrink-0" />
                <span><strong>Persepsi Nilai Terbatas:</strong> Sulit menaikkan harga tiket kelas jika sistem belajar masih terasa seperti grup WA biasa.</span>
              </li>
            </ul>
          </div>

          <div className="p-3.5 rounded-2xl bg-rose-950/40 border border-rose-500/30 text-rose-300 text-xs text-center font-medium">
            ⚠️ Membuang 20-30 jam waktu kerja staf admin setiap ada batch kelas baru
          </div>
        </div>

        {/* New Way: Platform Mandiri */}
        <div className="p-6 rounded-3xl bg-emerald-950/30 border border-emerald-500/40 flex flex-col justify-between gap-4 shadow-xl shadow-emerald-500/5">
          <div>
            <div className="flex items-center gap-2 text-emerald-400 font-display font-bold text-lg mb-4">
              <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
              <span>Dengan Platform Mandiri Al Madroj</span>
            </div>

            <ul className="flex flex-col gap-3 text-xs sm:text-sm text-slate-200">
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-2 flex-shrink-0" />
                <span><strong>Otomasi & Tertata Rapi:</strong> Pendaftaran, upload bukti bayar, dan aktivasi terpusat di dashboard admin. Cukup 1 klik approve.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-2 flex-shrink-0" />
                <span><strong>Materi Terlindungi:</strong> Video dan materi hanya bisa diakses oleh murid yang memiliki akun resmi dan sudah diverifikasi.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-2 flex-shrink-0" />
                <span><strong>Pengalaman Belajar Premium:</strong> Murid belajar nyaman dari laptop/HP, melihat daftar silabus berurutan, dan progress materi terpantau.</span>
              </li>
              <li className="flex items-start gap-2.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-2 flex-shrink-0" />
                <span><strong>Kredibilitas & Daya Jual Tinggi:</strong> Al Madroj tampil sebagai lembaga pendidikan profesional yang bonafide dan terpercaya.</span>
              </li>
            </ul>
          </div>

          <div className="p-3.5 rounded-2xl bg-emerald-500/15 border border-emerald-500/40 text-emerald-300 text-xs text-center font-semibold">
            ✨ Hemat hingga 80% waktu operasional + siap menampung ribuan peserta
          </div>
        </div>

      </div>

      {/* 3 Metric Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="p-4 rounded-2xl bg-slate-900/80 border border-white/5 flex items-center gap-3.5">
          <div className="p-3 rounded-xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
            <Clock className="w-5 h-5" />
          </div>
          <div>
            <div className="font-display font-bold text-xl text-white">80% Waktu</div>
            <div className="text-xs text-slate-400">Kerja admin terpangkas</div>
          </div>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/80 border border-white/5 flex items-center gap-3.5">
          <div className="p-3 rounded-xl bg-cyan-500/10 text-cyan-400 border border-cyan-500/20">
            <Users className="w-5 h-5" />
          </div>
          <div>
            <div className="font-display font-bold text-xl text-white">100% Mandiri</div>
            <div className="text-xs text-slate-400">Peserta akses via login sendiri</div>
          </div>
        </div>

        <div className="p-4 rounded-2xl bg-slate-900/80 border border-white/5 flex items-center gap-3.5">
          <div className="p-3 rounded-xl bg-amber-500/10 text-amber-400 border border-amber-500/20">
            <TrendingUp className="w-5 h-5" />
          </div>
          <div>
            <div className="font-display font-bold text-xl text-white">Investasi Aset</div>
            <div className="text-xs text-slate-400">Dapat dipakai berulang tanpa batas</div>
          </div>
        </div>
      </div>

    </div>
  );
};
