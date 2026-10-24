import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

// The user guide's pages: src/content/docs/guide/, served by Starlight.
export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
};
