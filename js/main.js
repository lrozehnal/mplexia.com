/* ============================================================
   Mplexia Limited – Main JavaScript
   ============================================================ */

/* Add 'js' class to <html> immediately so CSS animations are
   only applied when JavaScript is available. */
document.documentElement.classList.add('js');

(function () {
  'use strict';

  /* ── Sticky header ──────────────────────────────────────── */
  const header = document.getElementById('site-header');
  function onScroll() {
    if (window.scrollY > 20) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll(); // run once on load

  /* ── Mobile nav toggle ──────────────────────────────────── */
  const toggle   = document.getElementById('nav-toggle');
  const navLinks = document.getElementById('nav-links');

  toggle.addEventListener('click', function () {
    const isOpen = navLinks.classList.toggle('open');
    toggle.classList.toggle('open', isOpen);
    toggle.setAttribute('aria-expanded', String(isOpen));
    document.body.style.overflow = isOpen ? 'hidden' : '';
  });

  // Close nav when a link is clicked
  navLinks.querySelectorAll('.nav-link').forEach(function (link) {
    link.addEventListener('click', function () {
      navLinks.classList.remove('open');
      toggle.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = '';
    });
  });

  // Close nav on Escape
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && navLinks.classList.contains('open')) {
      navLinks.classList.remove('open');
      toggle.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = '';
      toggle.focus();
    }
  });

  /* ── Scroll-reveal ──────────────────────────────────────── */
  const revealEls = document.querySelectorAll(
    '.card, .about-grid, .why-item, .contact-card, .why-text'
  );
  revealEls.forEach(function (el) {
    el.classList.add('reveal');
  });

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    revealEls.forEach(function (el) { observer.observe(el); });
  } else {
    // Fallback: show all immediately
    revealEls.forEach(function (el) { el.classList.add('visible'); });
  }

  /* ── Footer year ────────────────────────────────────────── */
  const yearEl = document.getElementById('year');
  if (yearEl) {
    yearEl.textContent = new Date().getFullYear();
  }

  /* ── Active nav link on scroll ──────────────────────────── */
  const sections = document.querySelectorAll('main [id]');
  const navItems = document.querySelectorAll('.nav-links .nav-link');

  function setActiveNav() {
    let current = '';
    sections.forEach(function (sec) {
      const top = sec.getBoundingClientRect().top;
      if (top <= 100) {
        current = sec.getAttribute('id');
      }
    });
    navItems.forEach(function (link) {
      link.removeAttribute('aria-current');
      if (link.getAttribute('href') === '#' + current) {
        link.setAttribute('aria-current', 'true');
      }
    });
  }

  window.addEventListener('scroll', setActiveNav, { passive: true });

})();
