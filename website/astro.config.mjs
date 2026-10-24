import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import sidebar from './src/data/guide-sidebar.json' with { type: 'json' };

export default defineConfig({
  site: 'https://dpm.bandpassrecords.com',
  integrations: [
    // The user guide, at /guide/. Installed apps still open docs.html, which
    // src/pages/docs.html.ts sends on to the right page.
    starlight({
      title: 'DAW Project Manager',
      logo: { src: './src/assets/app_icon.png' },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/bandpassrecords/daw-project-manager' },
      ],
      sidebar: [
        { label: 'The whole guide on one page', link: '/guide/all/', attrs: { class: 'guide-all-link' } },
        ...sidebar,
      ],
      customCss: ['./src/styles/starlight.css'],
      head: [
        {
          // The palette picked on the homepage, before anything paints.
          tag: 'script',
          content:
            "try{const a=new URLSearchParams(location.search).get('palette');if(a)localStorage.setItem('dpm-palette',a);const p=a||localStorage.getItem('dpm-palette');if(p)document.documentElement.dataset.palette=p}catch{}",
        },
        { tag: 'script', attrs: { src: '/guide-lightbox.js', defer: true } },
      ],
    }),
  ],
});
