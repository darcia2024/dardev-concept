(function () {
  'use strict';

  // Urutan di sini mengikuti urutan tampil dari kiri ke kanan.
  const fotoGaleri = [
    ['media/galeri/9874.webp', 'Tampak samping rambut disisir ke belakang dengan tengkuk panjang'],
    ['media/galeri/9852.webp', 'Tampak samping potongan bergelombang dengan bagian depan terangkat'],
    ['media/galeri/9848.webp', 'Poni belah tengah bertekstur dengan sisi tipis'],
    ['media/galeri/9845.webp', 'Potongan belah tengah dengan rambut disisir rapi'],
    ['media/galeri/9827.webp', 'Rambut berlapis dengan poni panjang dan pelipis meruncing'],
    ['media/galeri/9826.webp', 'Rambut atas bervolume dengan gradasi pendek di sisi'],
    ['media/galeri/9821.webp', 'Tampak samping potongan pendek dengan ujung rambut mengarah ke atas'],
    ['media/galeri/9813.webp', 'Garis pelipis tegas pada potongan pendek dengan atasan rata'],
    ['media/galeri/9787.webp', 'Rambut belah tengah dengan poni bergelombang ke samping'],
    ['media/galeri/9768.webp', 'Poni ikal jatuh ke depan dengan sisi dipangkas pendek'],
    ['media/galeri/9742.webp', 'Potongan berponi dengan rambut lebih panjang di tengkuk'],
    ['media/galeri/9735.webp', 'Rambut dibelah dan diangkat ke belakang dengan sisi rapi'],
    ['media/galeri/9729.webp', 'Poni panjang bergelombang membingkai kedua sisi wajah'],
    ['media/galeri/9716.webp', 'Belahan samping tegas dengan rambut tersisir licin'],
    ['media/galeri/0193.webp', 'Poni pendek bertekstur dengan gradasi di sekeliling telinga'],
  ];

  const deret = document.createElement('div');
  deret.className = 'galeri-deret';
  for (const [src, alt] of fotoGaleri) {
    const foto = document.createElement('img');
    foto.width = foto.height = 600;
    foto.decoding = 'async';
    foto.fetchPriority = 'low';
    foto.alt = alt;
    foto.src = src;
    deret.append(foto);
  }

  const salinan = deret.cloneNode(true);
  salinan.setAttribute('aria-hidden', 'true');
  document.getElementById('lintasanGaleri').append(deret, salinan);
}());
