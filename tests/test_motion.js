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
// Reference glyph contrast and Gaussian width are independent of bead geometry.
for (const [t,opacity,sigma] of [[.3,.49,4.65],[.4,.785,1.46],[.5,.98,.525]]) {
  assert.ok(Math.abs(m.symbolReveal(t)-opacity)<.025,`glyph contrast at ${t}`);
  assert.ok(Math.abs(m.symbolSigma(t)-sigma)<.25,`glyph blur at ${t}`);
}
let previous=-1;
for(let i=0;i<=1100;i++) {
  const t=i/1000,value=m.symbolReveal(t);
  assert.ok(value>=previous-1e-9 && value>=0 && value<=1,'contrast must not flash or overshoot');
  assert.ok(m.symbolSigma(t)>=0 && m.symbolSigma(t)<=12);
  previous=value;
}
for(const from of [0,.13,.49,.78,1]) {
  assert.equal(m.symbolOpacity(0,true,from),from);
  assert.equal(m.symbolOpacity(0,false,from),from);
  assert.equal(m.symbolOpacity(.08,false,from),0);
}
assert.equal(m.symbolReveal(.6),1);
assert.equal(m.symbolSigma(.75),0);
console.log('PASS measured glyph reveal and interrupted opacity continuity');
for(const opening of [true,false]) {
  for(const t of (opening?[.035,.08,.15,.3]:[.015,.04,.07])) {
    const position=m.visibilityScale(t,opening,1,0,false);
    const velocity=m.visibilityVelocity(t,opening,1,0,false);
    assert.equal(m.visibilityScale(0,!opening,position,velocity,true),position,'toggle scale must not jump');
    const v=m.visibilityVelocity(0,!opening,position,velocity,true);
    assert.ok(Math.abs(v-velocity)<.015,'toggle velocity must remain continuous');
    const end=opening?.1:.5;
    assert.equal(m.visibilityScale(end,!opening,position,velocity,true),m.visibilityBase(end,!opening));
  }
}
console.log('PASS open/close reversal position and velocity');
for(const [from,to] of [[472,56],[56,472],[136,360]]) {
  for(const t of [.02,.08,.15,.3]) {
    const position=m.resizedHeight(t,from,to,0),velocity=m.resizeVelocity(t,from,to,0);
    assert.ok(Math.abs(m.resizedHeight(0,position,from,velocity)-position)<1e-9,'result resize position continuity');
    assert.ok(Math.abs(m.resizeVelocity(0,position,from,velocity)-velocity)<1e-9,'result resize velocity continuity');
    const numeric=(m.resizedHeight(t+.000001,from,to)-m.resizedHeight(t-.000001,from,to))/.000002;
    assert.ok(Math.abs(numeric-velocity)<.0001,'height velocity agrees with rendered trajectory');
    assert.equal(m.resizedHeight(.6,position,from,velocity),from);
  }
}
console.log('PASS result height reversals preserve position and velocity');
