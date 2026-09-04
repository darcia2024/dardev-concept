import React, { useEffect, useMemo, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import {
  ArrowLeft, Award, Bell, BookOpen, CalendarDays, Check, CheckCircle2,
  ChevronDown, ChevronRight, CircleHelp, ClipboardCheck, CreditCard, Download,
  FileText, GraduationCap, House, LayoutDashboard, LockKeyhole, Menu,
  MessageCircle, MoreHorizontal, Play, Plus, RefreshCw, Search, ShieldCheck,
  UploadCloud, UsersRound, X,
} from 'lucide-react';
import { PROPOSAL_META } from '../data/proposalData';

type Screen = 'dashboard' | 'catalog' | 'checkout' | 'learning' | 'quiz' | 'admin' | 'instructor' | 'certificate';
type AdminState = 'ready' | 'loading' | 'error';

interface ProductDemoProps {
  onBackToProposal: () => void;
}

interface Course {
  id: string;
  title: string;
  level: string;
  schedule: string;
  duration: string;
  price: string;
  progress: number;
  completed: number;
  lessons: number;
  tone: string;
  accent: string;
}

const courses: Course[] = [
  { id: 'arabic', title: 'Bahasa Arab Pemula', level: 'Dasar', schedule: 'Rabu, 20.00 WIB', duration: '12 pertemuan', price: 'Rp349.000', progress: 68, completed: 12, lessons: 18, tone: 'bg-[#dfeee7]', accent: 'text-[#176148]' },
  { id: 'tahsin', title: 'Tahsin Intensif', level: 'Menengah', schedule: 'Sabtu, 08.00 WIB', duration: '8 pertemuan', price: 'Rp279.000', progress: 34, completed: 5, lessons: 14, tone: 'bg-[#f1e7cc]', accent: 'text-[#75520d]' },
  { id: 'fiqih', title: 'Fiqih Ibadah Praktis', level: 'Semua level', schedule: 'Ahad, 19.30 WIB', duration: '10 pertemuan', price: 'Rp299.000', progress: 0, completed: 0, lessons: 16, tone: 'bg-[#e6e5ef]', accent: 'text-[#4b486d]' },
];

const lessons = [
  { title: 'Pengantar dan target belajar', duration: '08:42', type: 'Video', done: true },
  { title: 'Mengenal isim, fiil, dan huruf', duration: '16:20', type: 'Video', done: true },
  { title: 'Kosakata aktivitas harian', duration: '12:05', type: 'Video', done: true },
  { title: 'Latihan menyusun jumlah ismiyah', duration: '18:14', type: 'Video', done: false },
  { title: 'Ringkasan modul pertama', duration: '6 halaman', type: 'PDF', done: false },
];

const participants = [
  { name: 'Peserta 01', course: 'Bahasa Arab Pemula', payment: 'Lunas', progress: '68%', attendance: '5/6' },
  { name: 'Peserta 02', course: 'Tahsin Intensif', payment: 'Lunas', progress: '34%', attendance: '3/4' },
  { name: 'Peserta 03', course: 'Fiqih Ibadah Praktis', payment: 'Menunggu', progress: '0%', attendance: '-' },
  { name: 'Peserta 04', course: 'Bahasa Arab Pemula', payment: 'Lunas', progress: '92%', attendance: '6/6' },
];

const screenMeta: Record<Screen, { label: string; eyebrow: string }> = {
  dashboard: { label: 'Beranda', eyebrow: 'Ruang peserta' },
  catalog: { label: 'Katalog kelas', eyebrow: 'Program Al Madroj' },
  checkout: { label: 'Pendaftaran', eyebrow: 'Checkout aman' },
  learning: { label: 'Ruang belajar', eyebrow: 'Bahasa Arab Pemula' },
  quiz: { label: 'Evaluasi', eyebrow: 'Modul 1' },
  admin: { label: 'Monitoring', eyebrow: 'Panel admin' },
  instructor: { label: 'Kelas saya', eyebrow: 'Portal pengajar' },
  certificate: { label: 'Sertifikat', eyebrow: 'Kelulusan peserta' },
};

const navigation = [
  { id: 'dashboard' as Screen, label: 'Beranda', icon: House, group: 'Peserta' },
  { id: 'catalog' as Screen, label: 'Katalog kelas', icon: Search, group: 'Peserta' },
  { id: 'learning' as Screen, label: 'Ruang belajar', icon: BookOpen, group: 'Peserta' },
  { id: 'quiz' as Screen, label: 'Kuis & evaluasi', icon: ClipboardCheck, group: 'Peserta' },
  { id: 'certificate' as Screen, label: 'Sertifikat', icon: Award, group: 'Peserta' },
  { id: 'admin' as Screen, label: 'Monitoring admin', icon: LayoutDashboard, group: 'Pengelola' },
  { id: 'instructor' as Screen, label: 'Portal pengajar', icon: GraduationCap, group: 'Pengelola' },
];

const pageMotion = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -6 },
  transition: { duration: 0.22, ease: [0.22, 1, 0.36, 1] as const },
};

export const ProductDemo: React.FC<ProductDemoProps> = ({ onBackToProposal }) => {
  const [screen, setScreen] = useState<Screen>('dashboard');
  const [selectedCourse, setSelectedCourse] = useState(courses[0]);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [toast, setToast] = useState('Data di layar ini adalah simulasi tampilan produk.');
  const [catalogSearch, setCatalogSearch] = useState('');
  const [adminSearch, setAdminSearch] = useState('');
  const [adminState, setAdminState] = useState<AdminState>('ready');
  const [activeLesson, setActiveLesson] = useState(3);
  const [moduleOpen, setModuleOpen] = useState(true);
  const [quizAnswers, setQuizAnswers] = useState<Record<number, string>>({});
  const [quizSubmitted, setQuizSubmitted] = useState(false);
  const [checkoutSubmitted, setCheckoutSubmitted] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState<'qris' | 'va'>('qris');

  const visibleCourses = useMemo(
    () => courses.filter((course) => course.title.toLowerCase().includes(catalogSearch.toLowerCase())),
    [catalogSearch],
  );
  const visibleParticipants = useMemo(
    () => participants.filter((item) => (item.name + ' ' + item.course + ' ' + item.payment).toLowerCase().includes(adminSearch.toLowerCase())),
    [adminSearch],
  );

  useEffect(() => {
    const closeOverlays = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setMobileMenuOpen(false);
        setUploadOpen(false);
      }
    };
    const offline = () => setAdminState('error');
    const online = () => setAdminState('ready');
    window.addEventListener('keydown', closeOverlays);
    window.addEventListener('offline', offline);
    window.addEventListener('online', online);
    return () => {
      window.removeEventListener('keydown', closeOverlays);
      window.removeEventListener('offline', offline);
      window.removeEventListener('online', online);
    };
  }, []);

  const go = (next: Screen) => {
    setScreen(next);
    setMobileMenuOpen(false);
    setToast(screenMeta[next].label + ' dibuka.');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };
  const contact = () => {
    const text = encodeURIComponent('Halo, saya ingin membahas pengembangan Pro LMS Al Madroj setelah melihat preview produknya.');
    window.open('https://wa.me/' + PROPOSAL_META.contactWhatsApp + '?text=' + text, '_blank', 'noopener,noreferrer');
  };
  const refreshAdmin = () => {
    setAdminState('loading');
    window.setTimeout(() => {
      setAdminState(navigator.onLine ? 'ready' : 'error');
      setToast(navigator.onLine ? 'Data monitoring sudah diperbarui.' : 'Koneksi terputus. Data belum dapat dimuat.');
    }, 700);
  };

  return (
    <div className="min-h-[100dvh] overflow-x-hidden bg-[#f4f5f1] font-sans text-[#17201c]">
      <a href="#demo-content" className="fixed left-3 top-3 z-[60] -translate-y-24 rounded-md bg-white px-4 py-3 text-sm font-semibold text-[#173e31] shadow-lg transition focus:translate-y-0">Lewati ke konten</a>

      <aside className="fixed inset-y-0 left-0 z-40 hidden w-[264px] flex-col bg-[#10251d] px-4 py-5 text-white lg:flex">
        <Brand />
        <nav aria-label="Navigasi produk" className="demo-scrollbar mt-9 min-h-0 flex-1 overflow-y-auto">
          {['Peserta', 'Pengelola'].map((group) => (
            <div key={group} className="mb-7">
              <p className="mb-2 px-3 text-xs font-semibold text-[#91a79e]">{group}</p>
              <div className="space-y-1">
                {navigation.filter((item) => item.group === group).map((item) => (
                  <NavButton key={item.id} item={item} active={screen === item.id} onClick={() => go(item.id)} />
                ))}
              </div>
            </div>
          ))}
        </nav>
        <div className="border-t border-white/10 pt-4">
          <div className="mb-3 flex items-center gap-3 px-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-md bg-[#e8c56f] text-sm font-bold text-[#10251d]">AM</div>
            <div><p className="text-sm font-semibold">Al Madroj</p><p className="text-xs text-[#91a79e]">Pro LMS</p></div>
          </div>
          <button onClick={onBackToProposal} className="flex min-h-11 w-full items-center gap-3 rounded-md px-3 text-sm text-[#c6d2cd] transition hover:bg-white/8 hover:text-white">
            <ArrowLeft className="h-4 w-4" />Kembali ke penawaran
          </button>
        </div>
      </aside>

      <div className="lg:pl-[264px]">
        <header className="sticky top-0 z-30 border-b border-[#dfe3dd] bg-[#f4f5f1]/92 backdrop-blur-xl">
          <div className="flex h-16 items-center justify-between gap-3 px-4 sm:px-6 lg:h-[72px] lg:px-8 xl:px-10">
            <div className="flex min-w-0 items-center gap-3">
              <button aria-label="Buka menu" aria-expanded={mobileMenuOpen} onClick={() => setMobileMenuOpen(true)} className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md border border-[#d8ddd7] bg-white text-[#173e31] hover:bg-[#e9eee9] lg:hidden"><Menu className="h-5 w-5" /></button>
              <div className="hidden sm:block"><p className="text-xs font-semibold text-[#68756f]">{screenMeta[screen].eyebrow}</p><h1 className="truncate text-lg font-bold">{screenMeta[screen].label}</h1></div>
              <img src="/logo.svg" alt="Al Madroj" className="h-9 w-9 rounded-md bg-[#10251d] p-1.5 sm:hidden" />
            </div>
            <div className="flex items-center gap-2">
              <button onClick={contact} className="hidden min-h-11 items-center gap-2 rounded-md border border-[#ccd4ce] bg-white px-4 text-sm font-semibold text-[#173e31] hover:bg-[#edf1ee] sm:flex"><MessageCircle className="h-4 w-4" />Hubungi tim</button>
              <button aria-label="Lihat notifikasi" onClick={() => setToast('Tidak ada notifikasi baru.')} className="relative flex h-11 w-11 items-center justify-center rounded-md border border-[#d8ddd7] bg-white hover:bg-[#e9eee9]"><Bell className="h-5 w-5" /><span className="absolute right-2.5 top-2.5 h-2 w-2 rounded-full border-2 border-white bg-[#c98615]" /></button>
              <button onClick={() => setToast('Menu akun peserta dibuka.')} className="flex h-11 items-center gap-2 rounded-md border border-[#d8ddd7] bg-white px-2 pr-3 hover:bg-[#e9eee9]"><span className="flex h-7 w-7 items-center justify-center rounded-md bg-[#dfeee7] text-xs font-bold text-[#176148]">P</span><ChevronDown className="hidden h-4 w-4 text-[#68756f] sm:block" /><span className="sr-only">Buka menu akun</span></button>
            </div>
          </div>
        </header>

        <main id="demo-content" className="mx-auto w-full max-w-[1500px] px-4 pb-28 pt-5 sm:px-6 sm:pt-7 lg:px-8 lg:pb-10 xl:px-10">
          <div className="mb-5 flex items-center justify-between gap-4">
            <div><p className="text-xs font-semibold text-[#68756f] sm:hidden">{screenMeta[screen].eyebrow}</p><h2 className="text-2xl font-bold leading-tight sm:text-[30px]">{screenMeta[screen].label}</h2></div>
            <span className="hidden rounded-md border border-[#d8ddd7] bg-white px-3 py-2 text-xs font-medium text-[#68756f] md:block">Data simulasi</span>
          </div>

          <AnimatePresence mode="wait">
            <motion.div key={screen} {...pageMotion}>
              {screen === 'dashboard' && <DashboardScreen go={go} />}
              {screen === 'catalog' && <CatalogScreen search={catalogSearch} setSearch={setCatalogSearch} items={visibleCourses} checkout={(course) => { setSelectedCourse(course); setCheckoutSubmitted(false); go('checkout'); }} />}
              {screen === 'checkout' && <CheckoutScreen course={selectedCourse} payment={paymentMethod} setPayment={setPaymentMethod} submitted={checkoutSubmitted} submit={() => { setCheckoutSubmitted(true); setToast('Pendaftaran diterima. Invoice Mayar.id siap diproses.'); }} back={() => go('catalog')} />}
              {screen === 'learning' && <LearningScreen active={activeLesson} moduleOpen={moduleOpen} toggleModule={() => setModuleOpen((value) => !value)} setActive={setActiveLesson} goQuiz={() => go('quiz')} message={setToast} />}
              {screen === 'quiz' && <QuizScreen answers={quizAnswers} submitted={quizSubmitted} answer={(question, value) => setQuizAnswers((current) => ({ ...current, [question]: value }))} submit={() => { setQuizSubmitted(true); setToast('Jawaban tersimpan di laporan peserta.'); }} />}
              {screen === 'admin' && <AdminScreen search={adminSearch} setSearch={setAdminSearch} items={visibleParticipants} status={adminState} refresh={refreshAdmin} message={setToast} />}
              {screen === 'instructor' && <InstructorScreen upload={() => setUploadOpen(true)} message={setToast} />}
              {screen === 'certificate' && <CertificateScreen />}
            </motion.div>
          </AnimatePresence>

          <div role="status" aria-live="polite" className="mt-6 flex min-h-14 items-center justify-between gap-3 border-t border-[#d8ddd7] pt-4 text-sm text-[#59655f]">
            <div className="flex min-w-0 items-center gap-2"><CheckCircle2 className="h-4 w-4 shrink-0 text-[#176148]" /><span className="truncate">{toast}</span></div>
            <button onClick={contact} className="shrink-0 font-semibold text-[#176148] underline decoration-[#98b6a8] underline-offset-4">Diskusikan</button>
          </div>
        </main>
      </div>

      <MobileNavigation active={screen} go={go} more={() => setMobileMenuOpen(true)} />
      <AnimatePresence>
        {mobileMenuOpen && <MobileMenu active={screen} go={go} close={() => setMobileMenuOpen(false)} back={onBackToProposal} contact={contact} />}
        {uploadOpen && <UploadDialog close={() => setUploadOpen(false)} save={() => { setUploadOpen(false); setToast('Materi disimpan sebagai draft untuk direview admin.'); }} />}
      </AnimatePresence>
    </div>
  );
};

const Brand = () => (
  <div className="flex items-center gap-3 px-2">
    <img src="/logo.svg" alt="" className="h-11 w-11 rounded-lg bg-white p-2" />
    <div><p className="text-base font-bold leading-tight">Al Madroj</p><p className="mt-0.5 text-xs text-[#91a79e]">Learning platform</p></div>
  </div>
);

const NavButton = ({ item, active, onClick }: { item: typeof navigation[number]; active: boolean; onClick: () => void }) => {
  const Icon = item.icon;
  return (
    <button onClick={onClick} aria-current={active ? 'page' : undefined} className={'relative flex min-h-11 w-full items-center gap-3 rounded-md px-3 text-left text-sm font-medium transition ' + (active ? 'bg-white text-[#10251d]' : 'text-[#c6d2cd] hover:bg-white/8 hover:text-white')}>
      <Icon className="h-[18px] w-[18px]" strokeWidth={1.9} />{item.label}
      {active && <motion.span layoutId="active-nav" className="absolute -left-4 h-6 w-1 rounded-r bg-[#f2b84b]" />}
    </button>
  );
};

const DashboardScreen = ({ go }: { go: (screen: Screen) => void }) => (
  <div className="grid gap-5 xl:grid-cols-[minmax(0,1.65fr)_minmax(300px,.75fr)]">
    <div className="space-y-5">
      <section className="relative overflow-hidden rounded-lg bg-[#10251d] px-5 pb-6 pt-6 text-white sm:px-8 sm:pb-8 sm:pt-8">
        <div className="absolute right-0 top-0 h-full w-1/3 bg-[linear-gradient(135deg,transparent,rgba(242,184,75,.11))]" />
        <div className="relative max-w-2xl">
          <div className="mb-8 flex items-center gap-2 text-sm text-[#b8c9c1]"><span className="h-2 w-2 rounded-full bg-[#f2b84b]" />Pertemuan berikutnya, Rabu pukul 20.00 WIB</div>
          <p className="text-sm font-semibold text-[#b8c9c1]">Bahasa Arab Pemula</p>
          <h3 className="mt-2 max-w-xl text-[clamp(1.75rem,4vw,3.25rem)] font-bold leading-[1.08] text-balance">Lanjutkan dari jumlah ismiyah</h3>
          <p className="mt-4 max-w-xl text-sm leading-6 text-[#b8c9c1] sm:text-base">Pelajari pola kalimat dasar, lalu kerjakan evaluasi singkat untuk membuka modul berikutnya.</p>
          <div className="mt-7 flex flex-wrap gap-3">
            <button onClick={() => go('learning')} className="flex min-h-11 items-center gap-2 rounded-md bg-[#f2b84b] px-5 text-sm font-bold text-[#10251d] hover:bg-[#ffd176]"><Play className="h-4 w-4 fill-current" />Lanjut belajar</button>
            <button onClick={() => go('quiz')} className="min-h-11 rounded-md border border-white/20 px-5 text-sm font-semibold hover:bg-white/8">Buka evaluasi</button>
          </div>
        </div>
        <div className="relative mt-10 grid gap-4 border-t border-white/12 pt-5 sm:grid-cols-[1fr_auto] sm:items-center">
          <div><div className="mb-2 flex justify-between text-xs text-[#b8c9c1]"><span>Progress kelas</span><span className="font-semibold text-white">68%</span></div><div className="h-2 rounded-full bg-white/12"><div className="h-full w-[68%] rounded-full bg-[#f2b84b]" /></div></div>
          <p className="text-xs text-[#b8c9c1]">12 dari 18 materi selesai</p>
        </div>
      </section>
      <section>
        <div className="mb-3 flex items-center justify-between"><div><h3 className="text-lg font-bold">Kelas aktif</h3><p className="mt-1 text-sm text-[#68756f]">Akses materi mengikuti status pembayaran.</p></div><button onClick={() => go('catalog')} className="min-h-11 px-2 text-sm font-semibold text-[#176148]">Lihat katalog</button></div>
        <div className="grid gap-3 md:grid-cols-2">
          {courses.slice(0, 2).map((course) => <CourseProgress key={course.id} course={course} />)}
        </div>
      </section>
    </div>
    <aside className="space-y-5">
      <section className="rounded-lg border border-[#d8ddd7] bg-white p-5">
        <div className="flex justify-between"><div><p className="text-xs font-semibold text-[#68756f]">Jadwal terdekat</p><h3 className="mt-1 text-lg font-bold">Rabu, 20.00</h3></div><CalendarDays className="h-5 w-5 text-[#176148]" /></div>
        <div className="mt-5 border-l-2 border-[#f2b84b] pl-4"><p className="text-sm font-semibold">Kelas live, pertemuan 7</p><p className="mt-1 text-sm text-[#68756f]">Jumlah ismiyah dan latihan dialog</p></div>
        <button onClick={() => go('learning')} className="mt-5 min-h-11 w-full rounded-md border border-[#cad2cc] text-sm font-semibold hover:bg-[#edf1ee]">Lihat ruang kelas</button>
      </section>
      <section className="rounded-lg bg-[#e7eee9] p-5">
        <p className="text-xs font-semibold text-[#5e7067]">Status belajar</p>
        <div className="mt-4 space-y-4"><StatusRow icon={ClipboardCheck} label="Evaluasi modul 1" value="Belum dikerjakan" /><StatusRow icon={CalendarDays} label="Kehadiran" value="5 dari 6 sesi" /><StatusRow icon={Award} label="Sertifikat" value="Terkunci" /></div>
      </section>
      <button onClick={() => go('certificate')} className="flex min-h-14 w-full items-center justify-between rounded-lg border border-[#d8ddd7] bg-white px-5 text-left hover:border-[#9baba2]">
        <span><span className="block text-sm font-bold">Cek syarat sertifikat</span><span className="mt-0.5 block text-xs text-[#68756f]">Progress, nilai, dan kehadiran</span></span><ChevronRight className="h-5 w-5" />
      </button>
    </aside>
  </div>
);

const CourseProgress = ({ course }: { course: Course }) => (
  <article className="rounded-lg border border-[#d8ddd7] bg-white p-4 transition hover:border-[#9baba2] hover:shadow-[0_16px_40px_rgba(25,52,41,.08)]">
    <div className={'mb-5 flex h-24 items-end rounded-md p-4 ' + course.tone}><BookOpen className={'h-6 w-6 ' + course.accent} /></div>
    <p className={'text-xs font-semibold ' + course.accent}>{course.level}</p><h4 className="mt-1 text-lg font-bold">{course.title}</h4>
    <div className="mt-4 flex justify-between text-xs text-[#68756f]"><span>{course.completed}/{course.lessons} materi</span><span>{course.progress}%</span></div>
    <div className="mt-2 h-1.5 rounded-full bg-[#e7ebe7]"><div className="h-full rounded-full bg-[#176148]" style={{ width: course.progress + '%' }} /></div>
  </article>
);

const CatalogScreen = ({ search, setSearch, items, checkout }: { search: string; setSearch: (value: string) => void; items: Course[]; checkout: (course: Course) => void }) => (
  <div>
    <section className="grid gap-6 rounded-lg border border-[#d8ddd7] bg-white p-5 sm:p-7 lg:grid-cols-[minmax(0,1fr)_380px] lg:items-end">
      <div className="max-w-2xl"><p className="text-sm font-semibold text-[#176148]">Program belajar terstruktur</p><h3 className="mt-2 text-[clamp(1.8rem,4vw,3rem)] font-bold leading-[1.12] text-balance">Pilih kelas, bayar, lalu materi terbuka otomatis.</h3><p className="mt-3 max-w-xl text-sm leading-6 text-[#68756f] sm:text-base">Jadwal, silabus, evaluasi, dan progress tersimpan dalam satu akun.</p></div>
      <SearchInput value={search} setValue={setSearch} placeholder="Cari nama kelas" />
    </section>
    {items.length === 0 ? <EmptyState title="Kelas tidak ditemukan" description="Coba kata kunci lain untuk melihat program yang tersedia." action="Hapus pencarian" onAction={() => setSearch('')} /> : (
      <section className="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {items.map((course, index) => (
          <article key={course.id} className="flex min-h-[390px] flex-col rounded-lg border border-[#d8ddd7] bg-white p-4 transition hover:-translate-y-0.5 hover:border-[#9baba2] hover:shadow-[0_18px_42px_rgba(25,52,41,.08)]">
            <div className={'relative flex h-36 items-end rounded-md p-5 ' + course.tone}><span className={'text-[54px] font-bold leading-none opacity-15 ' + course.accent}>0{index + 1}</span><span className="absolute right-4 top-4 rounded-md bg-white/80 px-2.5 py-1 text-xs font-semibold">{course.level}</span></div>
            <div className="flex flex-1 flex-col px-1 pb-1 pt-5"><p className="text-xs font-semibold text-[#176148]">{course.duration}</p><h3 className="mt-1 text-xl font-bold">{course.title}</h3><div className="mt-4 space-y-2 text-sm text-[#59655f]"><p className="flex items-center gap-2"><CalendarDays className="h-4 w-4" />{course.schedule}</p><p className="flex items-center gap-2"><UsersRound className="h-4 w-4" />Tim Pengajar Al Madroj</p></div><div className="mt-auto flex items-end justify-between gap-3 border-t border-[#e5e8e3] pt-5"><div><p className="text-xs text-[#68756f]">Investasi belajar</p><p className="mt-1 text-lg font-bold">{course.price}</p></div><button onClick={() => checkout(course)} className="min-h-11 rounded-md bg-[#176148] px-4 text-sm font-bold text-white hover:bg-[#10251d]">Daftar kelas</button></div></div>
          </article>
        ))}
      </section>
    )}
  </div>
);

const CheckoutScreen = ({ course, payment, setPayment, submitted, submit, back }: { course: Course; payment: 'qris' | 'va'; setPayment: (value: 'qris' | 'va') => void; submitted: boolean; submit: () => void; back: () => void }) => {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const next: Record<string, string> = {};
    if (name.trim().length < 3) next.name = 'Masukkan nama lengkap peserta.';
    if (!/^08\d{8,11}$/.test(phone)) next.phone = 'Gunakan nomor WhatsApp aktif, contoh 081234567890.';
    if (!/^\S+@\S+\.\S+$/.test(email)) next.email = 'Masukkan alamat email yang valid.';
    setErrors(next);
    if (Object.keys(next).length === 0) submit();
  };
  if (submitted) return <EmptyState icon={CheckCircle2} title="Pendaftaran sudah tercatat" description={'Invoice ' + course.title + ' akan dikirim ke email dan WhatsApp peserta. Akses kelas aktif otomatis setelah pembayaran berhasil.'} action="Kembali ke katalog" onAction={back} success />;
  return (
    <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_390px]">
      <form onSubmit={handleSubmit} noValidate className="rounded-lg border border-[#d8ddd7] bg-white p-5 sm:p-7">
        <button type="button" onClick={back} className="mb-6 flex min-h-11 items-center gap-2 text-sm font-semibold text-[#59655f]"><ArrowLeft className="h-4 w-4" />Kembali ke katalog</button>
        <p className="text-sm font-semibold text-[#176148]">Data peserta</p><h3 className="mt-1 text-2xl font-bold">Buat akun untuk mengikuti kelas</h3><p className="mt-2 text-sm leading-6 text-[#68756f]">Email dipakai untuk login. WhatsApp dipakai untuk invoice dan pengingat jadwal.</p>
        <div className="mt-7 grid gap-5 sm:grid-cols-2"><FormField id="name" label="Nama lengkap" value={name} setValue={setName} placeholder="Nama sesuai sertifikat" error={errors.name} /><FormField id="phone" label="Nomor WhatsApp" value={phone} setValue={setPhone} placeholder="081234567890" error={errors.phone} /><div className="sm:col-span-2"><FormField id="email" label="Email login" value={email} setValue={setEmail} placeholder="nama@email.com" error={errors.email} /></div></div>
        <fieldset className="mt-8"><legend className="text-sm font-bold">Metode pembayaran</legend><div className="mt-3 grid gap-3 sm:grid-cols-2"><Payment active={payment === 'qris'} label="QRIS" detail="Scan dari semua e-wallet" click={() => setPayment('qris')} /><Payment active={payment === 'va'} label="Virtual Account" detail="Transfer bank otomatis" click={() => setPayment('va')} /></div></fieldset>
        <label className="mt-6 flex items-start gap-3 text-sm leading-6 text-[#59655f]"><input required type="checkbox" className="mt-1 h-4 w-4 accent-[#176148]" /><span>Saya memastikan data peserta sudah benar dan menyetujui ketentuan pendaftaran.</span></label>
        <button type="submit" className="mt-7 flex min-h-12 w-full items-center justify-center gap-2 rounded-md bg-[#176148] px-5 text-sm font-bold text-white hover:bg-[#10251d]"><LockKeyhole className="h-4 w-4" />Lanjut ke pembayaran</button>
      </form>
      <aside className="h-fit rounded-lg bg-[#10251d] p-5 text-white sm:p-6 xl:sticky xl:top-24">
        <p className="text-xs font-semibold text-[#afc1b9]">Ringkasan pesanan</p><h3 className="mt-3 text-2xl font-bold">{course.title}</h3><p className="mt-2 text-sm text-[#afc1b9]">{course.duration} · {course.schedule}</p>
        <div className="my-6 space-y-3 border-y border-white/12 py-5 text-sm"><div className="flex justify-between"><span className="text-[#afc1b9]">Biaya kelas</span><span>{course.price}</span></div><div className="flex justify-between"><span className="text-[#afc1b9]">Biaya layanan</span><span>Rp0</span></div></div>
        <div className="flex items-end justify-between"><span className="text-sm text-[#afc1b9]">Total pembayaran</span><span className="text-2xl font-bold">{course.price}</span></div>
        <div className="mt-7 flex gap-3 rounded-md bg-white/8 p-4"><ShieldCheck className="h-5 w-5 shrink-0 text-[#f2b84b]" /><p className="text-xs leading-5 text-[#c6d2cd]">Diproses melalui Mayar.id. Materi terbuka otomatis setelah transaksi berhasil.</p></div>
      </aside>
    </div>
  );
};

const LearningScreen = ({ active, moduleOpen, toggleModule, setActive, goQuiz, message }: { active: number; moduleOpen: boolean; toggleModule: () => void; setActive: (value: number) => void; goQuiz: () => void; message: (value: string) => void }) => (
  <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_380px]">
    <div className="space-y-5">
      <section className="overflow-hidden rounded-lg bg-[#0d1511] text-white"><div className="relative flex aspect-video items-center justify-center bg-[radial-gradient(circle_at_50%_35%,#284d3d_0%,#0d1511_63%)]"><button onClick={() => message('Pemutar materi aktif. Progress tersimpan otomatis.')} className="flex h-16 w-16 items-center justify-center rounded-full bg-[#f2b84b] text-[#10251d] transition hover:scale-105" aria-label="Putar materi"><Play className="ml-1 h-6 w-6 fill-current" /></button><div className="absolute inset-x-4 bottom-4 flex items-center gap-3"><span className="text-xs">08:16</span><div className="h-1 flex-1 rounded-full bg-white/20"><div className="h-full w-[42%] rounded-full bg-[#f2b84b]" /></div><span className="text-xs">18:14</span></div></div><div className="p-5 sm:p-6"><p className="text-xs font-semibold text-[#afc1b9]">Modul 1 · Materi 4</p><h3 className="mt-1 text-xl font-bold sm:text-2xl">Latihan menyusun jumlah ismiyah</h3><p className="mt-2 text-sm leading-6 text-[#afc1b9]">Pahami susunan mubtada dan khabar melalui contoh kalimat harian.</p></div></section>
      <section className="rounded-lg border border-[#d8ddd7] bg-white p-5 sm:p-6"><div className="flex flex-col gap-4 sm:flex-row sm:justify-between"><div><p className="text-xs font-semibold text-[#176148]">Catatan pertemuan</p><h3 className="mt-1 text-lg font-bold">Ringkasan materi</h3></div><button onClick={() => message('Modul PDF disiapkan untuk diunduh.')} className="flex min-h-11 items-center justify-center gap-2 rounded-md border border-[#cad2cc] px-4 text-sm font-semibold"><Download className="h-4 w-4" />Unduh modul</button></div><p className="mt-4 text-sm leading-7 text-[#59655f]">Jumlah ismiyah dimulai dengan isim. Peserta berlatih membedakan posisi mubtada dan khabar, membaca contoh, lalu menyusun kalimat sendiri.</p></section>
    </div>
    <aside className="h-fit rounded-lg border border-[#d8ddd7] bg-white xl:sticky xl:top-24">
      <div className="border-b border-[#e2e6e1] p-5"><div className="flex justify-between"><div><p className="text-xs font-semibold text-[#68756f]">Progress kelas</p><p className="mt-1 text-lg font-bold">68% selesai</p></div><span className="flex h-10 w-10 items-center justify-center rounded-md bg-[#dfeee7] font-bold text-[#176148]">12</span></div><div className="mt-4 h-1.5 rounded-full bg-[#e7ebe7]"><div className="h-full w-[68%] rounded-full bg-[#176148]" /></div></div>
      <button onClick={toggleModule} aria-expanded={moduleOpen} className="flex min-h-14 w-full items-center justify-between px-5 text-left text-sm font-bold hover:bg-[#f4f6f2]"><span>Modul 1: Struktur dasar</span><ChevronDown className={'h-4 w-4 transition ' + (moduleOpen ? 'rotate-180' : '')} /></button>
      {moduleOpen && <div className="border-t border-[#e2e6e1]">{lessons.map((lesson, index) => <button key={lesson.title} onClick={() => setActive(index)} className={'flex min-h-[64px] w-full items-start gap-3 border-b border-[#eef0ec] px-5 py-3 text-left ' + (active === index ? 'bg-[#edf4ef]' : 'hover:bg-[#f7f8f5]')}><span className={'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md ' + (lesson.done ? 'bg-[#176148] text-white' : active === index ? 'bg-[#f2b84b]' : 'bg-[#ecefeb] text-[#68756f]')}>{lesson.done ? <Check className="h-4 w-4" /> : lesson.type === 'PDF' ? <FileText className="h-4 w-4" /> : <Play className="h-3.5 w-3.5" />}</span><span><span className="block text-sm font-semibold leading-5">{lesson.title}</span><span className="mt-1 block text-xs text-[#68756f]">{lesson.type} · {lesson.duration}</span></span></button>)}<div className="p-4"><button onClick={goQuiz} className="min-h-11 w-full rounded-md bg-[#176148] px-4 text-sm font-bold text-white">Kerjakan evaluasi modul</button></div></div>}
    </aside>
  </div>
);

const QuizScreen = ({ answers, submitted, answer, submit }: { answers: Record<number, string>; submitted: boolean; answer: (question: number, value: string) => void; submit: () => void }) => {
  const questions = [
    { question: 'Apa unsur pembuka dalam jumlah ismiyah?', options: ['Isim', 'Fiil', 'Huruf jar'], correct: 'Isim' },
    { question: 'Pasangan utama dalam struktur jumlah ismiyah adalah...', options: ['Fiil dan fail', 'Mubtada dan khabar', 'Jar dan majrur'], correct: 'Mubtada dan khabar' },
  ];
  const score = questions.filter((item, index) => answers[index] === item.correct).length;
  return (
    <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_330px]">
      <section className="rounded-lg border border-[#d8ddd7] bg-white p-5 sm:p-7"><div className="border-b border-[#e2e6e1] pb-6"><p className="text-sm font-semibold text-[#176148]">Evaluasi modul 1</p><h3 className="mt-1 text-2xl font-bold">Struktur dasar bahasa Arab</h3><p className="mt-2 text-sm text-[#68756f]">Pilih satu jawaban untuk setiap pertanyaan.</p></div><div className="divide-y divide-[#e2e6e1]">{questions.map((item, index) => <fieldset key={item.question} className="py-6"><legend className="text-base font-bold"><span className="mr-2 text-[#176148]">{index + 1}.</span>{item.question}</legend><div className="mt-4 grid gap-2">{item.options.map((option) => <label key={option} className={'flex min-h-12 cursor-pointer items-center gap-3 rounded-md border px-4 text-sm ' + (answers[index] === option ? 'border-[#176148] bg-[#edf4ef]' : 'border-[#d8ddd7] hover:border-[#9baba2]')}><input type="radio" name={'q-' + index} checked={answers[index] === option} onChange={() => answer(index, option)} className="h-4 w-4 accent-[#176148]" />{option}</label>)}</div></fieldset>)}</div>{submitted ? <div role="status" className="rounded-md bg-[#e3f0e9] p-4 text-sm text-[#174b39]"><p className="font-bold">Hasil evaluasi: {score} dari {questions.length} jawaban benar.</p><p className="mt-1">Nilai tersimpan pada laporan peserta.</p></div> : <button onClick={submit} disabled={Object.keys(answers).length !== questions.length} className="min-h-12 w-full rounded-md bg-[#176148] text-sm font-bold text-white disabled:cursor-not-allowed disabled:bg-[#aab5af]">Kirim jawaban</button>}</section>
      <aside className="h-fit rounded-lg bg-[#e7eee9] p-5 xl:sticky xl:top-24"><p className="text-xs font-semibold text-[#5e7067]">Status pengerjaan</p><div className="mt-4 flex items-end justify-between"><span className="text-4xl font-bold">{Object.keys(answers).length}/{questions.length}</span><span className="pb-1 text-sm text-[#59655f]">terjawab</span></div><div className="mt-4 h-2 rounded-full bg-white"><div className="h-full rounded-full bg-[#176148]" style={{ width: (Object.keys(answers).length / questions.length) * 100 + '%' }} /></div><p className="mt-6 border-t border-[#cfd8d1] pt-5 text-xs leading-5 text-[#68756f]">Jawaban tersimpan selama halaman ini terbuka.</p></aside>
    </div>
  );
};

const AdminScreen = ({ search, setSearch, items, status, refresh, message }: { search: string; setSearch: (value: string) => void; items: typeof participants; status: AdminState; refresh: () => void; message: (value: string) => void }) => (
  <div className="space-y-5">
    <section className="grid overflow-hidden rounded-lg bg-[#10251d] text-white lg:grid-cols-[1.2fr_.8fr]">
      <div className="p-5 sm:p-7"><p className="text-sm font-semibold text-[#afc1b9]">Operasional hari ini</p><h3 className="mt-2 max-w-xl text-[clamp(1.75rem,4vw,2.75rem)] font-bold leading-[1.12]">Pantau pembayaran, akses, dan progres dari satu layar.</h3><div className="mt-8 grid grid-cols-2 gap-5 sm:grid-cols-4">{['Peserta aktif', 'Pembayaran', 'Perlu ditinjau', 'Sertifikat'].map((label) => <div key={label} className="border-l border-white/15 pl-3"><p className="text-xl font-bold">[DATA]</p><p className="mt-1 text-xs text-[#afc1b9]">{label}</p></div>)}</div></div>
      <div className="border-t border-white/12 bg-white/5 p-5 sm:p-7 lg:border-l lg:border-t-0"><p className="text-xs font-semibold text-[#afc1b9]">Tindakan cepat</p><div className="mt-4 grid gap-2"><QuickAction icon={UsersRound} label="Tambah akses peserta" click={() => message('Form pemberian akses peserta dibuka.')} /><QuickAction icon={Award} label="Tinjau sertifikat" click={() => message('Antrian sertifikat dibuka.')} /><QuickAction icon={Download} label="Ekspor laporan" click={() => message('Laporan disiapkan untuk diekspor.')} /></div></div>
    </section>
    <section className="rounded-lg border border-[#d8ddd7] bg-white">
      <div className="flex flex-col gap-4 border-b border-[#e2e6e1] p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5"><div><h3 className="text-lg font-bold">Monitoring peserta</h3><p className="mt-1 text-sm text-[#68756f]">Data simulasi untuk memperlihatkan struktur laporan.</p></div><div className="flex gap-2"><SearchInput value={search} setValue={setSearch} placeholder="Cari peserta atau kelas" compact /><button onClick={refresh} aria-label="Perbarui data" className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md border border-[#cbd3cd] hover:bg-[#edf1ee]"><RefreshCw className={'h-4 w-4 ' + (status === 'loading' ? 'animate-spin' : '')} /></button></div></div>
      {status === 'loading' ? <Loading /> : status === 'error' ? <InlineState title="Data tidak dapat dimuat" description="Periksa koneksi, lalu coba kembali." action="Coba lagi" click={refresh} /> : items.length === 0 ? <InlineState title="Tidak ada hasil" description="Ubah kata kunci untuk menampilkan peserta lain." action="Hapus pencarian" click={() => setSearch('')} /> : <ParticipantTable items={items} message={message} />}
    </section>
  </div>
);

const ParticipantTable = ({ items, message }: { items: typeof participants; message: (value: string) => void }) => (
  <div className="demo-scrollbar overflow-x-auto"><table className="w-full min-w-[760px] text-left text-sm"><thead><tr className="bg-[#f7f8f5] text-xs text-[#68756f]"><th className="px-5 py-3">Peserta</th><th className="px-5 py-3">Kelas</th><th className="px-5 py-3">Pembayaran</th><th className="px-5 py-3">Progress</th><th className="px-5 py-3">Kehadiran</th><th className="px-5 py-3 text-right">Tindakan</th></tr></thead><tbody>{items.map((item) => <tr key={item.name} className="border-t border-[#e8ebe7]"><td className="px-5 py-4 font-semibold">{item.name}</td><td className="px-5 py-4 text-[#59655f]">{item.course}</td><td className="px-5 py-4"><span className={'rounded-md px-2 py-1 text-xs font-semibold ' + (item.payment === 'Lunas' ? 'bg-[#e3f0e9] text-[#174b39]' : 'bg-[#f5ead0] text-[#75520d]')}>{item.payment}</span></td><td className="px-5 py-4">{item.progress}</td><td className="px-5 py-4">{item.attendance}</td><td className="px-5 py-4 text-right"><button onClick={() => message('Detail ' + item.name + ' dibuka.')} aria-label={'Buka detail ' + item.name} className="inline-flex h-10 w-10 items-center justify-center rounded-md hover:bg-[#e9eee9]"><MoreHorizontal className="h-5 w-5" /></button></td></tr>)}</tbody></table></div>
);

const InstructorScreen = ({ upload, message }: { upload: () => void; message: (value: string) => void }) => (
  <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_350px]">
    <div className="space-y-5"><section className="rounded-lg border border-[#d8ddd7] bg-white p-5 sm:p-7"><div className="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between"><div className="max-w-2xl"><p className="text-sm font-semibold text-[#176148]">Bahasa Arab Pemula</p><h3 className="mt-2 text-3xl font-bold">Kelola kelas tanpa membuka akses admin.</h3><p className="mt-3 text-sm leading-6 text-[#68756f]">Pengajar dapat menambah materi, memeriksa evaluasi, dan mencatat kehadiran.</p></div><button onClick={upload} className="flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-md bg-[#176148] px-5 text-sm font-bold text-white"><Plus className="h-4 w-4" />Tambah materi</button></div></section><section className="rounded-lg border border-[#d8ddd7] bg-white"><div className="border-b border-[#e2e6e1] p-5"><h3 className="text-lg font-bold">Materi terbaru</h3><p className="mt-1 text-sm text-[#68756f]">Urutan dapat ditinjau sebelum diterbitkan.</p></div><div className="divide-y divide-[#e8ebe7]">{lessons.slice(1).map((lesson, index) => <div key={lesson.title} className="flex items-center gap-4 p-4 sm:px-5"><span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-[#edf1ee] text-[#176148]">{lesson.type === 'PDF' ? <FileText className="h-5 w-5" /> : <Play className="h-4 w-4" />}</span><div className="min-w-0 flex-1"><p className="truncate text-sm font-semibold">{lesson.title}</p><p className="mt-1 text-xs text-[#68756f]">{lesson.type} · {index < 2 ? 'Terbit' : 'Draft'}</p></div><button onClick={() => message(lesson.title + ' dibuka untuk disunting.')} className="min-h-10 rounded-md px-3 text-sm font-semibold text-[#176148] hover:bg-[#edf1ee]">Sunting</button></div>)}</div></section></div>
    <aside className="space-y-5"><section className="rounded-lg bg-[#10251d] p-5 text-white"><p className="text-xs font-semibold text-[#afc1b9]">Agenda pengajar</p><h3 className="mt-2 text-xl font-bold">Pertemuan 7</h3><p className="mt-2 text-sm leading-6 text-[#afc1b9]">Rabu, 20.00 WIB · Jumlah ismiyah</p><button onClick={() => message('Form absensi pertemuan dibuka.')} className="mt-5 min-h-11 w-full rounded-md bg-[#f2b84b] text-sm font-bold text-[#10251d]">Buka absensi</button></section><section className="rounded-lg border border-[#d8ddd7] bg-white p-5"><div className="flex gap-3"><ShieldCheck className="h-5 w-5 text-[#176148]" /><h3 className="font-bold">Hak akses terbatas</h3></div><ul className="mt-4 space-y-3 text-sm text-[#59655f]"><li>Materi dan urutan modul</li><li>Nilai dan catatan evaluasi</li><li>Absensi kelas sendiri</li></ul><p className="mt-5 border-t border-[#e2e6e1] pt-4 text-xs leading-5 text-[#68756f]">Pembayaran dan penerbitan sertifikat tetap dikelola admin.</p></section></aside>
  </div>
);

const CertificateScreen = () => (
  <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_340px]">
    <section className="relative overflow-hidden rounded-lg border border-[#d5c18b] bg-[#fffdf7] px-5 py-10 text-center sm:px-10 sm:py-14 print:border-0"><div className="absolute inset-4 border border-[#d9c99f]" /><div className="relative mx-auto max-w-3xl"><img src="/logo.svg" alt="" className="mx-auto h-14 w-14 rounded-lg bg-[#10251d] p-2.5" /><p className="mt-6 text-sm font-semibold text-[#75520d]">Al Madroj Learning</p><h3 className="mt-3 text-[clamp(2rem,6vw,4.25rem)] font-bold leading-none text-[#173e31]">Syahadah Kelulusan</h3><p className="mx-auto mt-5 max-w-xl text-sm leading-6 text-[#68756f]">Diberikan setelah peserta menuntaskan materi, memenuhi kehadiran, dan lulus evaluasi kelas.</p><div className="mx-auto my-9 h-px max-w-md bg-[#d9c99f]" /><p className="text-xs text-[#68756f]">Diberikan kepada</p><p className="mt-2 text-2xl font-bold">[NAMA PESERTA]</p><p className="mt-5 text-sm text-[#68756f]">atas penyelesaian program</p><p className="mt-2 text-xl font-bold">Bahasa Arab Pemula</p><div className="mt-10 flex flex-col justify-between gap-4 text-xs text-[#68756f] sm:flex-row"><span>[NOMOR OTOMATIS]</span><span className="flex items-center justify-center gap-2"><ShieldCheck className="h-4 w-4 text-[#176148]" />Validasi digital</span><span>[TANGGAL LULUS]</span></div></div></section>
    <aside className="space-y-5"><section className="rounded-lg border border-[#d8ddd7] bg-white p-5"><h3 className="text-lg font-bold">Syarat penerbitan</h3><div className="mt-5 space-y-4">{['Materi selesai', 'Evaluasi lulus', 'Kehadiran cukup', 'Persetujuan admin'].map((item, index) => <div key={item} className="flex gap-3"><span className={'flex h-7 w-7 shrink-0 items-center justify-center rounded-md ' + (index === 0 ? 'bg-[#176148] text-white' : 'bg-[#ecefeb] text-[#68756f]')}>{index === 0 ? <Check className="h-4 w-4" /> : <LockKeyhole className="h-3.5 w-3.5" />}</span><div><p className="text-sm font-semibold">{item}</p><p className="mt-0.5 text-xs text-[#68756f]">Diperiksa otomatis oleh sistem</p></div></div>)}</div><button onClick={() => window.print()} className="mt-6 flex min-h-11 w-full items-center justify-center gap-2 rounded-md bg-[#176148] text-sm font-bold text-white"><Download className="h-4 w-4" />Cetak sertifikat</button></section><section className="rounded-lg bg-[#e7eee9] p-5"><p className="text-sm font-bold">Terbit otomatis</p><p className="mt-2 text-sm leading-6 text-[#59655f]">Sistem memeriksa progress, nilai, dan absensi sebelum sertifikat tersedia.</p></section></aside>
  </div>
);

const MobileNavigation = ({ active, go, more }: { active: Screen; go: (screen: Screen) => void; more: () => void }) => {
  const items = [{ id: 'dashboard' as Screen, label: 'Beranda', icon: House }, { id: 'catalog' as Screen, label: 'Kelas', icon: Search }, { id: 'learning' as Screen, label: 'Belajar', icon: BookOpen }, { id: 'admin' as Screen, label: 'Admin', icon: LayoutDashboard }];
  return <nav className="fixed inset-x-0 bottom-0 z-40 border-t border-[#d8ddd7] bg-white/96 px-2 pb-[max(.4rem,env(safe-area-inset-bottom))] pt-1.5 backdrop-blur-xl lg:hidden"><div className="mx-auto grid max-w-lg grid-cols-5">{items.map((item) => { const Icon = item.icon; const selected = active === item.id; return <button key={item.id} onClick={() => go(item.id)} className={'flex min-h-[56px] flex-col items-center justify-center gap-1 rounded-md text-[10px] font-semibold ' + (selected ? 'text-[#176148]' : 'text-[#68756f]')}><Icon className="h-5 w-5" /><span>{item.label}</span></button>; })}<button onClick={more} className="flex min-h-[56px] flex-col items-center justify-center gap-1 rounded-md text-[10px] font-semibold text-[#68756f]"><MoreHorizontal className="h-5 w-5" /><span>Lainnya</span></button></div></nav>;
};

const MobileMenu = ({ active, go, close, back, contact }: { active: Screen; go: (screen: Screen) => void; close: () => void; back: () => void; contact: () => void }) => (
  <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="fixed inset-0 z-50 bg-[#10251d]/45 backdrop-blur-sm lg:hidden" onMouseDown={(event) => { if (event.currentTarget === event.target) close(); }}>
    <motion.aside role="dialog" aria-modal="true" aria-label="Menu navigasi" initial={{ x: '-100%' }} animate={{ x: 0 }} exit={{ x: '-100%' }} transition={{ type: 'spring', damping: 28, stiffness: 320 }} className="flex h-full w-[min(88vw,340px)] flex-col bg-[#10251d] p-4 text-white">
      <div className="flex items-center justify-between"><Brand /><button onClick={close} aria-label="Tutup menu" className="flex h-11 w-11 items-center justify-center rounded-md hover:bg-white/10"><X className="h-5 w-5" /></button></div>
      <nav className="demo-scrollbar mt-8 flex-1 space-y-1 overflow-y-auto">{navigation.map((item) => <NavButton key={item.id} item={item} active={active === item.id} onClick={() => go(item.id)} />)}</nav>
      <div className="space-y-2 border-t border-white/10 pt-4"><button onClick={contact} className="flex min-h-11 w-full items-center gap-3 rounded-md bg-[#f2b84b] px-4 text-sm font-bold text-[#10251d]"><MessageCircle className="h-4 w-4" />Hubungi tim</button><button onClick={back} className="flex min-h-11 w-full items-center gap-3 rounded-md px-4 text-sm text-[#c6d2cd]"><ArrowLeft className="h-4 w-4" />Kembali ke penawaran</button></div>
    </motion.aside>
  </motion.div>
);

const UploadDialog = ({ close, save }: { close: () => void; save: () => void }) => (
  <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="fixed inset-0 z-[70] flex items-end justify-center bg-[#10251d]/55 backdrop-blur-sm sm:items-center sm:p-4" onMouseDown={(event) => { if (event.currentTarget === event.target) close(); }}>
    <motion.form onSubmit={(event) => { event.preventDefault(); save(); }} role="dialog" aria-modal="true" aria-labelledby="upload-title" initial={{ y: 24 }} animate={{ y: 0 }} exit={{ y: 24 }} className="w-full max-w-lg rounded-t-lg bg-white p-5 sm:rounded-lg sm:p-6">
      <div className="flex items-start justify-between"><div><p className="text-sm font-semibold text-[#176148]">Materi baru</p><h3 id="upload-title" className="mt-1 text-xl font-bold">Tambahkan ke Bahasa Arab Pemula</h3></div><button type="button" onClick={close} aria-label="Tutup dialog" className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md hover:bg-[#edf1ee]"><X className="h-5 w-5" /></button></div>
      <div className="mt-6 space-y-4"><FormField id="material" label="Judul materi" value="" setValue={() => {}} placeholder="Contoh: Latihan percakapan" /><label className="block"><span className="mb-2 block text-sm font-semibold">Jenis materi</span><select className="h-12 w-full rounded-md border border-[#cbd3cd] bg-white px-3 text-sm"><option>Video pembelajaran</option><option>Modul PDF</option><option>Teks materi</option></select></label><label className="flex min-h-28 cursor-pointer flex-col items-center justify-center rounded-md border border-dashed border-[#98a79f] bg-[#f7f8f5] p-5 text-center"><UploadCloud className="h-6 w-6 text-[#176148]" /><span className="mt-2 text-sm font-semibold">Pilih file materi</span><span className="mt-1 text-xs text-[#68756f]">Video atau PDF</span><input type="file" className="sr-only" /></label></div>
      <div className="mt-6 flex justify-end gap-2"><button type="button" onClick={close} className="min-h-11 rounded-md border border-[#cbd3cd] px-4 text-sm font-semibold">Batal</button><button type="submit" className="min-h-11 rounded-md bg-[#176148] px-5 text-sm font-bold text-white">Simpan draft</button></div>
    </motion.form>
  </motion.div>
);

const FormField = ({ id, label, value, setValue, placeholder, error }: { id: string; label: string; value: string; setValue: (value: string) => void; placeholder: string; error?: string }) => <label htmlFor={id} className="block"><span className="mb-2 block text-sm font-semibold">{label}</span><input id={id} value={value} onChange={(event) => setValue(event.target.value)} aria-invalid={Boolean(error)} aria-describedby={error ? id + '-error' : undefined} placeholder={placeholder} className={'h-12 w-full rounded-md border bg-white px-4 text-sm placeholder:text-[#75817b] ' + (error ? 'border-[#a7352a]' : 'border-[#cbd3cd] focus:border-[#176148]')} />{error && <span id={id + '-error'} className="mt-2 block text-xs font-semibold text-[#942c24]">{error}</span>}</label>;
const Payment = ({ active, label, detail, click }: { active: boolean; label: string; detail: string; click: () => void }) => <button type="button" role="radio" aria-checked={active} onClick={click} className={'flex min-h-[72px] items-center gap-3 rounded-md border p-3 text-left ' + (active ? 'border-[#176148] bg-[#edf4ef]' : 'border-[#d8ddd7]')}><span className={'flex h-9 w-9 items-center justify-center rounded-md ' + (active ? 'bg-[#176148] text-white' : 'bg-[#edf0ec]')}><CreditCard className="h-4 w-4" /></span><span><span className="block text-sm font-bold">{label}</span><span className="text-xs text-[#68756f]">{detail}</span></span></button>;
const StatusRow = ({ icon: Icon, label, value }: { icon: React.ElementType; label: string; value: string }) => <div className="flex gap-3"><Icon className="mt-0.5 h-4 w-4 shrink-0 text-[#176148]" /><div><p className="text-sm font-semibold">{label}</p><p className="mt-0.5 text-xs text-[#68756f]">{value}</p></div></div>;
const QuickAction = ({ icon: Icon, label, click }: { icon: React.ElementType; label: string; click: () => void }) => <button onClick={click} className="flex min-h-12 items-center gap-3 rounded-md border border-white/12 px-3 text-left text-sm font-semibold hover:bg-white/8"><Icon className="h-4 w-4 text-[#f2b84b]" />{label}</button>;
const SearchInput = ({ value, setValue, placeholder, compact = false }: { value: string; setValue: (value: string) => void; placeholder: string; compact?: boolean }) => <label className={'relative block min-w-0 ' + (compact ? 'flex-1 sm:w-64' : '')}><span className="sr-only">{placeholder}</span><Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[#68756f]" /><input value={value} onChange={(event) => setValue(event.target.value)} placeholder={placeholder} className="h-11 w-full rounded-md border border-[#cbd3cd] bg-white pl-10 pr-3 text-sm placeholder:text-[#75817b]" /></label>;
const EmptyState = ({ title, description, action, onAction, icon: Icon = Search, success = false }: { title: string; description: string; action: string; onAction: () => void; icon?: React.ElementType; success?: boolean }) => <section className={'mt-5 flex min-h-[340px] flex-col items-center justify-center rounded-lg border p-6 text-center ' + (success ? 'border-[#b9d4c5] bg-[#edf6f1]' : 'border-[#d8ddd7] bg-white')}><span className={'flex h-14 w-14 items-center justify-center rounded-lg ' + (success ? 'bg-[#176148] text-white' : 'bg-[#edf1ee] text-[#176148]')}><Icon className="h-6 w-6" /></span><h3 className="mt-5 text-xl font-bold">{title}</h3><p className="mt-2 max-w-md text-sm leading-6 text-[#68756f]">{description}</p><button onClick={onAction} className="mt-6 min-h-11 rounded-md bg-[#176148] px-5 text-sm font-bold text-white">{action}</button></section>;
const InlineState = ({ title, description, action, click }: { title: string; description: string; action: string; click: () => void }) => <div className="flex min-h-[270px] flex-col items-center justify-center p-6 text-center"><CircleHelp className="h-8 w-8 text-[#176148]" /><h4 className="mt-4 text-lg font-bold">{title}</h4><p className="mt-2 text-sm text-[#68756f]">{description}</p><button onClick={click} className="mt-5 min-h-11 rounded-md border border-[#cbd3cd] px-4 text-sm font-semibold">{action}</button></div>;
const Loading = () => <div aria-live="polite" aria-busy="true" className="p-5"><p className="mb-4 text-sm font-semibold">Memuat data peserta...</p><div className="space-y-3">{[0, 1, 2, 3].map((item) => <div key={item} className="grid grid-cols-[1fr_1.4fr_.7fr] gap-4"><span className="h-10 animate-pulse rounded-md bg-[#e9ece8]" /><span className="h-10 animate-pulse rounded-md bg-[#eef0ed]" /><span className="h-10 animate-pulse rounded-md bg-[#e9ece8]" /></div>)}</div></div>;

export default ProductDemo;
