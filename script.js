'use strict';

/* ============================================================
   PARTICLE CANVAS
   ============================================================ */
(function () {
  const canvas = document.getElementById('canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  const CONFIG = {
    count:        80,
    connectDist:  160,
    speed:        0.35,
    nodeRadius:   2.2,
    color:        '99,102,241',
    lineAlpha:    0.18,
    nodeAlpha:    0.55,
  };

  let W, H, nodes;

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
  }

  function makeNode() {
    return {
      x:  Math.random() * W,
      y:  Math.random() * H,
      vx: (Math.random() - 0.5) * CONFIG.speed,
      vy: (Math.random() - 0.5) * CONFIG.speed,
    };
  }

  function init() {
    resize();
    nodes = Array.from({ length: CONFIG.count }, makeNode);
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);

    // move & wrap
    for (const n of nodes) {
      n.x += n.vx;
      n.y += n.vy;
      if (n.x < 0)  n.x = W;
      if (n.x > W)  n.x = 0;
      if (n.y < 0)  n.y = H;
      if (n.y > H)  n.y = 0;
    }

    // lines
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        const dx = nodes[i].x - nodes[j].x;
        const dy = nodes[i].y - nodes[j].y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < CONFIG.connectDist) {
          const alpha = CONFIG.lineAlpha * (1 - dist / CONFIG.connectDist);
          ctx.beginPath();
          ctx.strokeStyle = `rgba(${CONFIG.color},${alpha})`;
          ctx.lineWidth = 0.8;
          ctx.moveTo(nodes[i].x, nodes[i].y);
          ctx.lineTo(nodes[j].x, nodes[j].y);
          ctx.stroke();
        }
      }
    }

    // dots
    for (const n of nodes) {
      ctx.beginPath();
      ctx.arc(n.x, n.y, CONFIG.nodeRadius, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${CONFIG.color},${CONFIG.nodeAlpha})`;
      ctx.fill();
    }

    requestAnimationFrame(draw);
  }

  window.addEventListener('resize', () => {
    resize();
    // re-clamp nodes to new bounds
    for (const n of nodes) {
      n.x = Math.min(n.x, W);
      n.y = Math.min(n.y, H);
    }
  });

  init();
  draw();
})();


/* ============================================================
   TYPED TEXT
   ============================================================ */
(function () {
  const el = document.getElementById('typed');
  if (!el) return;

  const phrases = [
    'Lead AI & Data Engineer',
    'Agentic AI Architect',
    'Databricks Platform Expert',
    'RAG & LLMOps Engineer',
    'Data Platform Lead',
  ];

  let phraseIdx = 0;
  let charIdx   = 0;
  let deleting  = false;
  const PAUSE   = 1800;
  const TYPE_MS = 65;
  const DEL_MS  = 32;

  function tick() {
    const current = phrases[phraseIdx];

    if (!deleting) {
      el.textContent = current.slice(0, ++charIdx);
      if (charIdx === current.length) {
        deleting = true;
        setTimeout(tick, PAUSE);
        return;
      }
    } else {
      el.textContent = current.slice(0, --charIdx);
      if (charIdx === 0) {
        deleting  = false;
        phraseIdx = (phraseIdx + 1) % phrases.length;
      }
    }

    setTimeout(tick, deleting ? DEL_MS : TYPE_MS);
  }

  setTimeout(tick, 600);
})();


/* ============================================================
   NAVBAR — SCROLL CLASS
   ============================================================ */
(function () {
  const nav = document.getElementById('navbar');
  if (!nav) return;

  const onScroll = () => {
    nav.classList.toggle('scrolled', window.scrollY > 20);
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();


/* ============================================================
   HAMBURGER / MOBILE DRAWER
   ============================================================ */
(function () {
  const btn    = document.getElementById('hamburger');
  const drawer = document.getElementById('mobileDrawer');
  if (!btn || !drawer) return;

  function close() {
    btn.classList.remove('open');
    drawer.classList.remove('open');
    document.body.style.overflow = '';
  }

  btn.addEventListener('click', () => {
    const opening = !drawer.classList.contains('open');
    btn.classList.toggle('open', opening);
    drawer.classList.toggle('open', opening);
    document.body.style.overflow = opening ? 'hidden' : '';
  });

  document.querySelectorAll('.drawer-link').forEach(a => {
    a.addEventListener('click', close);
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 768) close();
  });
})();


/* ============================================================
   COUNTER ANIMATIONS
   ============================================================ */
(function () {
  const counters = document.querySelectorAll('.stat-num');
  if (!counters.length) return;

  let fired = false;

  function animateCounter(el) {
    const target   = parseInt(el.dataset.target, 10);
    const duration = 1600;
    const start    = performance.now();

    function step(now) {
      const progress = Math.min((now - start) / duration, 1);
      // ease-out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.floor(eased * target);
      if (progress < 1) requestAnimationFrame(step);
      else el.textContent = target;
    }

    requestAnimationFrame(step);
  }

  function tryFire(entries) {
    for (const e of entries) {
      if (e.isIntersecting && !fired) {
        fired = true;
        counters.forEach(animateCounter);
      }
    }
  }

  const heroSection = document.getElementById('hero');
  if (!heroSection) return;

  const obs = new IntersectionObserver(tryFire, { threshold: 0.3 });
  obs.observe(heroSection);
})();


/* ============================================================
   SCROLL ANIMATIONS (AOS-like)
   ============================================================ */
(function () {
  const elements = document.querySelectorAll('[data-aos], .skill-card, .timeline-item, .project-card, .edu-card, .cert-card, .contact-card');

  function check() {
    const vh = window.innerHeight;
    for (const el of elements) {
      const rect = el.getBoundingClientRect();
      if (rect.top < vh * 0.9 && rect.bottom > 0) {
        el.classList.add('visible');
      }
    }
  }

  window.addEventListener('scroll', check, { passive: true });
  window.addEventListener('resize', check, { passive: true });
  // Run after paint so initial viewport elements are caught
  requestAnimationFrame(() => { requestAnimationFrame(check); });
})();


/* ============================================================
   SMOOTH SCROLL FOR NAV LINKS
   ============================================================ */
(function () {
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const target = document.querySelector(a.getAttribute('href'));
      if (!target) return;
      e.preventDefault();
      const navH = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--nav-h'), 10) || 68;
      const top  = target.getBoundingClientRect().top + window.scrollY - navH;
      window.scrollTo({ top, behavior: 'smooth' });
    });
  });
})();
