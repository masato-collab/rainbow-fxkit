/* =================================================================
   Rainbow Project — script.js
   最小限のインタラクション:
     1) ナビゲーションのスクロール状態切替
     2) モバイルメニュー(ハンバーガー)の開閉
     3) IntersectionObserverによるスクロールフェードイン
     4) FAQアコーディオンの「同時に1つだけ開く」任意挙動(軽め)
     5) 外部リンクの自動noopener補完(ついで)
   ================================================================= */
(function () {
  'use strict';

  /* -----------------------------------------------------------------
     prefers-reduced-motion 判定
     ----------------------------------------------------------------- */
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* -----------------------------------------------------------------
     1) ナビゲーションのスクロール状態
        8px以上スクロールしたら .is-scrolled を付与
     ----------------------------------------------------------------- */
  const nav = document.getElementById('nav');
  if (nav) {
    let ticking = false;
    const updateNavState = () => {
      const scrolled = window.scrollY > 8;
      nav.classList.toggle('is-scrolled', scrolled);
      ticking = false;
    };
    updateNavState();
    window.addEventListener('scroll', () => {
      if (!ticking) {
        window.requestAnimationFrame(updateNavState);
        ticking = true;
      }
    }, { passive: true });
  }

  /* -----------------------------------------------------------------
     2) モバイルメニュー開閉
     ----------------------------------------------------------------- */
  const toggle = document.querySelector('.nav__toggle');
  const menu   = document.getElementById('nav-menu');
  if (toggle && menu) {
    const closeMenu = () => {
      toggle.setAttribute('aria-expanded', 'false');
      menu.classList.remove('is-open');
    };
    toggle.addEventListener('click', () => {
      const isOpen = toggle.getAttribute('aria-expanded') === 'true';
      if (isOpen) {
        closeMenu();
      } else {
        toggle.setAttribute('aria-expanded', 'true');
        menu.classList.add('is-open');
      }
    });
    // メニュー内リンクをクリックしたら閉じる
    menu.querySelectorAll('a').forEach((a) => {
      a.addEventListener('click', () => closeMenu());
    });
    // Escキーで閉じる
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeMenu();
    });
    // 画面幅が広がったらリセット
    window.addEventListener('resize', () => {
      if (window.innerWidth > 768) closeMenu();
    });
  }

  /* -----------------------------------------------------------------
     3) スクロールフェードイン (IntersectionObserver)
        .reveal 要素を監視し、viewport進入時に .is-visible を付与
     ----------------------------------------------------------------- */
  const revealEls = document.querySelectorAll('.reveal');
  if (revealEls.length) {
    if (reduceMotion || !('IntersectionObserver' in window)) {
      // モーション抑制または未対応ブラウザ: 一括表示
      revealEls.forEach((el) => el.classList.add('is-visible'));
    } else {
      const io = new IntersectionObserver((entries, observer) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            // 上から順にわずかな遅延(最大400ms)を付けてフェードイン
            const delay = Math.min(
              entry.target.dataset.revealDelay
                ? parseInt(entry.target.dataset.revealDelay, 10)
                : 0,
              400
            );
            setTimeout(() => entry.target.classList.add('is-visible'), delay);
            observer.unobserve(entry.target);
          }
        });
      }, {
        root: null,
        rootMargin: '0px 0px -10% 0px',
        threshold: 0.08
      });
      revealEls.forEach((el) => io.observe(el));
    }
  }

  /* -----------------------------------------------------------------
     4) FAQ: 同じグループ内で1つだけ開く (任意機能)
        .faq 内の details にのみ適用。無効化したい場合は data-faq-single="false"
     ----------------------------------------------------------------- */
  document.querySelectorAll('.faq').forEach((group) => {
    if (group.dataset.faqSingle === 'false') return;
    const items = group.querySelectorAll('details.faq__item');
    items.forEach((d) => {
      d.addEventListener('toggle', () => {
        if (d.open) {
          items.forEach((other) => {
            if (other !== d && other.open) other.open = false;
          });
        }
      });
    });
  });

  /* -----------------------------------------------------------------
     5) 外部リンクに target="_blank" がある場合の noopener 補完
        (テンプレート書き忘れ防止)
     ----------------------------------------------------------------- */
  document.querySelectorAll('a[target="_blank"]').forEach((a) => {
    const rel = a.getAttribute('rel') || '';
    if (!/\bnoopener\b/.test(rel)) {
      a.setAttribute('rel', (rel + ' noopener').trim());
    }
  });

  /* -----------------------------------------------------------------
     6) ページロード時: ヒーロー要素は即座に表示
        (初回表示で IntersectionObserver を待たず印象を良くする)
     ----------------------------------------------------------------- */
  window.addEventListener('load', () => {
    document.querySelectorAll('.hero .reveal').forEach((el, i) => {
      setTimeout(() => el.classList.add('is-visible'), i * 80);
    });
  });

})();
