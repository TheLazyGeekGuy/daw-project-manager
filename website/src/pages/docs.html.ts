// docs.html was the whole guide on one page, and installed apps still open
// it, often with an anchor (docs.html#work-sessions). It now sends each
// anchor to the guide page that holds that section.
import anchors from '../data/guide-anchors.json';

export function GET() {
  const map = JSON.stringify(anchors);
  const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>User guide — DAW Project Manager</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="/guide/overview/">
<script>
  const anchors = ${map};
  const id = location.hash.slice(1);
  location.replace('/guide/' + (anchors[id] || 'overview') + '/');
</script>
<noscript><meta http-equiv="refresh" content="0; url=/guide/overview/"></noscript>
</head>
<body><a href="/guide/overview/">The user guide has moved.</a></body>
</html>
`;
  return new Response(page, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}
