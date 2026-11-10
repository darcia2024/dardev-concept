/* Video dekoratif beranda. Terpisah dari booking agar kegagalan media tidak
   menghalangi formulir, dan tidak mengunduh video dalam mode hemat data. */
(function () {
  'use strict';
  const video = document.getElementById('heroVideo');
  if (!video) return;

  const gerakDikurangi = window.matchMedia('(prefers-reduced-motion: reduce)');
  const koneksi = navigator.connection;
  let inginPutar = !gerakDikurangi.matches && !(koneksi && koneksi.saveData);
  const posisi = video.getBoundingClientRect();
  let terlihat = posisi.bottom > 0 && posisi.top < window.innerHeight;
  let gagal = false;

  function sesuaikan() {
    if (!inginPutar || !terlihat || document.hidden || gagal) {
      video.pause();
      return;
    }
    if (!video.getAttribute('src')) {
      video.src = window.matchMedia('(max-width: 760px)').matches
        ? video.dataset.mobileSrc : video.dataset.src;
    }
    video.muted = true;
    const putar = video.play();
    if (putar && putar.catch) putar.catch(function (error) {
      // pause() saat bergulir/tab berpindah boleh membatalkan play() yang
      // masih menunggu data. Video bisa berlanjut saat kembali terlihat.
      if (error.name === 'AbortError') return;
      inginPutar = false;
    });
  }

  video.addEventListener('error', function () {
    gagal = true;
    video.hidden = true;
  });
  document.addEventListener('visibilitychange', sesuaikan);
  gerakDikurangi.addEventListener('change', function () {
    inginPutar = !gerakDikurangi.matches && !(koneksi && koneksi.saveData);
    sesuaikan();
  });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      terlihat = entries[0].isIntersecting;
      sesuaikan();
    }).observe(video);
  }
  sesuaikan();
}());
