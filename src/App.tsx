import React, { useState, useEffect, useCallback, useRef } from 'react';
import { SLIDES, PROPOSAL_META } from './data/proposalData';
import { Navigation } from './components/Navigation';
import { SlideControlBar } from './components/SlideControlBar';
import { ThumbnailDrawer } from './components/ThumbnailDrawer';
import { ProductDemo } from './components/ProductDemo';
import { sound } from './utils/audio';

// Slides imports
import { Slide01Cover } from './components/Slides/Slide01Cover';
import { Slide02ProblemSolution } from './components/Slides/Slide02ProblemSolution';
import { Slide03Philosophy } from './components/Slides/Slide03Philosophy';
import { Slide04PackagesOverview } from './components/Slides/Slide04PackagesOverview';
import { Slide05PackageStarter } from './components/Slides/Slide05PackageStarter';
import { Slide06PackageStandard } from './components/Slides/Slide06PackageStandard';
import { Slide07PackagePro } from './components/Slides/Slide07PackagePro';
import { Slide08Comparison } from './components/Slides/Slide08Comparison';
import { Slide09Calculator } from './components/Slides/Slide09Calculator';
import { Slide10WorkflowPayment } from './components/Slides/Slide10WorkflowPayment';
import { Slide11FaqScope } from './components/Slides/Slide11FaqScope';
import { Slide12ClosingCta } from './components/Slides/Slide12ClosingCta';

type ViewMode = 'presentation' | 'document' | 'demo';

const getInitialViewMode = (): ViewMode => {
  if (window.location.pathname === '/demo-pro-lms') return 'demo';
  return 'presentation';
};

export function App() {
  const [currentSlide, setCurrentSlide] = useState<number>(0);
  const [viewMode, setViewMode] = useState<ViewMode>(getInitialViewMode);
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);
  const [soundEnabled, setSoundEnabled] = useState<boolean>(true);
  const [isThumbnailsOpen, setIsThumbnailsOpen] = useState<boolean>(false);

  // Touch swipe support for mobile
  const touchStartX = useRef<number>(0);
  const touchEndX = useRef<number>(0);

  const totalSlides = SLIDES.length;

  // Initialize sound manager default
  useEffect(() => {
    sound.setEnabled(soundEnabled);
  }, [soundEnabled]);

  // Navigate functions
  const handlePrev = useCallback(() => {
    setCurrentSlide((prev) => Math.max(0, prev - 1));
  }, []);

  const handleNext = useCallback(() => {
    setCurrentSlide((prev) => Math.min(totalSlides - 1, prev + 1));
  }, [totalSlides]);

  const handleJump = useCallback((index: number) => {
    if (index >= 0 && index < totalSlides) {
      setCurrentSlide(index);
    }
  }, [totalSlides]);

  const handleChangeViewMode = useCallback((mode: ViewMode) => {
    setViewMode(mode);
    const nextPath = mode === 'demo' ? '/demo-pro-lms' : '/';
    if (window.location.pathname !== nextPath) {
      window.history.pushState(null, '', nextPath);
    }
  }, []);

  const handleBackToProposal = useCallback(() => {
    handleChangeViewMode('presentation');
  }, [handleChangeViewMode]);

  // Jump to calculator shortcut (Slide index 8)
  const handleJumpToCalculator = useCallback(() => {
    setCurrentSlide(8);
  }, []);

  const handleOpenDemo = useCallback(() => {
    handleChangeViewMode('demo');
  }, [handleChangeViewMode]);

  useEffect(() => {
    const handlePopState = () => {
      setViewMode(getInitialViewMode());
    };
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  // Fullscreen toggle handler
  const handleToggleFullscreen = () => {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen().then(() => {
        setIsFullscreen(true);
      }).catch(() => {});
    } else {
      if (document.exitFullscreen) {
        document.exitFullscreen().then(() => {
          setIsFullscreen(false);
        }).catch(() => {});
      }
    }
  };

  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };
    document.addEventListener('fullscreenchange', handleFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
  }, []);

  // Keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Don't trigger if typing in an input
      if (['input', 'textarea', 'select'].includes((e.target as HTMLElement)?.tagName?.toLowerCase())) {
        return;
      }

      if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'PageDown') {
        if (viewMode === 'presentation') {
          e.preventDefault();
          sound.playSlide();
          handleNext();
        }
      } else if (e.key === 'ArrowLeft' || e.key === 'Backspace' || e.key === 'PageUp') {
        if (viewMode === 'presentation') {
          e.preventDefault();
          sound.playSlide();
          handlePrev();
        }
      } else if (e.key === 'Home') {
        if (viewMode === 'presentation') {
          e.preventDefault();
          sound.playSlide();
          handleJump(0);
        }
      } else if (e.key === 'End') {
        if (viewMode === 'presentation') {
          e.preventDefault();
          sound.playSlide();
          handleJump(totalSlides - 1);
        }
      } else if (e.key === 'f' || e.key === 'F') {
        e.preventDefault();
        handleToggleFullscreen();
      } else if (e.key === 'm' || e.key === 'M') {
        e.preventDefault();
        sound.playClick();
        setViewMode((prev) => (prev === 'presentation' ? 'document' : 'presentation'));
      } else if (e.key === 'g' || e.key === 'G' || e.key === 't' || e.key === 'T') {
        e.preventDefault();
        sound.playClick();
        setIsThumbnailsOpen((prev) => !prev);
      } else if (e.key === 'Escape') {
        setIsThumbnailsOpen(false);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [viewMode, handleNext, handlePrev, handleJump, totalSlides]);

  // Touch Swipe Handlers for mobile
  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.targetTouches[0].clientX;
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    touchEndX.current = e.changedTouches[0].clientX;
    handleSwipe();
  };

  const handleSwipe = () => {
    if (viewMode !== 'presentation') return;
    const diffX = touchStartX.current - touchEndX.current;
    if (diffX > 60) {
      // Swipe left -> Next
      sound.playSlide();
      handleNext();
    } else if (diffX < -60) {
      // Swipe right -> Prev
      sound.playSlide();
      handlePrev();
    }
  };

  // Render Slide Component by Index
  const renderSlideContent = (index: number) => {
    switch (index) {
      case 0:
        return <Slide01Cover onNext={handleNext} onOpenDemo={handleOpenDemo} />;
      case 1:
        return <Slide02ProblemSolution />;
      case 2:
        return <Slide03Philosophy />;
      case 3:
        return <Slide04PackagesOverview onJumpToSlide={handleJump} />;
      case 4:
        return <Slide05PackageStarter onJumpToCalculator={handleJumpToCalculator} />;
      case 5:
        return <Slide06PackageStandard onJumpToCalculator={handleJumpToCalculator} />;
      case 6:
        return <Slide07PackagePro onJumpToCalculator={handleJumpToCalculator} />;
      case 7:
        return <Slide08Comparison />;
      case 8:
        return <Slide09Calculator />;
      case 9:
        return <Slide10WorkflowPayment />;
      case 10:
        return <Slide11FaqScope />;
      case 11:
        return <Slide12ClosingCta onJumpToCalculator={handleJumpToCalculator} />;
      default:
        return <Slide01Cover onNext={handleNext} onOpenDemo={handleOpenDemo} />;
    }
  };

  if (viewMode === 'demo') {
    return <ProductDemo onBackToProposal={handleBackToProposal} />;
  }

  return (
    <div 
      className="min-h-screen bg-slate-950 text-slate-100 flex flex-col justify-between selection:bg-emerald-500 selection:text-slate-950 relative overflow-x-hidden font-sans"
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      {/* Ambient background glows */}
      <div className="fixed top-0 left-1/4 w-[600px] h-[600px] bg-emerald-500/5 rounded-full blur-[140px] pointer-events-none -z-10" />
      <div className="fixed bottom-0 right-1/4 w-[600px] h-[600px] bg-cyan-500/5 rounded-full blur-[140px] pointer-events-none -z-10" />
      <div className="fixed top-1/2 right-10 w-[400px] h-[400px] bg-amber-500/5 rounded-full blur-[120px] pointer-events-none -z-10" />

      {/* Top Navigation */}
      <Navigation
        currentSlide={currentSlide}
        totalSlides={totalSlides}
        currentSlideTitle={SLIDES[currentSlide]?.title || ''}
        isFullscreen={isFullscreen}
        onToggleFullscreen={handleToggleFullscreen}
        viewMode={viewMode}
        onToggleViewMode={handleChangeViewMode}
        soundEnabled={soundEnabled}
        onToggleSound={() => {
          const next = !soundEnabled;
          setSoundEnabled(next);
          sound.setEnabled(next);
        }}
        onOpenThumbnails={() => setIsThumbnailsOpen(true)}
      />

      {/* Main Presentation View */}
      {viewMode === 'presentation' ? (
        <main className="flex-1 flex flex-col items-center justify-center px-4 sm:px-6 lg:px-8 py-6 pb-28 min-h-[calc(100vh-140px)]">
          <div key={currentSlide} className="w-full animate-slide-in">
            {renderSlideContent(currentSlide)}
          </div>
        </main>
      ) : (
        /* Continuous Document Scroll View */
        <main className="flex-1 max-w-5xl mx-auto px-4 sm:px-6 py-10 space-y-16">
          <div className="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-300 text-center no-print">
            Anda sedang melihat proposal dalam <strong>Mode Dokumen (Scroll Penuh)</strong>. Gunakan mode ini untuk membaca santai atau mencetak/ekspor ke PDF.
          </div>

          {SLIDES.map((slide, index) => (
            <section key={slide.id} id={slide.id} className="scroll-mt-24 print-page-break">
              <div className="flex items-center gap-3 mb-4 no-print">
                <span className="text-xs font-mono px-2.5 py-0.5 rounded-full bg-slate-900 border border-white/10 text-emerald-400">
                  SLIDE {String(index + 1).padStart(2, '0')}
                </span>
                <span className="text-xs font-mono uppercase text-slate-400">{slide.category}</span>
                <div className="h-px bg-white/10 flex-1" />
              </div>

              {renderSlideContent(index)}
            </section>
          ))}
        </main>
      )}

      {/* Slide Navigation Bottom Bar (Presentation Mode only) */}
      {viewMode === 'presentation' && (
        <SlideControlBar
          currentSlide={currentSlide}
          totalSlides={totalSlides}
          onPrev={handlePrev}
          onNext={handleNext}
          onJump={handleJump}
          onOpenThumbnails={() => setIsThumbnailsOpen(true)}
        />
      )}

      {/* Thumbnail Drawer / Grid Overview Modal */}
      <ThumbnailDrawer
        isOpen={isThumbnailsOpen}
        onClose={() => setIsThumbnailsOpen(false)}
        currentSlide={currentSlide}
        onSelectSlide={handleJump}
      />
    </div>
  );
}

export default App;
