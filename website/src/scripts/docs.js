// The user guide: contents that follow the reader, search, and the screenshot lightbox.
(function () {
    const nav = document.getElementById('guide-nav');
    const links = [...nav.querySelectorAll('a')];
    const sections = [...document.querySelectorAll('.doc')];

    // The contents link for the section on screen.
    const byId = new Map(links.map(a => [a.getAttribute('href').slice(1), a]));
    const spy = new IntersectionObserver(entries => {
        for (const e of entries) {
            if (!e.isIntersecting) continue;
            links.forEach(a => a.classList.remove('active'));
            byId.get(e.target.id)?.classList.add('active');
        }
    }, { rootMargin: '-30% 0px -60% 0px' });
    sections.forEach(s => spy.observe(s));

    // Search: sections whose words don't match are hidden, with their links.
    const search = document.getElementById('guide-search');
    const noMatch = document.getElementById('no-match');
    search.addEventListener('input', () => {
        const q = search.value.trim().toLowerCase();
        let shown = 0;
        for (const s of sections) {
            const hit = !q || s.textContent.toLowerCase().includes(q);
            s.classList.toggle('hidden-by-search', !hit);
            byId.get(s.id)?.classList.toggle('hidden-by-search', !hit);
            if (hit) shown++;
        }
        noMatch.style.display = shown ? 'none' : 'block';
    });

    // Phones: the contents behind a button.
    const toggle = document.getElementById('guide-nav-toggle');
    toggle.addEventListener('click', () => {
        const open = nav.classList.toggle('open');
        toggle.setAttribute('aria-expanded', String(open));
    });
    links.forEach(a => a.addEventListener('click', () => nav.classList.remove('open')));

    // A screenshot, clicked, opens full size; Esc, a click or × closes it.
    const box = document.getElementById('lightbox');
    const boxImg = document.getElementById('lightbox-img');
    const open = img => {
        boxImg.src = img.currentSrc || img.src;
        boxImg.alt = img.alt;
        box.classList.add('open');
        document.body.classList.add('lightbox-open');
    };
    const close = () => {
        box.classList.remove('open');
        document.body.classList.remove('lightbox-open');
    };
    document.querySelectorAll('.shot img').forEach(img => img.addEventListener('click', () => open(img)));
    box.addEventListener('click', close);
    document.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });

    // Opened on #a-section: land there again once the pictures are in,
    // in case anything still moved while they loaded.
    window.addEventListener('load', () => {
        const target = location.hash && document.getElementById(location.hash.slice(1));
        if (target) target.scrollIntoView();
    });
})();
