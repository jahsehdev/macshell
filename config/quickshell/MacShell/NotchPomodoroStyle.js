.pragma library
var modes = ["focus", "short", "long", "quick", "custom"];
function name(mode) { return ({focus:"Work",short:"Short Break",long:"Long Break",quick:"Quick Timer",custom:"Custom"})[mode] || "Work"; }
function icon(mode) { return ({focus:"pomoWork",short:"pomoRest",long:"pomoLong",quick:"timer",custom:"pomoCustom"})[mode] || "pomoWork"; }
function tint(mode) { return ({focus:"#C9AF91",short:"#95BEAA",long:"#A5B3D1",quick:"#B8A5D3",custom:"#D7AE99"})[mode] || "#C9AF91"; }
function activityName(id) { return ({music:"Music",pomodoro:"Pomodoro",water:"Water",shelf:"Shelf",todo:"Todo",calendar:"Calendar",weather:"Weather",stats:"System"})[id] || id; }

function phaseName(mode) { return mode === "short" || mode === "long" ? "Break" : mode === "quick" ? "Timer" : "Focus"; }
function time(ms) { var seconds=Math.ceil(Math.max(0,ms)/1000);var minutes=Math.floor(seconds/60);return (minutes<10?"0":"")+minutes+":"+(seconds%60<10?"0":"")+seconds%60; }
