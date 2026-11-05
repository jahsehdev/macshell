.pragma library
var labelSize = 15;
var captionSize = 12;
var buttonSize = 13;
var iconSize = 18;
var iconStroke = 2.6;
function icon(page) {
    return ({music:"toolMusic",pomodoro:"timer",water:"toolWater",shelf:"toolShelf",todo:"toolTodo",calendar:"calendar",weather:"weather",stats:"stats",timer:"timer",recording:"recording",downloads:"download"})[page] || "toolMusic";
}
