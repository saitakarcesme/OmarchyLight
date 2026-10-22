const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const m = {};
vm.createContext(m);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../plugin/Motion.js'), 'utf8'), m);
const closed=m.closedGeometry(640), open=m.separatedGeometry(640);
// Measured capsule widths after the circles have visibly disconnected.
for (const [t,width] of [[.25,363],[.30,368],[.40,382],[.50,386],[.65,384]]) {
  assert.ok(Math.abs(m.geometry(t,true,closed,640)[0]-width)<1.5, `reference width at ${t}s`);
}
assert.ok(m.geometry(.25,true,closed,640)[0]<384, 'separation overshoots before settling');
assert.ok(m.openScale(.15)<1 && m.openScale(0)>1.08, 'opening contracts through rest size');
assert.equal(m.openScale(.5),1);
assert.equal(m.resizedHeight(.6,472,56),56);
assert.ok(m.resizedHeight(.25,472,56)<56,'collapse preserves reference undershoot');
for (const separate of [false,true]) {
  const from=separate?closed:open;
  for(let i=0;i<=110;i++) {
    const geometry=m.geometry(i/100,separate,from,640);
    assert.ok(geometry.every(Number.isFinite));
    assert.ok(geometry.slice(5,9).every(radius=>radius>=0));
  }
  // Typing/clearing mid-gesture cannot teleport the surface or discard velocity.
  for(const t of [.08,.16,.3,.65]) {
    const position=m.geometry(t,separate,from,640);
    const velocity=m.velocityAt(t,separate,from,640);
    const next=m.geometry(.00001,!separate,position,640,velocity);
    assert.deepEqual(Array.from(m.geometry(0,!separate,position,640,velocity)),Array.from(position));
    for(let j=0;j<9;j++) assert.ok(Math.abs((next[j]-position[j])/.00001-velocity[j])<3,'velocity continuity');
  }
}
console.log('PASS measured geometry, settling, and interrupted gesture continuity');
