import { PackageData, AddOnItem, FeatureComparisonRow, FaqItem, SlideItem } from '../types';

export const PROPOSAL_META = {
  clientName: 'Al Madroj',
  title: 'Penawaran Pengembangan Platform Kelas Digital',
  subtitle: 'Solusi Modern, Rapi, dan Otomatis untuk Transformasi Pembelajaran Online',
  minPrice: 'Rp 2,2 Juta',
  contactWhatsApp: '6281311506025',
  defaultWhatsAppMessage: 'Halo, saya tertarik dengan proposal penawaran platform kelas Al Madroj. Saya ingin konsultasi mengenai paket:',
  version: '2026.1',
  validUntil: '30 Hari sejak penawaran diterima'
};

export const SLIDES: SlideItem[] = [
  { id: 'cover', title: 'Ringkasan Penawaran', subtitle: 'Platform Kelas Al Madroj', category: 'Pengantar' },
  { id: 'problem-solution', title: 'Masalah vs Solusi', subtitle: 'Kenapa Al Madroj Butuh Platform Ini', category: 'Konteks' },
  { id: 'philosophy', title: 'Konsep Fleksibel', subtitle: 'Mulai Pas, Kembangkan Saat Siap', category: 'Strategi' },
  { id: 'packages-overview', title: 'Pilihan 3 Paket', subtitle: 'Starter, Standard, dan Pro', category: 'Paket' },
  { id: 'package-starter', title: 'Paket 1: Starter', subtitle: 'Rp 2.200.000 (Paling Ringan)', category: 'Detail Paket' },
  { id: 'package-standard', title: 'Paket 2: Standard', subtitle: 'Rp 3.500.000 (Rekomendasi Utama)', category: 'Detail Paket' },
  { id: 'package-pro', title: 'Paket 3: Pro LMS', subtitle: 'Rp 5.000.000 (Paling Lengkap)', category: 'Detail Paket' },
  { id: 'comparison', title: 'Perbandingan Fitur', subtitle: 'Tabel Komparasi Lengkap', category: 'Evaluasi' },
  { id: 'calculator', title: 'Kalkulator Harga', subtitle: 'Hitung Paket dan Termin Pembayaran', category: 'Interaktif' },
  { id: 'workflow', title: 'Skema Pembayaran', subtitle: 'Pembayaran Bertahap dan Garansi', category: 'Pelaksanaan' },
  { id: 'scope-faq', title: 'Catatan Scope', subtitle: 'Hal yang Belum Termasuk', category: 'Informasi' },
  { id: 'closing', title: 'Langkah Memulai', subtitle: 'Hubungi via WhatsApp', category: 'Aksi' },
];

export const PACKAGES: PackageData[] = [
  {
    id: 'starter',
    name: 'Starter',
    tagline: 'Paling Ringan untuk Mulai',
    price: 2200000,
    formattedPrice: 'Rp 2.200.000',
    bestFor: 'Al Madroj yang ingin segera online dengan website kelas profesional tanpa sistem login yang rumit.',
    laymanPitch: 'Solusi praktis jika Anda ingin punya etalase resmi berkelas. Calon peserta bisa membaca profil, memilih kelas, mendaftar, dan transfer dalam satu tempat yang rapi.',
    roiPitch: 'Hemat 5 hingga 10 jam per minggu tenaga admin dalam menjelaskan detail kelas berulang-ulang ke calon peserta.',
    bugFixingDays: 14,
    features: [
      'Domain .com gratis untuk 1 tahun pertama',
      'Landing page dan website utama Al Madroj yang kredibel',
      'Daftar kelas dan halaman detail kelas',
      'Profil pengajar, silabus materi, FAQ, dan form pendaftaran',
      'Formulir pendaftaran peserta online yang rapi',
      'Pembayaran manual via transfer bank atau QRIS ditambah upload bukti',
      'Dashboard admin sederhana untuk cek data pendaftar',
      'Manajemen konten kelas dasar (edit judul, harga, jadwal)',
      'Akses materi melalui halaman private terkontrol',
      'Tampilan responsif di HP, tablet, dan komputer',
      'Deployment online dan basic SEO',
      'Garansi perbaikan bug 14 hari setelah launch'
    ],
    colorScheme: {
      accent: '#06b6d4',
      border: 'border-slate-800',
      bgGlow: 'bg-slate-900',
      badgeBg: 'bg-slate-800',
      badgeText: 'text-slate-300'
    }
  },
  {
    id: 'standard',
    name: 'Standard',
    tagline: 'Platform Mandiri Peserta + Mayar.id Otomatis',
    isRecommended: true,
    price: 3500000,
    formattedPrice: 'Rp 3.500.000',
    bestFor: 'Pilihan paling ideal jika Al Madroj ingin beroperasi sebagai platform kelas modern sejati: peserta login mandiri, materi terkunci aman, dan pembayaran otomatis via Mayar.id.',
    laymanPitch: 'Peserta memiliki akun sendiri dan bayar otomatis via QRIS/VA Mayar.id. Begitu bayar berhasil, materi langsung terbuka di dashboard peserta secara urut per bab tanpa perlu kirim bukti transfer manual.',
    roiPitch: 'Menghemat 80% kerepotan operasional harian. Peserta merasa membeli program berbobot tinggi karena memiliki portal belajar eksklusif.',
    bugFixingDays: 30,
    features: [
      'Domain .com gratis untuk 1 tahun pertama',
      'Integrasi Payment Gateway Otomatis (Mayar.id) - QRIS & Virtual Account',
      'Semua fitur lengkap dari Paket Starter',
      'Sistem register dan login akun khusus peserta',
      'Dashboard pribadi peserta untuk melihat kelas yang dimiliki',
      'Struktur materi teratur per bab dan per pertemuan',
      'Mendukung video materi, modul teks, dan file materi',
      'Access control per kelas (hanya dibuka oleh peserta terdaftar)',
      'Admin dapat memberi atau mencabut akses peserta sewaktu-waktu',
      'Status progress belajar peserta dan riwayat aktivitas',
      'Dashboard admin lebih lengkap untuk manajemen data',
      'Sesi training admin sampai mahir mengelola platform',
      'Garansi perbaikan bug 30 hari setelah launch'
    ],
    colorScheme: {
      accent: '#10b981',
      border: 'border-emerald-600',
      bgGlow: 'bg-slate-900',
      badgeBg: 'bg-slate-800',
      badgeText: 'text-emerald-400'
    }
  },
  {
    id: 'pro',
    name: 'Pro LMS',
    tagline: 'LMS Lengkap, Mayar.id & Sertifikasi Otomatis',
    price: 5000000,
    formattedPrice: 'Rp 5.000.000',
    bestFor: 'Al Madroj yang siap berskala besar dengan sertifikasi otomatis, kuis evaluasi, absensi, pembayaran Mayar.id otomatis, dan keterlibatan banyak pengajar atau mentor.',
    laymanPitch: 'Platform berskala LMS penuh. Peserta menyelesaikan materi, mengerjakan kuis, dan langsung mendapatkan sertifikat digital otomatis. Dilengkapi fitur absensi dan akun khusus pengajar.',
    roiPitch: 'Otomatisasi 100% penerbitan sertifikat dan absensi, siap menangani ratusan hingga ribuan peserta.',
    bugFixingDays: 30,
    features: [
      'Domain .com gratis untuk 1 tahun pertama',
      'Integrasi Payment Gateway Otomatis (Mayar.id)',
      'Semua fitur lengkap dari Paket Standard',
      'Progress belajar detail per sub-materi',
      'Sistem kuis dan evaluasi sederhana per kelas',
      'Penerbitan sertifikat digital otomatis saat selesai kelas',
      'Fitur absensi dan kehadiran kelas basic',
      'Akses khusus role pengajar atau mentor basic',
      'Laporan perkembangan peserta per kelas',
      'Riwayat pembayaran, status pendaftaran, dan log akses',
      'Notifikasi status pendaftaran dan akses basic',
      'Dashboard monitoring lengkap untuk admin',
      'Prioritas revisi saat fase development',
      'Training dan handover lengkap untuk tim',
      'Garansi perbaikan bug 30 hari setelah launch'
    ],
    colorScheme: {
      accent: '#f59e0b',
      border: 'border-slate-800',
      bgGlow: 'bg-slate-900',
      badgeBg: 'bg-slate-800',
      badgeText: 'text-slate-300'
    }
  }
];

export const ADD_ONS: AddOnItem[] = [
  {
    id: 'payment_gateway_starter',
    name: 'Payment Gateway Mayar.id (Khusus Starter)',
    price: 750000,
    formattedPrice: '+ Rp 750.000',
    description: 'Integrasi Mayar.id untuk paket Starter (sudah termasuk otomatis di Standard dan Pro).',
    benefit: 'Peserta langsung aktif otomatis setelah pembayaran QRIS/VA.'
  },
  {
    id: 'wa_notification',
    name: 'Notifikasi WhatsApp Otomatis',
    price: 500000,
    formattedPrice: '+ Rp 500.000*',
    description: 'Kirim invoice, konfirmasi pembayaran, dan pengingat kelas otomatis ke WhatsApp peserta.',
    benefit: 'Tingkat keterbacaan pesan sangat tinggi dan terasa profesional.',
    isThirdPartyNote: true
  },
  {
    id: 'advanced_analytics',
    name: 'Advanced Analytics dan Laporan Finansial',
    price: 600000,
    formattedPrice: '+ Rp 600.000',
    description: 'Grafik rekap penjualan kelas, retensi peserta, dan ekspor data ke format Excel.',
    benefit: 'Memudahkan pemantauan data finansial dan perkembangan kelas.'
  },
  {
    id: 'multi_role_instructor',
    name: 'Multi-Role Pengajar Lanjutan',
    price: 750000,
    formattedPrice: '+ Rp 750.000',
    description: 'Portal mandiri bagi ustadz atau pengajar untuk upload materi dan cek data murid.',
    benefit: 'Pengajar dapat mandiri mengelola materi kelas masing-masing.'
  }
];

export const COMPARISON_TABLE: FeatureComparisonRow[] = [
  {
    category: 'Domain dan Etalase',
    name: 'Domain .com (1 tahun pertama)',
    laymanDescription: 'Alamat website resmi gratis untuk 1 tahun pertama',
    starter: true,
    standard: true,
    pro: true
  },
  {
    category: 'Domain dan Etalase',
    name: 'Website utama dan katalog kelas',
    laymanDescription: 'Halaman profil resmi Al Madroj dan daftar seluruh program belajar',
    starter: true,
    standard: true,
    pro: true
  },
  {
    category: 'Domain dan Etalase',
    name: 'Form pendaftaran',
    laymanDescription: 'Calon peserta mengisi formulir online di website',
    starter: true,
    standard: true,
    pro: true
  },
  {
    category: 'Pembayaran dan Akses',
    name: 'Sistem pembayaran',
    laymanDescription: 'Metode pembayaran yang digunakan peserta',
    starter: 'Manual Transfer',
    standard: 'Mayar.id Otomatis',
    pro: 'Mayar.id Otomatis'
  },
  {
    category: 'Pembayaran dan Akses',
    name: 'Dashboard admin',
    laymanDescription: 'Halaman pengelola untuk memverifikasi pendaftaran',
    starter: 'Basic',
    standard: 'Lengkap',
    pro: 'Lengkap'
  },
  {
    category: 'Portal Peserta',
    name: 'Akun peserta',
    laymanDescription: 'Peserta memiliki login username dan password sendiri',
    starter: false,
    standard: true,
    pro: true
  },
  {
    category: 'Portal Peserta',
    name: 'Dashboard peserta',
    laymanDescription: 'Halaman khusus murid melihat kelas yang diikuti',
    starter: false,
    standard: true,
    pro: true
  },
  {
    category: 'Materi dan Keamanan',
    name: 'Materi terstruktur per bab',
    laymanDescription: 'Video, audio, modul teks, dan file materi tersusun rapi',
    starter: 'Basic',
    standard: true,
    pro: true
  },
  {
    category: 'Materi dan Keamanan',
    name: 'Access control per kelas',
    laymanDescription: 'Materi hanya dapat dibuka oleh murid yang disetujui',
    starter: 'Basic',
    standard: true,
    pro: true
  },
  {
    category: 'Fitur Belajar',
    name: 'Progress belajar',
    laymanDescription: 'Pemantauan persentase penyelesaian materi belajar',
    starter: false,
    standard: 'Basic',
    pro: 'Advanced'
  },
  {
    category: 'Fitur Belajar',
    name: 'Quiz dan evaluasi',
    laymanDescription: 'Latihan soal pemahaman per kelas',
    starter: false,
    standard: false,
    pro: true
  },
  {
    category: 'Fitur Belajar',
    name: 'Sertifikat otomatis',
    laymanDescription: 'Sertifikat digital terbit otomatis saat kelas tuntas',
    starter: false,
    standard: false,
    pro: true
  },
  {
    category: 'Fitur Belajar',
    name: 'Absensi basic',
    laymanDescription: 'Pencatatan kehadiran peserta',
    starter: false,
    standard: false,
    pro: true
  },
  {
    category: 'Manajemen Pengajar',
    name: 'Role pengajar basic',
    laymanDescription: 'Akses khusus bagi guru atau mentor',
    starter: false,
    standard: false,
    pro: true
  },
  {
    category: 'Layanan dan Garansi',
    name: 'Training admin',
    laymanDescription: 'Bimbingan penggunaan sampai tim Al Madroj terbiasa mengelola platform',
    starter: 'Basic',
    standard: true,
    pro: true
  }
];

export const PAYMENT_SCHEME = {
  starter: [
    { step: '50% DP', percentage: '50%', amount: 1100000, description: 'Saat kick-off pengerjaan' },
    { step: '50% Sebelum Handover', percentage: '50%', amount: 1100000, description: 'Sebelum serah terima website live' }
  ],
  standard: [
    { step: '50% DP', percentage: '50%', amount: 1750000, description: 'Saat kick-off perancangan' },
    { step: '30% Saat Beta', percentage: '30%', amount: 1050000, description: 'Saat demo platform siap diuji coba' },
    { step: '20% Sebelum Handover', percentage: '20%', amount: 700000, description: 'Sebelum serah terima dan training admin' }
  ],
  pro: [
    { step: '50% DP', percentage: '50%', amount: 2500000, description: 'Saat kick-off perancangan LMS' },
    { step: '30% Saat Beta', percentage: '30%', amount: 1500000, description: 'Saat demo fitur kuis dan sertifikat siap diuji coba' },
    { step: '20% Sebelum Handover', percentage: '20%', amount: 1000000, description: 'Sebelum handover lengkap dan launch' }
  ]
};

export const NOT_INCLUDED_ITEMS = [
  {
    title: 'Biaya Perpanjangan Domain di Tahun ke-2',
    desc: 'Domain .com gratis untuk 1 tahun pertama. Perpanjangan tahun ke-2 dan seterusnya dibayarkan sesuai tarif resmi registrar domain.'
  },
  {
    title: 'Biaya Transaksi Provider Mayar.id',
    desc: 'Biaya per transaksi dari penyedia Mayar.id.'
  },
  {
    title: 'Layanan Cloud Hosting Khusus',
    desc: 'Layanan server kapasitas tinggi jika diperlukan server dedicated khusus berbayar.'
  },
  {
    title: 'WhatsApp API Berbayar',
    desc: 'Langganan provider gateway WhatsApp jika menggunakan notifikasi otomatis.'
  },
  {
    title: 'Zoom / Live Streaming Berbayar',
    desc: 'Akun Zoom Pro jika kelas mengadakan sesi live interaktif.'
  },
  {
    title: 'Aplikasi Android dan iOS Native',
    desc: 'Platform ini berbasis web responsive yang ringan diakses langsung dari browser.'
  },
  {
    title: 'Fitur AI atau Integrasi di Luar Scope',
    desc: 'Permintaan fitur tambahan di luar kesepakatan dapat didiskusikan secara fleksibel.'
  }
];

export const FAQS: FaqItem[] = [
  {
    question: 'Apakah domain sudah termasuk dalam paket?',
    answer: 'Ya, semua paket (Starter, Standard, dan Pro) sudah termasuk pendaftaran nama domain .com gratis untuk 1 tahun pertama.',
    category: 'biaya'
  },
  {
    question: 'Apakah Paket Standard sudah otomatis payment gateway?',
    answer: 'Ya, Paket Standard (Rp3,5 Juta) dan Pro LMS (Rp5 Juta) sudah terintegrasi payment gateway Mayar.id sehingga peserta dapat membayar via QRIS/VA dan akun langsung aktif otomatis.',
    category: 'fitur'
  },
  {
    question: 'Apakah orang awam bisa mengelola website ini nantinya?',
    answer: 'Sangat bisa. Dashboard admin dirancang dengan bahasa Indonesia yang jelas, tombol yang mudah dipahami, dan kami sertakan sesi training langsung sampai tim Al Madroj benar-benar terbiasa.',
    category: 'teknis'
  },
  {
    question: 'Berapa lama estimasi pengerjaan website ini?',
    answer: 'Estimasi pengerjaan untuk Paket Starter sekitar 7 sampai 10 hari kerja, Paket Standard sekitar 14 sampai 20 hari kerja, dan Paket Pro sekitar 20 sampai 30 hari kerja setelah materi dan DP diterima.',
    category: 'pengerjaan'
  }
];
