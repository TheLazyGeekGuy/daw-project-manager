// Every DAW the app finds, and what a deep scan reads from each one's project
// file. The homepage's grid and table and the guide's grid and matrix are all
// drawn from this list, so the two pages can't disagree again.

export type Read =
  | 'tempo'
  | 'key'
  | 'version'
  | 'notes'
  | 'markers'
  | 'tracks'
  | 'plugins'
  | 'midiClips'
  | 'midiEvents';

export interface Daw {
  name: string;
  /** A shorter name for the guide's tight grid. */
  short?: string;
  /** File name in resources/daw/logos. */
  logo: string;
  /** What a deep scan reads; empty for a DAW that is found and listed only. */
  reads: Read[];
  /** Marks a footnote on the homepage table (see [footnotes])… */
  mark?: '*' | '†';
  /** …after that cell's tick, or else after the name. */
  markOn?: Read;
  /** Shown after the name in the guide's matrix. */
  qualifier?: string;
}

export const readLabels: Record<Read, string> = {
  tempo: 'Tempo',
  key: 'Key',
  version: 'Version',
  notes: 'Notes',
  markers: 'Markers',
  tracks: 'Tracks',
  plugins: 'Plug-ins',
  midiClips: 'MIDI clips',
  midiEvents: 'MIDI events',
};

export const allReads = Object.keys(readLabels) as Read[];

const full: Read[] = ['tempo', 'key', 'version', 'notes', 'tracks', 'plugins', 'midiClips'];
const basic: Read[] = ['tempo', 'key', 'version'];

export const daws: Daw[] = [
  { name: 'Ableton Live', logo: 'ableton-live.png', reads: ['tempo', 'key', 'version', 'tracks', 'plugins', 'midiClips', 'midiEvents'] },
  { name: 'Bitwig Studio', logo: 'bitwig-studio.png', reads: basic, mark: '*', markOn: 'key' },
  { name: 'Cakewalk / Sonar', logo: 'cakewalk.png', reads: [] },
  { name: 'Cubase', logo: 'cubase.png', reads: full },
  { name: 'FL Studio', logo: 'fl-studio.png', reads: ['tempo', 'version', 'tracks', 'plugins', 'midiClips'] },
  { name: 'Logic Pro', logo: 'logic-pro.png', reads: basic, mark: '†', qualifier: '(on macOS)' },
  { name: 'MAGDA', logo: 'magda.png', reads: basic },
  { name: 'Maschine', logo: 'maschine.png', reads: [] },
  { name: 'Nuendo', logo: 'nuendo.png', reads: full },
  { name: 'Pro Tools', logo: 'pro-tools.png', reads: [] },
  { name: 'Reaper', logo: 'reaper.png', reads: [...full, 'markers', 'midiEvents'] },
  { name: 'Studio One', logo: 'studio-one.png', reads: ['tempo', 'version', 'tracks'] },
  { name: 'Tracktion Waveform', short: 'Waveform', logo: 'tracktion-waveform.png', reads: [] },
  { name: 'Universal Audio LUNA', short: 'LUNA', logo: 'luna.png', reads: [] },
  { name: 'Ardour', logo: 'ardour.png', reads: [] },
  { name: 'GarageBand', logo: 'garageband.png', reads: [] },
  { name: 'Renoise', logo: 'renoise.png', reads: [] },
  { name: 'LMMS', logo: 'lmms.png', reads: [] },
  { name: 'Audacity', logo: 'audacity.png', reads: [] },
  { name: 'Qtractor', logo: 'qtractor.png', reads: [] },
  { name: 'Reason', logo: 'reason.png', reads: [] },
  { name: 'Digital Performer', logo: 'digital-performer.png', reads: [] },
  { name: 'Adobe Audition', short: 'Audition', logo: 'adobe-audition.png', reads: [] },
  { name: 'Samplitude / Sequoia', short: 'Samplitude', logo: 'samplitude-sequoia.png', reads: [] },
  { name: 'ACID Pro', logo: 'acid-pro.png', reads: [] },
  { name: 'Mixcraft', logo: 'mixcraft.png', reads: [] },
  { name: 'Rosegarden', logo: 'rosegarden.png', reads: [] },
  { name: 'Zrythm', logo: 'zrythm.png', reads: [] },
];

export const footnotes: Record<NonNullable<Daw['mark']>, string> = {
  '*': 'Key detection requires Bitwig Studio 6 or later.',
  '†': 'Logic Pro extraction runs on macOS only — a <code class="daw-ext">.logicx</code> project opened on Windows or Linux is still detected, just without BPM, key or version.',
};

/** The DAWs read inside, the most read first (the guide's order). */
export const deepDaws = daws
  .filter((d) => d.reads.length > 0)
  .sort((a, b) => b.reads.length - a.reads.length);

/** The same DAWs alphabetically (the homepage table's order). */
export const deepDawsByName = [...deepDaws].sort((a, b) => a.name.localeCompare(b.name));

export const logoUrl = (daw: Daw) => `/resources/daw/logos/${daw.logo}`;
