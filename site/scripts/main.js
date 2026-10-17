/*  MagicWall landing page — progressive enhancement. Single IIFE, plain ES2020,
    no dependencies or globals; every module no-ops when its hooks are missing. */
(() => {
  'use strict';

  document.documentElement.classList.add('js');

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  /** Update text only when it changes, so aria-live regions do not re-announce. */
  const setText = (el, value) => { if (el && value && el.textContent.trim() !== value) el.textContent = value; };

  /** Latest release — GitHub API behind a 30-minute sessionStorage cache. */
  const RELEASE_KEY = 'mw:release:v1';
  const RELEASE_TTL = 30 * 60 * 1000;
  const RELEASE_API = 'https://api.github.com/repos/davidullo/magicwall/releases/latest';
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /** Asset bytes → "7.7 MB"; ISO timestamp → "17 Oct 2026" (fixed English). */
  const formatSize = (bytes) => { const n = Number(bytes); return isFinite(n) && n > 0 ? (n / 1048576).toFixed(1) + ' MB' : ''; };
  const formatDate = (iso) => { const d = new Date(iso);
    return isNaN(d) ? '' : `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`; };
  /** First .dmg asset (case-insensitive), else .zip, else null. */
  const pickAsset = (assets) => {
    const pick = (re) => (assets || []).find((a) => a && re.test(a.name || '')) || null;
    return pick(/\.dmg$/i) || pick(/\.zip$/i);
  };
  /** Fresh cache entry, or null; storage may be unavailable in private mode. */
  const readReleaseCache = () => {
    try {
      const data = JSON.parse(window.sessionStorage.getItem(RELEASE_KEY) || '');
      return data && typeof data.ts === 'number' && Date.now() - data.ts < RELEASE_TTL && data.url ? data : null;
    } catch { return null; }
  };
  const writeReleaseCache = (data) => {
    try { window.sessionStorage.setItem(RELEASE_KEY, JSON.stringify(data)); } catch { /* ignore */ }
  };

  /** Paint release data into every [data-release-*] hook. */
  const renderRelease = (rel) => {
    $$('[data-release-link]').forEach((a) => { a.href = rel.url; a.setAttribute('download', ''); });
    $$('[data-release-version]').forEach((el) => setText(el, rel.tag));
    $$('[data-release-name]').forEach((el) => setText(el, rel.name));
    $$('[data-release-size]').forEach((el) => setText(el, formatSize(rel.bytes)));
    $$('[data-release-date]').forEach((el) => setText(el, formatDate(rel.date)));
    setText($('[data-release-status]'), [rel.tag, formatSize(rel.bytes), 'macOS 15+'].filter(Boolean).join(' · '));
  };

  /** Load the latest release (cache first); keeps placeholders on failure. Never rejects. */
  const initRelease = async () => {
    const status = $('[data-release-status]');
    const hooks = '[data-release-link],[data-release-version],[data-release-name],[data-release-size],[data-release-date]';
    if (!$(hooks) && !status) return;
    try {
      const cached = readReleaseCache();
      if (cached) { renderRelease(cached); return; }
      const res = await fetch(RELEASE_API, { headers: { Accept: 'application/vnd.github+json' } });
      if (!res.ok) throw new Error('release request failed');
      const data = await res.json();
      const asset = pickAsset(data && data.assets);
      if (!asset || !asset.browser_download_url) throw new Error('no downloadable asset');
      const rel = { ts: Date.now(), tag: data.tag_name || '', name: asset.name || '',
        url: asset.browser_download_url, bytes: asset.size, date: data.published_at || '' };
      writeReleaseCache(rel);
      renderRelease(rel);
    } catch { setText(status, 'Latest release on GitHub'); }
  };

  /** Scroll reveal — .is-in once per [data-reveal]; no animation for in-view ones. */
  const initReveal = () => {
    const items = $$('[data-reveal]');
    if (!items.length) return;
    const Observer = window.IntersectionObserver;
    if (reducedMotion() || typeof Observer !== 'function') {
      items.forEach((el) => el.classList.add('is-in'));
      return;
    }
    const vh = window.innerHeight || document.documentElement.clientHeight || 0;
    const pending = items.filter((el) => {
      const rect = el.getBoundingClientRect();
      const seen = rect.top < vh && rect.bottom > 0;
      if (seen) el.classList.add('is-in');
      return !seen;
    });
    if (!pending.length) return;
    const io = new Observer((entries) => entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-in');
      io.unobserve(entry.target);
    }), { threshold: 0.15, rootMargin: '0px 0px -8% 0px' });
    pending.forEach((el) => io.observe(el));
    // Safety net: never leave content hidden if the observer never fires
    // (headless captures, browsers with a broken IntersectionObserver, …).
    window.setTimeout(() => pending.forEach((el) => el.classList.add('is-in')), 2500);
  };

  /** Sticky nav — is-scrolled state plus mobile panel toggle. */
  const initNav = () => {
    const nav = $('[data-nav]');
    if (!nav) return;
    let queued = false;
    const sync = () => { queued = false; nav.classList.toggle('is-scrolled', window.scrollY > 8); };
    sync();
    window.addEventListener('scroll', () => {
      if (!queued) { queued = true; window.requestAnimationFrame(sync); }
    }, { passive: true });
    const toggle = $('[data-nav-toggle]');
    if (!toggle) return;
    const setOpen = (open) => { nav.classList.toggle('is-open', open); toggle.setAttribute('aria-expanded', String(open)); };
    toggle.addEventListener('click', () => setOpen(toggle.getAttribute('aria-expanded') !== 'true'));
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') setOpen(false); });
    const panel = $('[data-nav-panel]');
    if (panel) panel.addEventListener('click', (event) => {
      const link = event.target && event.target.closest && event.target.closest('a');
      if (link) setOpen(false);
    });
    const wide = window.matchMedia('(min-width: 901px)');
    if (typeof wide.addEventListener === 'function') wide.addEventListener('change', (event) => { if (event.matches) setOpen(false); });
  };

  /** Bricks hero — brick-bond span field, cursor parallax, debounced rebuild. */
  const initBricks = () => {
    const host = $('[data-bricks]');
    if (!host || reducedMotion()) return; // reduced motion: CSS shows a static pattern
    let lastW = 0, lastH = 0, builtAt = 0, frame = 0, mx = 50, my = 50;

    /** Regenerate the bond, covering the box plus one extra row and column. */
    const build = () => {
      const width = host.clientWidth;
      const height = host.clientHeight;
      if (!width || !height) return;
      builtAt = Date.now(); lastW = width; lastH = height;
      const cs = window.getComputedStyle(host);
      const w = parseFloat(cs.getPropertyValue('--brick-w')) || 96, h = parseFloat(cs.getPropertyValue('--brick-h')) || 48;
      const rows = Math.ceil(height / h) + 1;
      const cols = Math.ceil(width / w) + 1;
      const frag = document.createDocumentFragment();
      for (let r = 0; r < rows; r += 1) {
        const offset = (r % 2) * 0.5 * w;
        for (let c = 0; c < cols; c += 1) {
          const brick = document.createElement('span');
          brick.className = 'brick'; brick.setAttribute('aria-hidden', 'true');
          brick.style.left = (c * w + offset) + 'px'; brick.style.top = (r * h) + 'px';
          brick.style.setProperty('--d', r * 40 + (c % 6) * 25 + 'ms');
          brick.style.setProperty('--r', (((r * 7 + c * 13) % 11 - 5) / 5 * 0.6).toFixed(2) + 'deg');
          frag.appendChild(brick);
        }
      }
      host.textContent = ''; host.appendChild(frag);
      host.classList.add('is-ready');
    };

    const flush = () => {
      frame = 0;
      host.style.setProperty('--mx', mx.toFixed(2) + '%');
      host.style.setProperty('--my', my.toFixed(2) + '%');
    };
    // Listen on the whole hero: the copy above the bricks sits on top of the
    // field, so pointer events would never reach the bricks themselves.
    const hoverRoot = host.closest('.hero') || host;
    hoverRoot.addEventListener('pointermove', (event) => {
      const rect = host.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      mx = ((event.clientX - rect.left) / rect.width) * 100;
      my = ((event.clientY - rect.top) / rect.height) * 100;
      if (!frame) frame = window.requestAnimationFrame(flush);
    });
    hoverRoot.addEventListener('pointerleave', () => {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0; mx = my = 50;
      host.style.setProperty('--mx', '50%'); host.style.setProperty('--my', '50%');
    });

    // Rebuild only when the box changed by >40px, at most once per 200ms.
    let resizeTimer = 0;
    window.addEventListener('resize', () => {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(() => {
        const changed = Math.abs(host.clientWidth - lastW) > 40 || Math.abs(host.clientHeight - lastH) > 40;
        if (!changed) return;
        const wait = Math.max(0, 200 - (Date.now() - builtAt));
        if (wait) window.setTimeout(build, wait); else build();
      }, 150);
    });

    build();
  };

  /** Hero media — honour reduced motion and data-saver, then play the wallpaper. */
  const initHeroMedia = () => {
    const video = $('.screen-wallpaper');
    if (!video) return;
    const connection = navigator.connection || navigator.mozConnection || {};
    const frugal = connection.saveData === true || /^(slow-)?2g$/.test(connection.effectiveType || '');
    if (reducedMotion() || frugal) {
      video.removeAttribute('autoplay');
      video.pause();
      return;
    }
    const play = () => { const promise = video.play(); if (promise && promise.catch) promise.catch(() => {}); };
    if (video.readyState >= 2) play(); else video.addEventListener('loadeddata', play, { once: true });
  };

  /** Dock — macOS magnification ported from jollycat. Every icon rests at the
      same size (the MagicWall icon sits centred, not enlarged); icons grow in a
      gaussian around the pointer through a CSS `zoom` on .dock-icon-zoom, with
      the targets computed from index distance so zoomed boxes never feed back
      into the measurement that drives them. */
  const initDock = () => {
    const dock = $('[data-dock]');
    if (!dock) return;
    const zoomWrappers = $$('.dock-icon-zoom', dock);
    const count = zoomWrappers.length;
    if (!count) return;

    const MAX_EXTRA = 0.5; // 1 → 1.5 at the pointer
    const HOVER_FALLOFF = 1.2; // gaussian width, in icon slots
    const LERP_SPEED = 0.18; // easing towards the targets
    const REST = 1; // no resting magnification: all icons are the same size

    const current = new Array(count).fill(REST);
    const target = new Array(count).fill(REST);
    let animating = false;

    const apply = () => {
      for (let i = 0; i < count; i += 1) zoomWrappers[i].style.zoom = current[i].toFixed(4);
    };

    apply();
    if (reducedMotion()) return;

    /** Map a pointer X onto a fractional icon slot in [0, count-1]. */
    const computeTargets = (pointerX) => {
      const rect = dock.getBoundingClientRect();
      const cs = window.getComputedStyle(dock);
      const padLeft = parseFloat(cs.paddingLeft) || 0;
      const padRight = parseFloat(cs.paddingRight) || 0;
      const contentLeft = rect.left + padLeft;
      const contentWidth = rect.width - padLeft - padRight;
      if (!contentWidth) return;
      const mouseIndex = ((pointerX - contentLeft) / contentWidth) * count - 0.5;
      for (let i = 0; i < count; i += 1) {
        const distance = Math.abs(i - mouseIndex);
        target[i] = 1 + MAX_EXTRA * Math.exp(-(distance * distance) / HOVER_FALLOFF);
      }
    };

    const animate = () => {
      let settled = true;
      for (let i = 0; i < count; i += 1) {
        const diff = target[i] - current[i];
        if (Math.abs(diff) > 0.001) {
          current[i] += diff * LERP_SPEED;
          settled = false;
        } else {
          current[i] = target[i];
        }
      }
      apply();
      if (settled) animating = false;
      else window.requestAnimationFrame(animate);
    };
    const start = () => {
      if (!animating) {
        animating = true;
        window.requestAnimationFrame(animate);
      }
    };

    dock.addEventListener('pointermove', (event) => {
      if (event.pointerType === 'touch') return;
      computeTargets(event.clientX);
      start();
    });
    dock.addEventListener('pointerleave', () => {
      for (let i = 0; i < count; i += 1) target[i] = REST;
      start();
    });
  };

  /** Misc — footer year plus the html.is-ready fade-in hook. */
  const initMisc = () => {
    const year = String(new Date().getFullYear());
    $$('[data-year]').forEach((el) => setText(el, year));
    const markReady = () => document.documentElement.classList.add('is-ready');
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', markReady, { once: true });
    else markReady();
  };

  /** Boot every module once the DOM is parsed (or right away when it is). */
  const boot = () => {
    initRelease(); initReveal(); initNav(); initBricks();
    initHeroMedia(); initDock(); initMisc();
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
})();
