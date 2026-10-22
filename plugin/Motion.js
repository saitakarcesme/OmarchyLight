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
var liquidCoefficients = [[19.382299171019728, 0.6536684670044219, 357.4541530450318, 0.0013090681647974904, 21.216280565916573, 0.6471293773336526, 8.84193850598915e-30, 0.04699663148249967], [14.623728675349723, 0.6304903328822695, 379.44492780237954, 0.013212335071773322, 14.291040009508063, 0.7144799504082886, 4.367279557632869, 0.03820292230363299], [11.416785524546773, 0.6675209812436531, 373.3933040791087, -0.004876342442322507, 12.317409129711141, 0.7652974060593524, 5.697070850589186, 0.052277504287826924], [10.374926492765008, 0.7063698312465727, 366.9876842342047, -0.01016650284424358, 11.647323044096117, 0.8524657783507514, 4.506782064371403, 0.05402647528736655]];
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
