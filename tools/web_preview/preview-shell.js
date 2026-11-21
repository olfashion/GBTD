(function () {
  'use strict';
  const coarse = window.matchMedia('(pointer: coarse)');
  function updateTouchMode() {
    document.documentElement.classList.toggle('has-touch', coarse.matches || navigator.maxTouchPoints > 0);
  }
  updateTouchMode();
  coarse.addEventListener('change', updateTouchMode);
  document.getElementById('reload-game').addEventListener('click', () => window.location.reload());
}());
