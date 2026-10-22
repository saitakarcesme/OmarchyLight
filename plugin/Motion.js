// Logical pixels and milliseconds, measured from the supplied 2880×1800 Retina recording.
var width = 640;
var searchHeight = 56;
var compactWidth = 384;
var categoryDiameter = 56;
var categoryGap = 8;
var rowHeight = 56;
var topFraction = 129/900;
var openDuration = 500;
var closeDuration = 100;
var resizeDuration = 600;
var idleDelay = 750;
var suggestionDelay = 300;

function spring(t, frequency, damping) {
    if(t<=0)return 0;
    var u=Math.sqrt(1-damping*damping), wd=frequency*u;
    return 1-Math.exp(-damping*frequency*t)*(Math.cos(wd*t)+damping/u*Math.sin(wd*t));
}
// Per bead: center frequency, damping, initial x, delay; radius frequency, damping, initial radius, delay.
// Frequencies are rad/s; delays are seconds.
var liquidCoefficients = [[19.382299171019728, 0.6536684670044219, 357.4541530450318, 0.0013090681647974904, 21.216280565916573, 0.6471293773336526, 8.84193850598915e-30, 0.04699663148249967], [14.623728675349723, 0.6304903328822695, 379.44492780237954, 0.013212335071773322, 14.291040009508063, 0.7144799504082886, 4.367279557632869, 0.03820292230363299], [11.416785524546773, 0.6675209812436531, 373.3933040791087, -0.004876342442322507, 12.317409129711141, 0.7652974060593524, 5.697070850589186, 0.052277504287826924], [10.374926492765008, 0.7063698312465727, 366.9876842342047, -0.01016650284424358, 11.647323044096117, 0.8524657783507514, 4.506782064371403, 0.05402647528736655]];
// Merge rows: center frequency, damping, target x, delay; radius frequency, damping, delay.
var mergeCoefficients = [[54.99999999999496, 0.5482795271467491, 418.1775140492732, 0.00037746106816256256, 16.780208684624498, 0.4000000000000001, -0.0018780789387647517], [25.66229904919337, 0.6929647693828854, 439.99999999999665, 0.0029440397710430535, 11.152585947971998, 0.4000000000000001, -0.0106387671536352], [19.5036301173973, 0.6933561843188016, 439.9999999576086, 0.002038006408194672, 10.661804266681097, 0.5048074011536332, -0.013415192161470357], [17.604785109788228, 0.7041445437405299, 435.448799662247, 0.0018091286089271508, 10.727286826603985, 0.5230342480016599, -0.013364398347196918]];
function closedGeometry(width) {
    var result=[width];
    for(var i=0;i<4;i++)result.push(liquidCoefficients[i][2]+width-640);
    for(var j=0;j<4;j++)result.push(liquidCoefficients[j][6]);
    result.push(5.37587231);return result;
}
function separatedGeometry(width) {
    return [width-256,width-219,width-155,width-91,width-27,27.5,27.5,27.5,27.5,5.37587231];
}
// Interrupted gestures retain both position and velocity. The measured canonical
// curves remain separate so a normal transition keeps its per-bead delays.
function retarget(t, from, target, velocity, frequency, damping) {
    var wd=frequency*Math.sqrt(1-damping*damping), d=from-target;
    return target+Math.exp(-damping*frequency*t)*(d*Math.cos(wd*t)+(velocity+damping*frequency*d)/wd*Math.sin(wd*t));
}
function geometry(t,separate,from,width,velocity) {
    if(t<=0)return from.slice();
    if(t>=1.1)return separate?separatedGeometry(width):closedGeometry(width);
    if(velocity) {
        var destination=separate?separatedGeometry(width):closedGeometry(width), interrupted=[];
        for(var n=0;n<10;n++)interrupted.push(retarget(t,from[n],destination[n],velocity[n],n===0?18:22,.82));
        for(var r=5;r<9;r++)interrupted[r]=Math.max(0,interrupted[r]);
        interrupted[9]=Math.max(.05,interrupted[9]);return interrupted;
    }
    var targets=[width-219,width-155,width-91,width-27];
    var mainProgress=separate?spring(t,16.2205,.626667):spring(t-.00345989,16.17529189,.91757501);
    var result=[from[0]+((separate?width-256:width)-from[0])*mainProgress];
    for(var i=0;i<4;i++) {
        var c=separate?liquidCoefficients[i]:mergeCoefficients[i];
        var target=separate?targets[i]:c[2]+width-640;
        result.push(from[i+1]+(target-from[i+1])*spring(t-c[3],c[0],c[1]));
    }
    for(var j=0;j<4;j++) {
        var r=separate?liquidCoefficients[j]:mergeCoefficients[j];
        var delay=separate?r[7]:r[6];
        result.push(Math.max(0,from[j+5]+((separate?27.5:0)-from[j+5])*spring(t-delay,r[4],r[5])));
    }
    result.push(separate?5.37587231+(25.4679428-5.37587231)*(1-spring(t-.227132686,9.35359115,.85)):14.00547727);
    return result;
}
function resizedHeight(t,from,to) {
    return t>=.6?to:from+(to-from)*spring(t,22.06974867,.83378442);
}

function openScale(seconds) {
    if(seconds>=.5)return 1;
    return 1+.12241138*(1-spring(seconds+.02177793,22.04001509,.6791864));
}

function velocityAt(t,separate,from,width,velocity) {
    var before=geometry(Math.max(0,t-.001),separate,from,width,velocity);
    var after=geometry(t+.001,separate,from,width,velocity), dt=t<.001?.001+t:.002;
    return after.map(function(value,index){return (value-before[index])/dt;});
}

// Sampled contrast from the four reference glyphs, independently of the surface
// springs. Monotone cubic interpolation avoids a speed step at each video sample.
var symbolSamples = [[0,0],[.18,0],[.2,.035],[.233333,.13],[.266667,.346],
    [.3,.49],[.333333,.60],[.366667,.71],[.4,.785],[.433333,.865],
    [.466667,.94],[.5,.98],[.533333,.995],[.6,1],[1.1,1]];
function symbolReveal(t) {
    if(t<=0)return 0;
    if(t>=.6)return 1;
    var points=symbolSamples, i=0;
    while(i<points.length-2 && t>points[i+1][0])i++;
    function slope(j) {
        if(j===0 || j===points.length-1)return 0;
        var a=(points[j][1]-points[j-1][1])/(points[j][0]-points[j-1][0]);
        var b=(points[j+1][1]-points[j][1])/(points[j+1][0]-points[j][0]);
        return a*b<=0?0:2*a*b/(a+b);
    }
    var dt=points[i+1][0]-points[i][0],u=(t-points[i][0])/dt;
    return (2*u*u*u-3*u*u+1)*points[i][1]+(u*u*u-2*u*u+u)*dt*slope(i)
        +(-2*u*u*u+3*u*u)*points[i+1][1]+(u*u*u-u*u)*dt*slope(i+1);
}
function symbolSigma(t) {
    // Logical-pixel sigma, fitted against the final sharp glyph, not Qt's blur slider.
    var sigma=Math.min(12,6.40103849*Math.exp(-10.8204031*(t-.266667)));
    return t>=.75?0:sigma*Math.min(1,Math.max(0,(.75-t)/.15));
}
function symbolOpacity(t,separate,from) {
    return separate?from+(1-from)*symbolReveal(t):from*Math.max(0,1-t/.08);
}
function symbolBlur(t,separate,from) {
    return separate?from*symbolSigma(t)/12:from;
}

function visibilityBase(t,opening) {
    return opening?openScale(t):1+.08*Math.pow(Math.max(0,Math.min(1,t/.1)),1.25);
}
function visibilityScale(t,opening,from,velocity,interrupted) {
    var base=visibilityBase(t,opening);
    if(!interrupted)return base;
    // A short Hermite correction preserves both position and velocity when
    // Super+Space reverses an animation. It vanishes with zero velocity, leaving
    // the measured canonical curve unchanged for the rest of the transition.
    var duration=opening?.15:.1,u=Math.min(1,Math.max(0,t/duration));
    var baseVelocity=visibilityBaseVelocity(0,opening);
    var delta=from-visibilityBase(0,opening),dv=velocity-baseVelocity;
    return base+delta*(2*u*u*u-3*u*u+1)+dv*duration*(u*u*u-2*u*u+u);
}
function visibilityBaseVelocity(t,opening) {
    if(!opening)return t<=0 || t>=.1?0:Math.pow(t/.1,.25);
    if(t>=.5)return 0;
    var w=22.04001509,z=.6791864,wd=w*Math.sqrt(1-z*z),phase=t+.02177793;
    return -.12241138*w*w/wd*Math.exp(-z*w*phase)*Math.sin(wd*phase);
}
function visibilityVelocity(t,opening,from,velocity,interrupted) {
    var base=visibilityBaseVelocity(t,opening);
    if(!interrupted)return base;
    var duration=opening?.15:.1,u=Math.min(1,Math.max(0,t/duration));
    var delta=from-visibilityBase(0,opening),dv=velocity-visibilityBaseVelocity(0,opening);
    return base+delta*(6*u*u-6*u)/duration+dv*(3*u*u-4*u+1);
}
