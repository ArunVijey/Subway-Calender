// Loads the web app's pure logic (parser, repeats, merge, line matching)
// from ../../../index.html into a sandbox, with the clock pinned to `now`.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function loadWebApp(NOW) {
  const html = fs.readFileSync(path.join(__dirname, '../../../index.html'), 'utf8');
  const script = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));

  // Pull out the pure sections; everything that touches the DOM is skipped.
  function section(startMarker, endMarker) {
    const a = script.indexOf(startMarker), b = script.indexOf(endMarker, a);
    if (a < 0 || b < 0) throw new Error('marker not found: ' + startMarker);
    return script.slice(a, b);
  }
  const helpers = section('const $ = id', 'const ICON =');
  const state = section('const PALETTE', "const KEY = 'subway3'");
  const lines = section('const lineOf', '// ---------- toast');
  const ical = section('// ---------- iCal parsing', '// ---------- merging synced events');
  const mergeSrc = section('function merge(', 'function feedName');
  const googleSrc = section('function fromGoogle(', 'async function gPull(');

  const ctx = { console, Intl, Math, JSON, String, Number, Set, Map, Array, Object, RegExp, isFinite, parseInt, encodeURIComponent, decodeURIComponent, URL };
  ctx.Date = class extends Date {
    constructor(...a) { super(...(a.length ? a : [NOW])); }
    static now() { return NOW; }
  };
  ctx.Date.UTC = Date.UTC;
  ctx.Date.parse = Date.parse;
  vm.createContext(ctx);
  vm.runInContext(`${helpers}\n${state}\nlet S = defaults();\nconst save = () => {};\n${lines}\n${ical}\n${mergeSrc}
${googleSrc}
    uid = () => 'u' + (++globalThis.__uid);
    globalThis.api = { parseIcs, occurrences, matchLine, normalize, merge, ruleFor, fromGoogle, toGoogle, setS: s => { S = s; }, getS: () => S };`.replace('const uid =', 'let uid ='), ctx);
  ctx.__uid = 0;
  return ctx.api;
}

module.exports = { loadWebApp };
